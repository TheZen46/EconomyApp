import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Opt-in for local test builds of the release variant without the release key.
val allowDebugSigning = project.findProperty("allowDebugSigning")?.toString()?.toBoolean() == true

android {
    namespace = "com.taidy.finance"
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
        applicationId = "com.taidy.finance"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters.addAll(listOf("arm64-v8a", "armeabi-v7a", "x86_64"))
        }

        externalNativeBuild {
            cmake {
                cppFlags("-std=c++17", "-frtti", "-fexceptions", "-fopenmp")
                arguments(
                    "-DANDROID_STL=c++_shared",
                    "-DGGML_USE_OPENMP=ON",
                    "-DGGML_USE_VULKAN=ON"
                )
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDirs("src/main/jniLibs")
        }
    }

    signingConfigs {
        create("release") {
            val keyAliasVal = keystoreProperties.getProperty("keyAlias") ?: System.getenv("KEY_ALIAS")
            val keyPasswordVal = keystoreProperties.getProperty("keyPassword") ?: System.getenv("KEY_PASSWORD")
            val storePasswordVal = keystoreProperties.getProperty("storePassword") ?: System.getenv("STORE_PASSWORD")
            val storeFileVal = keystoreProperties.getProperty("storeFile") ?: System.getenv("STORE_FILE")

            if (storeFileVal != null && keyAliasVal != null && keyPasswordVal != null && storePasswordVal != null) {
                keyAlias = keyAliasVal
                keyPassword = keyPasswordVal
                storePassword = storePasswordVal
                val f = file(storeFileVal)
                storeFile = if (f.isAbsolute) {
                    f
                } else {
                    val inRoot = rootProject.file(storeFileVal)
                    if (inRoot.exists()) inRoot else rootProject.file("app/$storeFileVal")
                }
            }
        }
    }

    buildTypes {
        release {
            // Signed with the release key only. Falling back to the debug key
            // produced APKs that a correctly signed build cannot update; without
            // the release key the build fails (see the check at the end of this
            // file) unless -PallowDebugSigning=true is passed.
            val releaseSigning = signingConfigs.getByName("release")
            signingConfig = when {
                releaseSigning.storeFile != null -> releaseSigning
                allowDebugSigning -> signingConfigs.getByName("debug")
                else -> null
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any { task ->
        task.project == project && (task.name == "assembleRelease" || task.name == "bundleRelease")
    }
    val releaseSigningMissing = android.signingConfigs.getByName("release").storeFile == null
    if (buildsRelease && releaseSigningMissing && !allowDebugSigning) {
        throw GradleException(
            "Release signing is not configured. Provide android/key.properties or the STORE_FILE, " +
                "KEY_ALIAS, KEY_PASSWORD and STORE_PASSWORD environment variables, or pass " +
                "-PallowDebugSigning=true for a local test build."
        )
    }
}
