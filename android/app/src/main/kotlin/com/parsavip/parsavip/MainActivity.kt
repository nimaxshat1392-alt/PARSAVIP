package com.parsavip.parsavip

import android.content.Intent
import android.net.VpnService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.parsavip.parsavip/xray"
    private val EVENT_CHANNEL = "com.parsavip.parsavip/xray_events"
    private val VPN_PERMISSION_CODE = 0x0F01
    private var pendingConfig: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val config = call.argument<String>("config")
                        if (config.isNullOrEmpty()) {
                            result.error("INVALID", "Config empty", null)
                            return@setMethodCallHandler
                        }
                        pendingConfig = config
                        val intent = VpnService.prepare(this)
                        if (intent != null) {
                            startActivityForResult(intent, VPN_PERMISSION_CODE)
                            result.success(false)
                        } else {
                            startVpn(config)
                            result.success(true)
                        }
                    }
                    "stop" -> {
                        val i = Intent(this, ParsaVpnService::class.java)
                        i.action = ParsaVpnService.ACTION_STOP
                        startService(i)
                        result.success(true)
                    }
                    "status" -> {
                        result.success(mapOf("connected" to ParsaVpnService.isConnected))
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    ParsaVpnService.eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    ParsaVpnService.eventSink = null
                }
            })
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_PERMISSION_CODE && resultCode == RESULT_OK) {
            pendingConfig?.let { startVpn(it) }
        }
        pendingConfig = null
    }

    private fun startVpn(config: String) {
        val i = Intent(this, ParsaVpnService::class.java)
        i.action = ParsaVpnService.ACTION_START
        i.putExtra("config", config)
        startService(i)
    }
}
