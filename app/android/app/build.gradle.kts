import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Spec 15: release signing from app/android/key.properties (storeFile, storePassword, keyAlias, keyPassword), written
// by hand - ops/production_runbook.txt step 8. Never in the repo (.gitignore). It is read ONLY when a release task
// was asked for (plan 15 D229), so debug builds and unit tests never open it. Nothing here prints its values.
// Keep Gradle's configuration cache OFF: it would store values read here (the passwords) under .gradle/.
val keyPropertiesFile = rootProject.file("key.properties")
val wantsRelease = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
val keyProperties = Properties().apply {
    if (wantsRelease && keyPropertiesFile.isFile) keyPropertiesFile.inputStream().use { load(it) }
}
val releaseKeyNames = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val missingReleaseKeys = releaseKeyNames.filter { keyProperties.getProperty(it).isNullOrBlank() }

android {
    namespace = "com.bdpay.verifier"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.bdpay.verifier"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (wantsRelease && missingReleaseKeys.isEmpty()) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // No debug-key fallback: a release APK is signed with the release key or not built (spec 15).
            if (wantsRelease && missingReleaseKeys.isEmpty()) signingConfig = signingConfigs.getByName("release")
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

dependencies {
    // Spec 13a: background upload, status refresh and heartbeat (exact pin, approved 2026-10-30).
    implementation("androidx.work:work-runtime-ktx:2.12.0")
    // Kotlin unit tests for SmsFilter (spec 06) and the pipeline logic (spec 13a).
    testImplementation("junit:junit:4.13.2")
}

// Spec 14: RealSmsTest reads the shared samples in tests/real_sms/ (repo root); declared as an input so a changed
// sample re-runs the unit tests instead of leaving an old result "up to date".
tasks.withType<Test>().configureEach {
    inputs.files(fileTree("../../../tests/real_sms")).withPropertyName("realSmsSamples")
}

// Spec 15: release packaging stops with a clear message when the signing file is missing or incomplete. Messages
// name keys, never values or paths. Debug builds do not run these tasks.
tasks.matching { it.name == "packageRelease" || it.name == "bundleRelease" }.configureEach {
    doFirst {
        if (!keyPropertiesFile.isFile) {
            throw GradleException(
                "Release signing: android/key.properties not found. Create it by hand - see " +
                    "ops/production_runbook.txt step 8. Debug builds do not need it.",
            )
        }
        if (missingReleaseKeys.isNotEmpty()) {
            throw GradleException("Release signing: android/key.properties is missing: ${missingReleaseKeys.joinToString()}.")
        }
        if (!file(keyProperties.getProperty("storeFile")).isFile) {
            throw GradleException("Release signing: the storeFile named in android/key.properties does not exist.")
        }
    }
}
