package `in`.abhijithvijayan.opendash.companion

import java.math.BigInteger
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.KeyFactory
import java.security.interfaces.RSAPrivateCrtKey
import java.security.spec.PKCS8EncodedKeySpec
import android.util.Base64

/// The adb public-key line (`<base64> <name>`) for an RSA private key in
/// PKCS#8 PEM: the 524-byte struct adbd reads from `adb_keys`.
object AdbPubkey {
    private const val WORDS = 64

    fun line(privateKeyPem: ByteArray, name: String): String {
        val body = String(privateKeyPem)
            .lines()
            .filterNot { it.startsWith("-----") }
            .joinToString("")
        val key = KeyFactory.getInstance("RSA")
            .generatePrivate(PKCS8EncodedKeySpec(Base64.decode(body, Base64.DEFAULT))) as RSAPrivateCrtKey
        return Base64.encodeToString(encode(key.modulus, key.publicExponent), Base64.NO_WRAP) + " " + name
    }

    private fun encode(n: BigInteger, e: BigInteger): ByteArray {
        val r32 = BigInteger.ONE.shiftLeft(32)
        val n0inv = n.mod(r32).modInverse(r32).negate().mod(r32)
        val rr = BigInteger.ONE.shiftLeft(WORDS * 32 * 2).mod(n)
        val buf = ByteBuffer.allocate(4 + 4 + WORDS * 4 * 2 + 4).order(ByteOrder.LITTLE_ENDIAN)
        buf.putInt(WORDS)
        buf.putInt(n0inv.toInt())
        buf.put(littleEndian(n))
        buf.put(littleEndian(rr))
        buf.putInt(e.toInt())
        return buf.array()
    }

    private fun littleEndian(v: BigInteger): ByteArray {
        val be = v.toByteArray().dropWhile { it == 0.toByte() }.toByteArray()
        val out = ByteArray(WORDS * 4)
        for (i in be.indices) out[i] = be[be.size - 1 - i]
        return out
    }
}
