package `in`.abhijithvijayan.opendash.companion

import android.content.pm.PackageManager
import java.security.MessageDigest

/// Package, version and signer certificates (SHA-256) of an APK file.
object ApkInspector {
    fun inspect(pm: PackageManager, path: String): ApkInfo? {
        // On older Android (seen on 10), a file (not an installed app) gets its
        // signers read only for GET_SIGNATURES: GET_SIGNING_CERTIFICATES alone
        // left signingInfo null, and every release read as unsigned. Either
        // way Android verifies the signature first: a tampered file has none.
        @Suppress("DEPRECATION")
        val info = pm.getPackageArchiveInfo(path, PackageManager.GET_SIGNING_CERTIFICATES or PackageManager.GET_SIGNATURES)
            ?: return null
        val signing = info.signingInfo
        @Suppress("DEPRECATION")
        val certs = when {
            signing == null -> info.signatures?.toList().orEmpty()
            signing.hasMultipleSigners() -> signing.apkContentsSigners.toList()
            else -> signing.signingCertificateHistory.toList()
        }
        val sha = certs.map { sig ->
            MessageDigest.getInstance("SHA-256").digest(sig.toByteArray()).joinToString("") { "%02x".format(it) }
        }
        return ApkInfo(info.packageName, info.versionName ?: "", info.longVersionCode, sha)
    }
}
