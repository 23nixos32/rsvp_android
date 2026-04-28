package com.rsvpreader.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.view.KeyEvent

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.rsvpreader.app/volume_keys"
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        return when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> {
                channel?.invokeMethod("volumeUp", null)
                true
            }
            KeyEvent.KEYCODE_VOLUME_DOWN -> {
                channel?.invokeMethod("volumeDown", null)
                true
            }
            else -> super.onKeyDown(keyCode, event)
        }
    }
}
