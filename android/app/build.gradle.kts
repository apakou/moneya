plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.moneya"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Base applicationId. Per-flavor suffixes below (.dev / .staging /
        // <none for prod>) produce three distinct install IDs so dev,
        // staging and prod builds can coexist on a single device — a
        // hard requirement for fintech QA on real hardware.
        applicationId = "com.moneya.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ---- Flavors (PR3) ----------------------------------------------------
    // Each flavor sets:
    //   • applicationIdSuffix — unique install ID so flavors coexist on
    //     one device.
    //   • resValue "string" "app_name" — overrides the launcher label
    //     wired in AndroidManifest.xml via `@string/app_name`.
    //
    // Drive these via:
    //     flutter run --flavor dev --dart-define=FLAVOR=dev \
    //                 --dart-define=API_BASE_URL=...
    // (or use scripts/run_dev.sh — see scripts/README.md).
    //
    // We deliberately do NOT inject API_BASE_URL via buildConfigField:
    // Dart `--dart-define` is the single source of truth for Dart code
    // and we want flavor wiring to be Dart-discoverable (see
    // `lib/core/config/env.dart`).
    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "MoneyA Dev")
        }
        create("staging") {
            dimension = "env"
            applicationIdSuffix = ".staging"
            resValue("string", "app_name", "MoneyA Staging")
        }
        create("prod") {
            dimension = "env"
            // No suffix — production keeps the canonical applicationId.
            resValue("string", "app_name", "MoneyA")
        }
    }

    buildTypes {
        release {
            // Debug-signed for now so `flutter run --release` works in
            // CI. A real upload-key signing config lands with the first
            // Play Store internal-testing release.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
