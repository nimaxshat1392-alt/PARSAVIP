package com.parsavip.parsavip

import com.github.blueboytm.flutter_vless.FlutterVlessPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FlutterVlessPlugin.setInstance(this)
    }
}
