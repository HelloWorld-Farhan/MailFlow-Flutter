import java.io.File
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.helloworld.mailflow"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.helloworld.mailflow"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val keyPropsFile = rootProject.file("key.properties")
    val keyProps = Properties()
    if (keyPropsFile.exists()) {
        FileInputStream(keyPropsFile).use { keyProps.load(it) }
    }

    val ksPath = System.getenv("MAILFLOW_KEYSTORE_PATH") ?: keyProps.getProperty("storeFile")
    val ksFile = if (!ksPath.isNullOrBlank()) {
        val f = File(ksPath)
        if (f.isAbsolute) f else file(ksPath)
    } else null
    val ksPass = System.getenv("MAILFLOW_KEYSTORE_PASSWORD") ?: keyProps.getProperty("storePassword")
    val ksAlias = System.getenv("MAILFLOW_KEY_ALIAS") ?: keyProps.getProperty("keyAlias")
    val ksKeyPass = System.getenv("MAILFLOW_KEY_PASSWORD") ?: keyProps.getProperty("keyPassword")

    val hasReleaseSigning = ksFile != null && ksFile.exists() &&
        !ksPass.isNullOrBlank() &&
        !ksAlias.isNullOrBlank() &&
        !ksKeyPass.isNullOrBlank()

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = ksFile
                storePassword = ksPass
                keyAlias = ksAlias
                keyPassword = ksKeyPass
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
