package `in`.abhijithvijayan.opendash.companion

import android.content.pm.PackageManager
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.io.RandomAccessFile
import java.security.MessageDigest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/// Runs on a device: what PackageManager reports for an APK file differs
/// between Android versions (on Android 10 a signed file read as unsigned).
@RunWith(AndroidJUnit4::class)
class ApkInspectorTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext
    private val pm = context.packageManager

    /// This app's own APK and the certificate it was installed with.
    private val apk = File(context.applicationInfo.sourceDir)

    @Suppress("DEPRECATION")
    private val installedCert: String = pm.getPackageInfo(context.packageName, PackageManager.GET_SIGNATURES)
        .signatures!!.single().let { sha256(it.toByteArray()) }

    @Test
    fun aSignedApkFileReportsTheCertificateItIsSignedWith() {
        val info = ApkInspector.inspect(pm, apk.path)!!
        assertEquals(context.packageName, info.packageName)
        assertEquals(listOf(installedCert), info.certSha256)
    }

    @Test
    fun aTamperedApkReportsNoSigner() {
        val copy = File(context.cacheDir, "tampered.apk")
        apk.copyTo(copy, overwrite = true)
        // One byte inside the signed contents, well before the signing block.
        RandomAccessFile(copy, "rw").use { f ->
            f.seek(f.length() / 3)
            val b = f.read()
            f.seek(f.length() / 3)
            f.write(b xor 0xff)
        }
        val info = ApkInspector.inspect(pm, copy.path)
        assertTrue("tampered APK still reported signers: ${info?.certSha256}", info == null || info.certSha256.isEmpty())
    }

    private fun sha256(b: ByteArray) = MessageDigest.getInstance("SHA-256").digest(b).joinToString("") { "%02x".format(it) }
}
