import java.util.Base64

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/// GOOGLE_MAPS_API_KEY from the build's --dart-define values (Flutter passes
/// them base64-encoded in the `dart-defines` property), else from the
/// environment; empty when neither has it.
fun googleMapsApiKey(): String {
    val defines = (project.findProperty("dart-defines") as String?) ?: ""
    for (encoded in defines.split(",")) {
        if (encoded.isBlank()) continue
        val define = String(Base64.getDecoder().decode(encoded))
        if (define.startsWith("GOOGLE_MAPS_API_KEY=")) {
            return define.substringAfter("=")
        }
    }
    return System.getenv("GOOGLE_MAPS_API_KEY") ?: ""
}

android {
    namespace = "com.dineqr.admin"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.dineqr.admin"
        // Separate from the customer app (com.dineqr.customer): both can be
        // installed side by side.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Android 9+ blocks plain http://. Shipped builds must use https://,
        // so this stays off unless a build explicitly asks for it — which is
        // only needed to test a release build against the development API
        // over the local network:
        //
        //     flutter build apk -PdineqrCleartext=true \
        //       --dart-define=DINEQR_API_URL=http://<LAN IP>:5264
        //
        // (or set the DINEQR_CLEARTEXT environment variable). Debug builds
        // below turn it on anyway, since they always talk to a local API.
        manifestPlaceholders["dineqrCleartext"] =
            (project.findProperty("dineqrCleartext") as String?)
                ?: System.getenv("DINEQR_CLEARTEXT")
                ?: "false"

        // Google Maps for the GPS ordering area. One key for every platform:
        // `flutter build apk --dart-define=GOOGLE_MAPS_API_KEY=...` (the app
        // reads the same define to know a map can be shown), or the
        // GOOGLE_MAPS_API_KEY environment variable. Without it the location
        // is entered as coordinates instead.
        manifestPlaceholders["googleMapsApiKey"] = googleMapsApiKey()
    }

    buildTypes {
        debug {
            manifestPlaceholders["dineqrCleartext"] = "true"
        }
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

flutter {
    source = "../.."
}
