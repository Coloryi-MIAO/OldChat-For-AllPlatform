plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

android {
    namespace = "com.coloryi.oldchatforallplatform"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.coloryi.oldchatforallplatform"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("oldchatrelease") {
            val signingDir = rootProject.file("../signing")
            storeFile = signingDir.resolve("oldchatrelease.p12")
            storePassword = providers.environmentVariable("OLDCHATANDROIDSTOREPASSWORD").orNull ?: "oldchatlocalbuild"
            keyAlias = providers.environmentVariable("OLDCHATANDROIDKEYALIAS").orNull ?: "oldchatrelease"
            keyPassword = providers.environmentVariable("OLDCHATANDROIDKEYPASSWORD").orNull ?: "oldchatlocalbuild"
            storeType = "PKCS12"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("oldchatrelease")
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
