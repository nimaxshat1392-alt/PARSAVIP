package com.parsavip.parsavip

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.github.blueboytm.flutter_v2ray.v2ray.V2rayController

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        V2rayController.init(this, applicationInfo.icon, "PARSAVIP")
    }
}
