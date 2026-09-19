package com.parsavip.parsavip

import android.content.Intent
import android.net.VpnService
import com.v2ray.ang.service.V2RayVpnService
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

        // کانال متدها برای ارتباط Flutter با Native
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        val uri = call.argument<String>("config")
                        if (uri.isNullOrEmpty()) {
                            result.error("INVALID", "Config URI is empty", null)
                            return@setMethodCallHandler
                        }
                        pendingConfig = uri
                        // درخواست مجوز VPN از کاربر
                        val intent = VpnService.prepare(this)
                        if (intent != null) {
                            startActivityForResult(intent, VPN_PERMISSION_CODE)
                            result.success(false) // منتظر تأیید کاربر
                        } else {
                            // مجوز قبلاً داده شده، سرویس را استارت بزن
                            startV2RayService(uri)
                            result.success(true)
                        }
                    }
                    "stop" -> {
                        val i = Intent(this, V2RayVpnService::class.java)
                        i.action = V2RayVpnService.ACTION_STOP
                        startService(i)
                        result.success(true)
                    }
                    "status" -> {
                        result.success(mapOf("connected" to V2RayVpnService.isRunning))
                    }
                    else -> result.notImplemented()
                }
            }

        // کانال رویدادها برای دریافت وضعیت از Native
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    // در اینجا می‌توانید یک BroadcastReceiver برای دریافت وضعیت از سرویس ثبت کنید
                    // برای سادگی، فعلاً از یک متغیر استاتیک در سرویس استفاده می‌کنیم
                    V2RayVpnService.eventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    V2RayVpnService.eventSink = null
                }
            })
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == VPN_PERMISSION_CODE && resultCode == RESULT_OK) {
            pendingConfig?.let { startV2RayService(it) }
        }
        pendingConfig = null
    }

    private fun startV2RayService(uri: String) {
        val i = Intent(this, V2RayVpnService::class.java)
        i.action = V2RayVpnService.ACTION_START
        i.putExtra("config", uri)
        startService(i)
    }
}
