package com.bluelight.bluelight

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val cip186ChannelName = "com.yuti/cip30"
    private val cip186HandlerMethod = "handleCip30DeepLink"
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, cip186ChannelName)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        dispatchCip186(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        dispatchCip186(intent)
    }

    private fun dispatchCip186(intent: Intent?) {
        val data = intent?.data ?: return
        val scheme = data.scheme ?: return
        val isCustom = scheme == "cip30dl-yuti"
        val isAppLink = scheme == "https" && (data.path?.startsWith("/cip30dl/v1/") == true)
        if (!isCustom && !isAppLink) return
        channel?.invokeMethod(cip186HandlerMethod, data.toString())
    }
}
