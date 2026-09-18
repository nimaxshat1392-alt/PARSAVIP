package com.parsavip.parsavip

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import io.flutter.plugin.common.EventChannel
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController
import libv2ray.Libv2ray
import java.io.File
import java.io.FileOutputStream

class ParsaVpnService : VpnService() {

    companion object {
        const val TAG = "ParsaVpnService"
        const val ACTION_START = "com.parsavip.parsavip.START"
        const val ACTION_STOP = "com.parsavip.parsavip.STOP"
        const val CHANNEL_ID = "parsavip_vpn"
        const val NOTIF_ID = 1001

        @Volatile var isConnected = false
        var eventSink: EventChannel.EventSink? = null
    }

    private var tun: ParcelFileDescriptor? = null
    private var controller: CoreController? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val jsonConfig = intent.getStringExtra("config") ?: ""
                startVpn(jsonConfig)
            }
            ACTION_STOP -> {
                stopVpn()
                stopSelf()
            }
        }
        return START_STICKY
    }

    private fun startVpn(jsonConfig: String) {
        try {
            // ۱. ساخت TUN interface
            val builder = Builder()
            builder.setSession("PARSAVIP")
            builder.setMtu(1500)
            builder.addAddress("172.19.0.1", 30)
            builder.addRoute("0.0.0.0", 0)
            builder.addDnsServer("1.1.1.1")
            builder.addDnsServer("8.8.8.8")

            try {
                builder.addDisallowedApplication(packageName)
            } catch (e: Exception) {
                Log.w(TAG, "Cannot exclude self: ${e.message}")
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setMetered(false)
            }

            tun = builder.establish()
            if (tun == null) {
                Log.e(TAG, "TUN is null")
                eventSink?.error("TUN_FAIL", "Cannot establish TUN", null)
                return
            }

            // ۲. ذخیره config در فایل
            val datDir = filesDir.absolutePath
            val configFile = File(filesDir, "config.json")
            FileOutputStream(configFile).use { it.write(jsonConfig.toByteArray()) }
            Log.i(TAG, "Config saved to ${configFile.absolutePath}")

            // ۳. init env
            try {
                Libv2ray.initCoreEnv(datDir, configFile.absolutePath)
                Log.i(TAG, "initCoreEnv OK")
            } catch (e: Exception) {
                Log.e(TAG, "initCoreEnv error", e)
            }

            // ۴. callback handler — interface, بدون پرانتز
            val handler = object : CoreCallbackHandler {
                override fun onEmitStatus(code: Long, message: String?): Long {
                    Log.i(TAG, "onEmitStatus: $code - $message")
                    return 0L
                }

                override fun startup(): Long {
                    Log.i(TAG, "callback startup")
                    return 0L
                }

                override fun shutdown(): Long {
                    Log.i(TAG, "callback shutdown")
                    return 0L
                }
            }

            // ۵. ساخت controller
            controller = Libv2ray.newCoreController(handler)
            if (controller == null) {
                eventSink?.error("CTRL_FAIL", "Cannot create CoreController", null)
                return
            }

            // ۶. اجرای Xray — ⭐ امضا: startLoop(String configPath, Int tunFd)
            val code = controller?.startLoop(configFile.absolutePath, tun!!.fd)
            Log.i(TAG, "startLoop code=$code")

            // ۷. تنظیم وضعیت
            isConnected = true
            showNotification()
            eventSink?.success(mapOf("event" to "connected"))
            Log.i(TAG, "VPN started successfully")

        } catch (e: Exception) {
            Log.e(TAG, "startVpn error", e)
            eventSink?.error("START_FAIL", e.message ?: "Unknown error", null)
        }
    }

    private fun stopVpn() {
        isConnected = false
        try {
            controller?.stopLoop()
            controller = null
            Log.i(TAG, "stopLoop OK")
        } catch (e: Exception) {
            Log.e(TAG, "stopLoop error: ${e.message}")
        }
        try {
            tun?.close()
            tun = null
        } catch (_: Exception) {}
        cancelNotification()
        eventSink?.success(mapOf("event" to "disconnected"))
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                CHANNEL_ID,
                "VPN Status",
                NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }

    private fun showNotification() {
        val pi = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        val stopIntent = Intent(this, ParsaVpnService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPi = PendingIntent.getService(
            this, 1, stopIntent,
            PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL_ID)
        else
            @Suppress("DEPRECATION") Notification.Builder(this)

        val notif = builder
            .setContentTitle("PARSAVIP")
            .setContentText("متصل به VPN")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(pi)
            .addAction(0, "قطع", stopPi)
            .setOngoing(true)
            .build()

        startForeground(NOTIF_ID, notif)
    }

    private fun cancelNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION") stopForeground(true)
        }
    }

    override fun onRevoke() {
        stopVpn()
        stopSelf()
        super.onRevoke()
    }

    override fun onDestroy() {
        stopVpn()
        super.onDestroy()
    }
}
