import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // Flutter Gradle plugin
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase Google Services plugin
    id("com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

val validateReleaseSigning = tasks.register("validateReleaseSigning") {
    doLast {
        val requiredProperties = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
        require(keystorePropertiesFile.isFile) {
            "Release signing is not configured. Add android/key.properties using the instructions in README.md."
        }
        val missingProperties = requiredProperties.filter {
            keystoreProperties.getProperty(it).isNullOrBlank()
        }
        require(missingProperties.isEmpty()) {
            "Missing release signing properties: ${missingProperties.joinToString()}"
        }
        val storeFile = rootProject.file(keystoreProperties.getProperty("storeFile"))
        require(storeFile.isFile) {
            "Release keystore file does not exist: ${storeFile.path}"
        }
    }
}

tasks.configureEach {
    if (name == "preReleaseBuild") {
        dependsOn(validateReleaseSigning)
    }
}

android {
    namespace = "com.example.sales_tracking"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { rootProject.file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.sales_tracking"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Firebase BoM ensures compatible versions of Firebase libraries
    implementation(platform("com.google.firebase:firebase-bom:34.10.0"))

    // Optional Firebase SDKs
    implementation("com.google.firebase:firebase-analytics")   // analytics
    implementation("com.google.firebase:firebase-firestore")  // database
}

// --------------------
// Project-level buildscript
// --------------------
buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.1.1")
        classpath("com.google.gms:google-services:4.4.4")  // Google services plugin
    }
}

repositories {
    google()
    mavenCentral()
}