package `in`.abhijithvijayan.opendash.companion

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.core.content.FileProvider
import com.flyfishxu.kadb.Kadb
import com.flyfishxu.kadb.cert.KadbCert
import com.flyfishxu.kadb.cert.OkioFilePrivateKeyStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okio.Buffer
import okio.ForwardingSource
import okio.Path.Companion.toOkioPath
import okio.source
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket

class AdbBridge(private val context: Context, private val events: AdbEvents) : AdbHostApi {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    @Volatile private var kadb: Kadb? = null

    /// Set by [cancelTransfer]; the counting source bails on it so a push or
    /// install stops mid-transfer. Reset at the start of each transfer.
    @Volatile private var cancelRequested = false

    private class TransferCancelled : Exception()

    init {
        KadbCert.configure(OkioFilePrivateKeyStore(File(context.filesDir, "adbkey").toOkioPath()))
        // Copies handed to the installer or a share target ([shareable]). Both
        // have their own copy by the time this app starts again.
        for (dir in listOf("downloads", "reports")) runCatching { File(context.cacheDir, dir).deleteRecursively() }
    }

    override suspend fun connect(host: String, port: Long): ConnectReply = withContext(Dispatchers.IO) {
        disconnectNow()
        val p = port.toInt()
        try {
            Socket().use { it.connect(InetSocketAddress(host, p), 1500) }
        } catch (e: Exception) {
            return@withContext ConnectReply("unreachable", e.javaClass.simpleName)
        }
        // A short-lived probe decides "accepted or not": adbd that doesn't know
        // this key just stops answering, so only a short read timeout tells.
        val probe = Kadb.create(host, p, connectTimeout = 3000, socketTimeout = 6000)
        val accepted = try {
            probe.shell("echo ok").output.trim() == "ok"
        } catch (e: Exception) {
            false
        } finally {
            runCatching { probe.close() }
        }
        if (!accepted) return@withContext ConnectReply("unauthorized", null)
        // The working client waits long: a cold start or the installer's dexopt
        // on the head unit can be silent for well over ten seconds.
        kadb = Kadb.create(host, p, connectTimeout = 3000, socketTimeout = 120_000)
        ConnectReply("ok", null)
    }

    override suspend fun provision(host: String): ProvisionReply = withContext(Dispatchers.IO) {
        // adbd reads the key store line "<base64> <comment>"; keep only the key
        // bytes from publicKey() and tag it so the injected key is identifiable.
        val keyLine = publicKey().substringBefore(' ') + " adb@opendash"
        val reply = WifiCanProvisioner.provision(host, keyLine)
        if (reply.outcome != "ok") return@withContext reply
        // Key injected and adbd bounced. Give adbd a moment to accept us with a
        // best-effort probe; the Dart layer re-runs connect() and decides, so we
        // report "ok" regardless of what this probe sees.
        runCatching {
            val probe = Kadb.create(host, 5555, connectTimeout = 3000, socketTimeout = 6000)
            try {
                probe.shell("echo ok")
            } finally {
                runCatching { probe.close() }
            }
        }
        ProvisionReply("ok", null)
    }

    override suspend fun setScooterMode(host: String, mode: String): ProvisionReply = withContext(Dispatchers.IO) {
        WifiCanProvisioner.setScooterMode(host, mode)
    }

    override suspend fun shell(command: String): ShellReply = withContext(Dispatchers.IO) {
        val k = kadb ?: throw AdbApiError("not_connected", "Not connected", null)
        try {
            val r = k.shell(command)
            ShellReply(r.allOutput, r.exitCode.toLong())
        } catch (e: Exception) {
            dropOnFailure()
            throw AdbApiError("connection_lost", e.message ?: e.javaClass.simpleName, null)
        }
    }

    /// The file as a source that reports how much of it has been read.
    private fun counting(file: File): ForwardingSource {
        val total = file.length()
        var sent = 0L
        var lastPosted = 0L
        return object : ForwardingSource(file.source()) {
            override fun read(sink: Buffer, byteCount: Long): Long {
                if (cancelRequested) throw TransferCancelled()
                val n = super.read(sink, byteCount)
                if (n > 0) {
                    sent += n
                    if (sent - lastPosted >= 256 * 1024 || sent == total) {
                        lastPosted = sent
                        val s = sent
                        scope.launch { runCatching { events.installProgress(s, total) } }
                    }
                }
                return n
            }
        }
    }

