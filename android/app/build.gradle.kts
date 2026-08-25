import java.util.Properties
import java.util.Base64
import java.nio.charset.StandardCharsets

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val productionBuildRequested = gradle.startParameter.taskNames.any { taskName ->
    taskName.contains("Prod", ignoreCase = true)
}
val releaseSigningRequested = gradle.startParameter.taskNames.any { taskName ->
    taskName.contains("Release", ignoreCase = true) ||
        taskName.contains("Prod", ignoreCase = true)
}
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

val releaseSigningPropertyNames =
    listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
val releaseSigningConfigured = releaseSigningPropertyNames.all { name ->
    !keystoreProperties.getProperty(name).isNullOrBlank()
}

if (releaseSigningRequested && !releaseSigningConfigured) {
    val missing = releaseSigningPropertyNames
        .filter { name -> keystoreProperties.getProperty(name).isNullOrBlank() }
        .joinToString()
    error("Missing Android release signing properties in android/key.properties: $missing")
}

fun keystoreProperty(name: String): String = keystoreProperties.getProperty(name)

fun productionDartDefines(): Map<String, String> {
    val encodedDefines = providers.gradleProperty("dart-defines").orNull
        ?: return emptyMap()
    return encodedDefines
        .split(",")
        .mapNotNull { encoded ->
            runCatching {
                String(
                    Base64.getDecoder().decode(encoded),
                    StandardCharsets.UTF_8,
                )
            }.getOrNull()
        }
        .mapNotNull { definition ->
            val separator = definition.indexOf('=')
            if (separator <= 0) {
                null
            } else {
                definition.substring(0, separator) to definition.substring(separator + 1)
            }
        }
        .toMap()
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.owntend.mobile"
    compileSdk = 37
    buildToolsVersion = "36.0.0"
    ndkVersion = flutter.ndkVersion

    sourceSets {
        getByName("main") {
            java.srcDir("src/main/kotlin")
        }
    }

    buildFeatures {
        resValues = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "app.owntend.mobile"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["admobAppId"] = "ca-app-pub-3940256099942544~3347511713"
    }

    flavorDimensions += "environment"
    productFlavors {
        create("dev") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "Owntend Dev")
            manifestPlaceholders["admobAppId"] = "ca-app-pub-3940256099942544~3347511713"
        }
        create("staging") {
            dimension = "environment"
            applicationIdSuffix = ".staging"
            versionNameSuffix = "-staging"
            resValue("string", "app_name", "Owntend Staging")
            manifestPlaceholders["admobAppId"] = "ca-app-pub-3940256099942544~3347511713"
        }
        create("prod") {
            dimension = "environment"
            resValue("string", "app_name", "Owntend")
            manifestPlaceholders["admobAppId"] = "ca-app-pub-5274007212820203~7167645746"
        }
    }

    signingConfigs {
        if (releaseSigningConfigured) {
            create("release") {
                keyAlias = keystoreProperty("keyAlias")
                keyPassword = keystoreProperty("keyPassword")
                storeFile = file(keystoreProperty("storeFile"))
                storePassword = keystoreProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    lint {
        checkReleaseBuilds = true
        abortOnError = true
        checkAllWarnings = true
        warningsAsErrors = false
        ignoreTestSources = true
        htmlReport = true
        xmlReport = true
        sarifReport = true
        textReport = true
        htmlOutput = file("build/reports/lint-results-prodRelease.html")
        xmlOutput = file("build/reports/lint-results-prodRelease.xml")
        sarifOutput = file("build/reports/lint-results-prodRelease.sarif")
        textOutput = file("build/reports/lint-results-prodRelease.txt")
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
    implementation("androidx.core:core:1.19.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

tasks.configureEach {
    if (name.startsWith("preProd") && name.endsWith("Build")) {
        doFirst {
            if (!productionBuildRequested) {
                return@doFirst
            }
            val defines = productionDartDefines()
            check(defines["APP_ENV"] == "prod") {
                "Production builds require APP_ENV=prod. " +
                    "Use --dart-define-from-file=config/prod.json."
            }
            check(!defines["SUPABASE_URL"].isNullOrBlank()) {
                "Production builds require SUPABASE_URL."
            }
            check(!defines["SUPABASE_PUBLISHABLE_KEY"].isNullOrBlank()) {
                "Production builds require SUPABASE_PUBLISHABLE_KEY."
            }
            check(!defines["GOOGLE_WEB_CLIENT_ID"].isNullOrBlank()) {
                "Production builds require GOOGLE_WEB_CLIENT_ID for native Google sign-in."
            }
        }
    }
}
