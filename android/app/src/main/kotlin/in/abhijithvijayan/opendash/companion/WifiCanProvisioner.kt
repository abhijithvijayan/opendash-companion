package `in`.abhijithvijayan.opendash.companion

import android.util.Base64
import io.grpc.Attributes
import io.grpc.EquivalentAddressGroup
import io.grpc.ManagedChannel
import io.grpc.NameResolver
import io.grpc.Status
import io.grpc.StatusException
import io.grpc.StatusRuntimeException
import io.grpc.okhttp.OkHttpChannelBuilder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.asExecutor
import kotlinx.coroutines.withContext
import wifican.Wifican.Command
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.SocketAddress
import java.net.URI
import java.util.concurrent.TimeUnit
import wifican.WifiCanRpcGrpcKt

/// Injects this phone's adb public key into a scooter over the firmware's
/// unauthenticated `wifican` gRPC service (root, port 50005), then restarts
/// adbd so it accepts us. Only Gen 1 (MoveOS 3) heads implement
/// `ExecuteADBCommand`; a Gen 2 / MoveOS 4 head answers UNIMPLEMENTED, which we
/// surface so the caller can route it to the sealed-scooter screen.
object WifiCanProvisioner {
    private const val PORT = 50005
    private const val CALL_DEADLINE_SECONDS = 10L

    private const val LEGACY_KEY_FILE = "/data/misc/adb/adbkeymoveos3_pub_prod"
    private const val ADB_KEYS_FILE = "/data/misc/adb/adb_keys"
    private const val STAGED_KEY_FILE = "/data/local/tmp/opendash_adb_keys"

    /// [pubKeyLine] is the adb key store line to inject, e.g. "<base64> adb@opendash".
    suspend fun provision(host: String, pubKeyLine: String): ProvisionReply = withContext(Dispatchers.IO) {
        val channel = try {
            channel(host)
        } catch (e: Exception) {
            // Host/zone resolution failure — we never reached the service.
            return@withContext ProvisionReply("unreachable", e.message ?: e.javaClass.simpleName)
        }
        try {
            // 1. Force manufacturing mode: keeps IPv4 5555/50005 open. Never set "cust".
            exec(channel, "setprop persist.ola.security.scootermode mfg")

            // 2. Pick the key route. A legacy (MoveOS 3) head keeps a dedicated key
            //    file; writing to it AND adb_keys is what that generation honours.
            //    A standard head has no such file: stage the key and bind-mount it
            //    over /adb_keys.
            val probe = exec(channel, "ls $LEGACY_KEY_FILE")
            val isLegacy = probe.contains("adbkeymoveos3_pub_prod") &&
                !probe.contains("No such file", ignoreCase = true)

            if (isLegacy) {
                exec(channel, "echo $pubKeyLine>$LEGACY_KEY_FILE")
                exec(channel, "echo $pubKeyLine>$ADB_KEYS_FILE")
            } else {
                exec(channel, "echo $pubKeyLine>$STAGED_KEY_FILE")
                exec(channel, "umount -l /adb_keys || true")
                exec(channel, "mount --bind $STAGED_KEY_FILE /adb_keys")
            }

            // 3. Bounce adbd so it re-reads the key store.
            exec(channel, "stop adbd;start adbd")

            ProvisionReply("ok", null)
        } catch (e: StatusException) {
            ProvisionReply(outcomeFor(e.status), e.message)
        } catch (e: StatusRuntimeException) {
            ProvisionReply(outcomeFor(e.status), e.message)
        } catch (e: Exception) {
            ProvisionReply("failed", e.message ?: e.javaClass.simpleName)
        } finally {
            runCatching { channel.shutdownNow() }
        }
    }

    private fun outcomeFor(status: Status): String = when (status.code) {
        Status.Code.UNIMPLEMENTED -> "unimplemented"
        Status.Code.UNAVAILABLE, Status.Code.DEADLINE_EXCEEDED -> "unreachable"
        else -> "failed"
    }

    /// Runs one shell command via ExecuteADBCommand and returns its output.
    ///
    /// ExecuteADBCommand is NOT a shell: it splits cmd_msg on whitespace and
    /// execs the tokens directly (and already runs as root). So anything with
    /// spaces, pipes or redirects is base64-wrapped and handed to `sh -c` as a
    /// single token, with every space written as `${IFS}` for sh to expand.
    private suspend fun exec(channel: ManagedChannel, command: String): String {
        val b64 = Base64.encodeToString(command.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
        val wrapped = "echo -n '$b64'|base64 -d|sh".replace(" ", "\${IFS}")
        val cmdMsg = "sh -c $wrapped"

        val stub = WifiCanRpcGrpcKt.WifiCanRpcCoroutineStub(channel)
            .withDeadlineAfter(CALL_DEADLINE_SECONDS, TimeUnit.SECONDS)
        val response = stub.executeADBCommand(Command.newBuilder().setCmdMsg(cmdMsg).build())
        return response.statusMsg ?: ""
    }

    /// Builds a plaintext gRPC channel to [host]:50005.
    ///
    /// The host may be a scoped IPv6 link-local such as `fe80::1%wlan0`. gRPC's
    /// default DNS name resolver mangles the `%zone` when it parses the target
    /// as a URI, so we resolve the host ourselves with the same
    /// `InetAddress.getByName` the adb/kadb path uses (which keeps the scope id
    /// as a scoped Inet6Address) and hand gRPC the already-resolved address
    /// through a fixed name resolver, bypassing URI parsing entirely.
    private fun channel(host: String): ManagedChannel {
        val address = InetSocketAddress(InetAddress.getByName(host), PORT)
        return OkHttpChannelBuilder.forTarget("fixed:///opendash")
            .nameResolverFactory(FixedAddressResolverFactory(address))
            .usePlaintext()
            .executor(Dispatchers.IO.asExecutor())
            .build()
    }

    /// A one-address name resolver: gRPC gets exactly the [SocketAddress] we
    /// resolved, so it never re-parses a zoned IPv6 literal.
    private class FixedAddressResolverFactory(
        private val address: SocketAddress,
    ) : NameResolver.Factory() {
        override fun getDefaultScheme(): String = "fixed"

        override fun newNameResolver(targetUri: URI, args: NameResolver.Args): NameResolver =
            object : NameResolver() {
                override fun getServiceAuthority(): String = "opendash-scooter"

                override fun start(listener: Listener2) {
                    listener.onResult(
                        ResolutionResult.newBuilder()
                            .setAddresses(listOf(EquivalentAddressGroup(address)))
                            .setAttributes(Attributes.EMPTY)
                            .build(),
                    )
                }

                override fun shutdown() {}
            }
    }
}
