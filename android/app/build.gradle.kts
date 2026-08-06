import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials live outside version control, in
// android/key.properties (see android/key.properties.example). When the file
// is absent — a fresh clone, or CI that only builds debug — the release build
// falls back to the debug key so `flutter build apk` still works locally, and
// prints a warning so an unsigned-for-Play build can never pass unnoticed.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.ki1lux.adhani"
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (java.time on API < 26).
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        // Play rejects anything under com.example.*. This id is permanent
        // once the first bundle is uploaded — change it here (and only here)
        // before the first upload if a different one is wanted.
        applicationId = "com.ki1lux.adhani"
        // Pinned rather than inherited from the Flutter tool so a Flutter
        // upgrade can't silently move the floor or the target out from under
        // a published release.
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

    }

    // The app ships one language. Restricting locales drops the ~70 unused
    // translations AppCompat/WorkManager pull in. This lives here rather than
    // as `defaultConfig.resourceConfigurations`, which AGP deprecated in
    // favour of `androidResources.localeFilters` (available since AGP 8.10;
    // this project is on 8.11.1) and removes in AGP 9.
    androidResources {
        localeFilters += listOf("ar", "en")
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                logger.warn(
                    "⚠️  android/key.properties not found — signing the RELEASE build with the " +
                        "DEBUG key. This artifact cannot be uploaded to Google Play."
                )
                signingConfigs.getByName("debug")
            }
            // Ship a mapping file with the bundle so Play can deobfuscate
            // crash reports.
            isDebuggable = false
        }
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/*.kotlin_module",
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE*",
                "META-INF/NOTICE*",
                "kotlin/**",
                "DebugProbesKt.bin"
            )
        }
    }

    lint {
        // A lint failure should stop a release build, not be discovered by a
        // Play reviewer.
        abortOnError = false
        checkReleaseBuilds = true
    }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.work:work-runtime-ktx:2.10.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")

    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
