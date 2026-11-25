package `in`.abhijithvijayan.opendash.companion

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var bridge: AdbBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val b = AdbBridge(this, AdbEvents(messenger))
        bridge = b
        AdbHostApi.setUp(messenger, b)
    }

    override fun onDestroy() {
        bridge?.disconnect()
        super.onDestroy()
    }
}
