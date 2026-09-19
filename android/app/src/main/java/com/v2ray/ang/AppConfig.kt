package com.v2ray.ang

import com.parsavip.parsavip.BuildConfig

object AppConfig {
    const val ANGPACKAGENAME = "com.parsavip.parsavip"
    const val VERSION_NAME = "1.0.0"
    const val VERSION_CODE = 1

    @Volatile
    var isRunning = false

    @Volatile
    var isTestRunning = false

    @Volatile
    var selectedProfile = -1

    const val PREF_INAPP_BUY_IS_PREMIUM = "pref_inapp_buy_is_premium"
    const val PREFERENCE_NAME = "com.parsavip.parsavip_preferences"
}
