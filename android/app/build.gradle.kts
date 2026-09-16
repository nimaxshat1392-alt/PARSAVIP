plugins {
    id "com.android.application"
    id "kotlin-android"
    id "dev.flutter.flutter-gradle-plugin"
}

android {
    namespace "com.parsavip.parsavip"
    compileSdk 35 // طبق نیازمندی پلاگین جدید
    ndkVersion flutter.ndkVersion

    compileOptions {
        sourceCompatibility JavaVersion.VERSION_17
        targetCompatibility JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = '17'
    }

    defaultConfig {
        applicationId "com.parsavip.parsavip"
        minSdkVersion 23 // حداقل نسخه مورد نیاز پلاگین
        targetSdkVersion 34
        versionCode 1
        versionName "1.0.0"
    }

    buildTypes {
        release {
            signingConfig signingConfigs.debug
            minifyEnabled false
            shrinkResources false
        }
    }

    packagingOptions {
        jniLibs {
            useLegacyPackaging = true // طبق مستندات پلاگین برای لود صحیح کتابخانه‌های بومی
        }
    }
}

flutter {
    source '../..'
}
