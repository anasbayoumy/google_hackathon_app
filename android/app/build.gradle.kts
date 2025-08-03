plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val core_version = "1.13.1"
val kotlin_version = "1.9.23"
// Define a common MediaPipe Tasks version for consistency
val mediapipe_tasks_version = "0.10.21"
val mediapipe_tasks_version_genai = "0.10.25"


android {
    namespace = "com.example.myapp"
    compileSdk = 35
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.myapp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

dependencies {
    implementation("androidx.core:core:$core_version")
    // Updated MediaPipe dependencies to a consistent and available version (0.10.21)
    implementation("com.google.mediapipe:tasks-genai:$mediapipe_tasks_version_genai")
    // Removed tasks-vision as it's likely transitively included by tasks-vision-image-generator
    implementation("com.google.mediapipe:tasks-vision-image-generator:$mediapipe_tasks_version")
    implementation("com.google.mediapipe:tasks-text:$mediapipe_tasks_version")
    implementation("com.google.mediapipe:tasks-audio:$mediapipe_tasks_version")

    implementation("org.tensorflow:tensorflow-lite-select-tf-ops:2.15.0")
    implementation("androidx.exifinterface:exifinterface:1.3.6")
    implementation("androidx.multidex:multidex:2.0.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    // Vosk for offline speech-to-text (using correct group ID and latest version)
    implementation("com.alphacephei:vosk-android:0.3.47")
    // Wear OS Data Layer for watch communication
    implementation("com.google.android.gms:play-services-wearable:18.0.0")
    // Add coroutines for tasks.await support
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.7.3")
}

flutter {
    source = "../.."
}