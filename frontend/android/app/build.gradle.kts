plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.sheliming.coco"
    // flutter_secure_storage 要求 compileSdk 37；与 Flutter 默认 36 向后兼容
    compileSdk = 37
    // 本机安装的是 NDK r28b（Pkg.Revision 28.1.13356709），与 Flutter 默认 28.2 目录并存即可编译
    ndkVersion = "28.2.13676358"

    compileOptions {
        // flutter_local_notifications / timezone 需要 JDK 8+ API desugar
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.sheliming.coco"
        // 通知渠道 / 精确闹钟等需 Android 8+；国内老人机主流 10–14
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.core:core-ktx:1.15.0")
}

flutter {
    source = "../.."
}
