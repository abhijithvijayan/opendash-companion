package `in`.abhijithvijayan.opendash.companion

import java.math.BigInteger
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Base64

/// The adb public-key line (`<base64> <name>`) for an RSA private key in
/// PKCS#8 PEM: the 524-byte struct adbd reads from `adb_keys`.
object AdbPubkey {
    private const val WORDS = 64

    fun line(privateKeyPem: ByteArray, name: String): String {
        val body = String(privateKeyPem)
            .lines()
            .filterNot { it.startsWith("-----") }
            .joinToString("")
        val (n, e) = modulusAndExponent(Base64.getMimeDecoder().decode(body))
        return Base64.getEncoder().encodeToString(encode(n, e)) + " " + name
    }

    /// Read from the key file itself, not from a parsed key: Android 10's
    /// Conscrypt returns a plain RSAPrivateKey for it, which has no public
    /// exponent. PKCS#8 is SEQUENCE { version, algorithm, OCTET STRING
    /// RSAPrivateKey }, and RSAPrivateKey is SEQUENCE { version, n, e, ... }.
    private fun modulusAndExponent(pkcs8: ByteArray): Pair<BigInteger, BigInteger> {
        val outer = Der(pkcs8).enter(0x30)
        outer.skip(0x02)
        outer.skip(0x30)
        val rsa = Der(outer.read(0x04)).enter(0x30)
        rsa.skip(0x02)
        return BigInteger(1, rsa.read(0x02)) to BigInteger(1, rsa.read(0x02))
    }

    private class Der(private val b: ByteArray, private var at: Int = 0, private val end: Int = b.size) {
        fun read(tag: Int): ByteArray {
            require(at < end && (b[at].toInt() and 0xff) == tag) { "Not an RSA PKCS#8 key" }
            at++
            var len = b[at++].toInt() and 0xff
            if (len >= 0x80) {
                val count = len and 0x7f
                require(count in 1..3) { "Not an RSA PKCS#8 key" }
                len = 0
                repeat(count) { len = (len shl 8) or (b[at++].toInt() and 0xff) }
            }
            require(at + len <= end) { "Not an RSA PKCS#8 key" }
            return b.copyOfRange(at, at + len).also { at += len }
        }

        fun skip(tag: Int) {
            read(tag)
        }

        fun enter(tag: Int) = read(tag).let { Der(it) }
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
