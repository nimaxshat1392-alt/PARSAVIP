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
import libXray.LibXray
import org.json.JSONObject
import org.json.JSONArray

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

            val datDir = filesDir.absolutePath
            val configJson = LibXray.convertShareLinksToXrayJson(shareLink)
            Log.i(TAG, "Config JSON: $configJson")

            val fullConfig = injectTunInbound(configJson)
            Log.i(TAG, "Full config: $fullConfig")

            LibXray.runXrayFromJSON(datDir, "config.json", fullConfig)

            isConnected = true
            showNotification()
            eventSink?.success(mapOf("event" to "connected"))

        } catch (e: Exception) {
            Log.e(TAG, "startVpn error", e)
            eventSink?.error("START_FAIL", e.message, null)
        }
    }

    private fun injectTunInbound(jsonStr: String): String {
        val root = JSONObject(jsonStr)

        val tunInbound = JSONObject().apply {
            put("tag", "tun-in")
            put("protocol", "tun")
            put("settings", JSONObject().apply {
                put("address", "172.19.0.1/30")
                put("mtu", 1500)
                put("userLevel", 0)
                put("autoSystemRoutingTable", true)
            })
            put("sniffing", JSONObject().apply {
                put("enabled", true)
                put("destOverride", JSONArray(listOf("http", "tls", "quic")))
                put("routeOnly", false)
            })
        }

        val inbounds = JSONArray()
        inbounds.put(tunInbound)
        root.put("inbounds", inbounds)

        val routing = JSONObject().apply {
            put("domainStrategy", "IPIfNonMatch")
            put("rules", JSONArray())
        }
        root.put("routing", routing)

        val dns = JSONObject().apply {
            put("servers", JSONArray(listOf("1.1.1.1", "8.8.8.8")))
        }
        root.put("dns", dns)

        return root.toString()
    }

    private fun stopVpn() {
        isConnected = false
        try {
            LibXray.stopXray()
        } catch (e: Exception) {
            Log.e(TAG, "stopXray error: ${e.message}")
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
                CHANNEL_ID, "VPN Status", NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(ch)
        }
    }

    private fun showNotification() {
        val pi = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE
        )
        val stopIntent = Intent(this, ParsaVpnService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPi = PendingIntent.getService(
            this, 1, stopIntent, PendingIntent.FLAG_IMMUTABLE
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
