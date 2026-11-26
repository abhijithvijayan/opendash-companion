package `in`.abhijithvijayan.opendash.companion

import java.math.BigInteger
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.security.KeyPairGenerator
import java.security.interfaces.RSAPrivateCrtKey
import java.util.Base64
import org.junit.Assert.assertEquals
import org.junit.Test

class AdbPubkeyTest {
    private val key = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair().private as RSAPrivateCrtKey

    private fun pem(der: ByteArray) =
        ("-----BEGIN PRIVATE KEY-----\n" + Base64.getMimeEncoder(64, "\n".toByteArray()).encodeToString(der) + "\n-----END PRIVATE KEY-----\n").toByteArray()

    /// The modulus and exponent adbd will read back out of the line.
    private fun decode(line: String): Pair<BigInteger, BigInteger> {
        val b = ByteBuffer.wrap(Base64.getDecoder().decode(line.substringBefore(' '))).order(ByteOrder.LITTLE_ENDIAN)
        assertEquals(64, b.int)
        b.int
        val n = ByteArray(256).also { b.get(it) }.reversedArray()
        b.position(b.position() + 256)
        return BigInteger(1, n) to BigInteger.valueOf(b.int.toLong())
    }

    @Test
    fun `a full PKCS 8 key gives its modulus and exponent`() {
        val line = AdbPubkey.line(pem(key.encoded), "opendash-companion")
        assertEquals(key.modulus to key.publicExponent, decode(line))
        assertEquals("opendash-companion", line.substringAfter(' '))
    }

    // Android 10's Conscrypt hands back a plain RSAPrivateKey for a PKCS#8
    // key, with no public exponent on it. A key whose CRT numbers are zero
    // does the same on the JVM. The exponent is in the key file either way.
    @Test
    fun `a key the provider does not return as a CRT key still gives its exponent`() {
        val line = AdbPubkey.line(pem(pkcs8WithoutCrt(key.modulus, key.publicExponent, key.privateExponent)), "x")
        assertEquals(key.modulus to key.publicExponent, decode(line))
    }

    private fun pkcs8WithoutCrt(n: BigInteger, e: BigInteger, d: BigInteger): ByteArray {
        val zero = BigInteger.ZERO
        val rsa = seq(int(zero), int(n), int(e), int(d), int(zero), int(zero), int(zero), int(zero), int(zero))
        val algorithm = seq(tlv(0x06, byteArrayOf(0x2a, 0x86.toByte(), 0x48, 0x86.toByte(), 0xf7.toByte(), 0x0d, 0x01, 0x01, 0x01)), byteArrayOf(0x05, 0x00))
        return seq(int(zero), algorithm, tlv(0x04, rsa))
    }

    private fun int(v: BigInteger) = tlv(0x02, v.toByteArray())
    private fun seq(vararg parts: ByteArray) = tlv(0x30, parts.fold(ByteArray(0)) { a, b -> a + b })
    private fun tlv(tag: Int, body: ByteArray): ByteArray {
        val len = body.size
        val head = when {
            len < 0x80 -> byteArrayOf(len.toByte())
            len < 0x100 -> byteArrayOf(0x81.toByte(), len.toByte())
            else -> byteArrayOf(0x82.toByte(), (len shr 8).toByte(), len.toByte())
        }
        return byteArrayOf(tag.toByte()) + head + body
    }
}
