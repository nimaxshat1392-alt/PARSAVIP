package com.parsavip.parsavip

import android.content.Intent
import android.net.VpnService
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val TAG = "MainActivity"
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
                        val uri = call.argument<String>("config")
                        if (uri.isNullOrEmpty()) {
                            result.error("INVALID", "Config empty", null)
                            return@setMethodCallHandler
                        }
                        pendingConfig = uri
                        val intent = VpnService.prepare(this)
                        if (intent != null) {
                            startActivityForResult(intent, VPN_PERMISSION_CODE)
                            result.success(false)
                        } else {
                            startV2Ray(uri)
                            result.success(true)
                        }
                    }
                    "stop" -> {
                        try {
                            val i = Intent()
                            i.setClassName(packageName, "com.v2ray.ang.service.V2RayVpnService")
                            i.action = "com.v2ray.ang.action.STOP"
                            startService(i)
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "stop error", e)
                            result.error("STOP_FAIL", e.message, null)
                        }
                    }
                    "status" -> {
                        result.success(mapOf("connected" to false))
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    Log.i(TAG, "Event channel listening")
                }
                override fun onCancel(arguments: Any?) {
                    Log.i(TAG, "Event channel cancelled")
                }
            })
    }

    override fun onActivityResult(requestCode: Int, requestCode2: Int, data: Intent?) {
        super.onActivityResult(requestCode, requestCode2, data)
        if (requestCode == VPN_PERMISSION_CODE && requestCode2 == RESULT_OK) {
            pendingConfig?.let { startV2Ray(it) }
        }
        pendingConfig = null
    }

    private fun startV2Ray(uri: String) {
        try {
            val i = Intent()
            i.setClassName(packageName, "com.v2ray.ang.service.V2RayVpnService")
            i.action = "com.v2ray.ang.action.START"
            i.putExtra("config", uri)
            startService(i)
            Log.i(TAG, "V2Ray service started")
        } catch (e: Exception) {
            Log.e(TAG, "start error", e)
        }
    }
}