    override suspend fun push(localPath: String, remotePath: String) = withContext(Dispatchers.IO) {
        val k = kadb ?: throw AdbApiError("not_connected", "Not connected", null)
        val file = File(localPath)
        cancelRequested = false
        try {
            counting(file).use { k.push(it, remotePath, mode = 420, lastModifiedMs = file.lastModified()) }
        } catch (e: Exception) {
            // A rider-requested stop isn't a failure: leave the connection up.
            if (cancelRequested) throw AdbApiError("cancelled", "Cancelled", null)
            dropOnFailure()
            throw AdbApiError("connection_lost", e.message ?: e.javaClass.simpleName, null)
        }
    }

    override suspend fun pull(remotePath: String, localPath: String) = withContext(Dispatchers.IO) {
        val k = kadb ?: throw AdbApiError("not_connected", "Not connected", null)
        try {
            k.pull(File(localPath), remotePath)
        } catch (e: Exception) {
            File(localPath).delete()
            dropOnFailure()
            throw AdbApiError("connection_lost", e.message ?: e.javaClass.simpleName, null)
        }
    }

    override suspend fun install(apkPath: String, options: List<String>): String = withContext(Dispatchers.IO) {
        val k = kadb ?: throw AdbApiError("not_connected", "Not connected", null)
        val file = File(apkPath)
        val total = file.length()
        val counting = counting(file)
        cancelRequested = false
        try {
            counting.use { k.install(it, total, *options.toTypedArray()) }
            "Success"
        } catch (e: TransferCancelled) {
            throw AdbApiError("cancelled", "Cancelled", null)
        } catch (e: IllegalStateException) {
            if (cancelRequested) throw AdbApiError("cancelled", "Cancelled", null)
            throw AdbApiError("install_failed", e.message ?: "Install failed", null)
        } catch (e: Exception) {
            if (cancelRequested) throw AdbApiError("cancelled", "Cancelled", null)
            dropOnFailure()
            throw AdbApiError("connection_lost", e.message ?: e.javaClass.simpleName, null)
        }
    }

    override fun cancelTransfer() {
        cancelRequested = true
    }

    override fun disconnect() {
        scope.launch(Dispatchers.IO) { disconnectNow() }
    }

    override fun publicKey(): String {
        val pem = KadbCert.ensureReady().privateKeyPem
        return AdbPubkey.line(pem, "opendash-companion")
    }

    override fun inspectApk(path: String): ApkInfo? = ApkInspector.inspect(context.packageManager, path)

    override fun canInstallOnPhone(): Boolean = context.packageManager.canRequestPackageInstalls()

    override fun openInstallPermission() {
        val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    override fun installOnPhone(apkPath: String) {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", shareable(File(apkPath), "downloads"))
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    override fun filesDir(): String = context.filesDir.path

    override fun shareFile(path: String, mimeType: String, subject: String) {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", shareable(File(path), "reports"))
        val send = Intent(Intent.ACTION_SEND)
            .setType(mimeType)
            .putExtra(Intent.EXTRA_STREAM, uri)
            .putExtra(Intent.EXTRA_SUBJECT, subject)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        context.startActivity(Intent.createChooser(send, subject).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /// FileProvider serves only cacheDir/<dir>/. Dart's temp directory is
    /// code_cache, outside it, so a file from there is copied in first.
    private fun shareable(file: File, dir: String): File {
        val root = File(context.cacheDir, dir).canonicalFile
        if (file.canonicalPath.startsWith(root.path + File.separator)) return file
        root.mkdirs()
        root.listFiles()?.forEach { it.delete() }
        val out = File(root, file.name)
        file.copyTo(out, overwrite = true)
        return out
    }

    private fun dropOnFailure() {
        val k = kadb ?: return
        if (!k.connectionCheck()) disconnectNow()
    }

    private fun disconnectNow() {
        val k = kadb
        kadb = null
        runCatching { k?.close() }
    }
}
