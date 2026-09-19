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
import libv2ray.Libv2ray
import libv2ray.V2rayCallback
import libv2ray.V2rayPoint
import java.io.File

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
    private var v2rayPoint: V2rayPoint? = null
    private var runningThread: Thread? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val config = intent.getStringExtra("config") ?: ""
                startVpn(config)
            }
            ACTION_STOP -> {
                stopVpn()
                stopSelf()
            }
        }
        return START_STICKY
    }

    private fun startVpn(shareLink: String) {
        try {
            // ۱. تبدیل share link به config JSON
            val datDir = filesDir.absolutePath
            val configJson = Libv2ray.convertShareLinksToXrayJson(shareLink)
            Log.i(TAG, "Config: $configJson")

            // ۲. ساخت TUN
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
                eventSink?.error("TUN_FAIL", "Cannot establish TUN", null)
                return
            }

            // ۳. callback: مهم‌ترین بخش — protect socket از VPN
            val callback = object : V2rayCallback {
                override fun OnEmitStatus(status: Long, msg: String?) {
                    Log.i(TAG, "V2Ray status=$status msg=$msg")
                }

                override fun ProtectFd(fd: Long): Boolean {
                    val ok = protect(fd.toInt())
                    Log.i(TAG, "protect fd=$fd ok=$ok")
                    return ok
                }
            }

            // ۴. ساخت V2rayPoint
            v2rayPoint = Libv2ray.newV2rayPoint(callback, configJson)
            if (v2rayPoint == null) {
                eventSink?.error("POINT_FAIL", "Cannot create V2rayPoint", null)
                return
            }

            // ۵. تنظیم VpnService
            v2rayPoint!!.setDomain("")
            v2rayPoint!!.setIsVpnMode(true)
            v2rayPoint!!.setVpnService(this)
            v2rayPoint!!.setTunFd(tun!!.fd)

            // ۶. اجرای Xray در thread جدا
            runningThread = Thread {
                try {
                    v2rayPoint!!.runLoop(true)
                    Log.i(TAG, "Xray runLoop started")
                } catch (e: Exception) {
                    Log.e(TAG, "runLoop error", e)
                }
            }.also { it.start() }

            // ۷. صبر کن تا Xray راه بیاد
            Thread.sleep(1500)

            isConnected = true
            showNotification()
            eventSink?.success(mapOf("event" to "connected"))
            Log.i(TAG, "✅ VPN started")

        } catch (e: Exception) {
            Log.e(TAG, "startVpn error", e)
            eventSink?.error("START_FAIL", e.message ?: "Unknown", null)
        }
    }

    private fun stopVpn() {
        isConnected = false
        try {
            v2rayPoint?.stopLoop()
            Log.i(TAG, "stopLoop OK")
        } catch (e: Exception) {
            Log.e(TAG, "stopLoop error: ${e.message}")
        }
        try {
            runningThread?.interrupt()
            runningThread = null
        } catch (_: Exception) {}
        try {
            tun?.close()
            tun = null
        } catch (_: Exception) {}
        v2rayPoint = null
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
            .setContentText("متصل")
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
