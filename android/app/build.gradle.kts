import java.io.FileInputStream
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "kr.donminzzi.bubble_shooter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "kr.donminzzi.pebbix"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (System.getenv("ANDROID_KEYSTORE_PATH") != null) {
                storeFile = file(System.getenv("ANDROID_KEYSTORE_PATH"))
                keyAlias = System.getenv("ANDROID_KEYSTORE_ALIAS")
                keyPassword = System.getenv("ANDROID_KEYSTORE_PRIVATE_KEY_PASSWORD")
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            } else {
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String?
            }
        }
    }

    flavorDimensions += "default"
    productFlavors {
        create("production") {
            dimension = "default"
            applicationIdSuffix = ""
        }
        create("staging") {
            dimension = "default"
            applicationIdSuffix = ".stg"
        }
        create("development") {
            dimension = "default"
            applicationIdSuffix = ".dev"
        }
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android.txt"),
                "proguard-rules.pro",
            )
        }
        getByName("debug") {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// The Mobile Ads SDK reads the AdMob application ID from the manifest at startup, and ad units only
// serve under the app that owns them. Only a production release may carry the real ID, and only
// together with the two unit-ID --dart-define flags, so the app and its units come from one account.
// ios/scripts/admob_app_id.sh applies the same rule to the iOS build; keep the two in step.
val googleSampleAdMobAppId = "ca-app-pub-3940256099942544~3347511713"

// flutter_tools passes every --dart-define to Gradle as one comma-separated list of base64 entries.
val dartDefines: Map<String, String> =
    (findProperty("dart-defines") as String?)
        .orEmpty()
        .split(",")
        .filter { it.isNotEmpty() }
        .map { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }
        .associate { it.substringBefore("=") to it.substringAfter("=", "") }

fun productionAdMobAppId(): String {
    val appId = dartDefines["ADMOB_APP_ID"].orEmpty()
    val unitIds =
        listOf("ADMOB_REWARDED_AD_UNIT_ID", "ADMOB_INTERSTITIAL_AD_UNIT_ID")
            .associateWith { dartDefines[it].orEmpty() }
    // No AdMob defines at all keeps the sample ID, which is what the release builds before
    // the account existed shipped. Anything in between is a half-configured release.
    if (appId.isEmpty() && unitIds.values.all { it.isEmpty() }) return googleSampleAdMobAppId

    val missing = (mapOf("ADMOB_APP_ID" to appId) + unitIds).filterValues { it.isEmpty() }.keys
    if (missing.isNotEmpty()) {
        throw GradleException("A production release needs all AdMob dart-defines; missing: ${missing.joinToString()}.")
    }
    val publisher =
        Regex("""(ca-app-pub-\d{16})~\d{10}""").matchEntire(appId)?.groupValues?.get(1)
            ?: throw GradleException("ADMOB_APP_ID is not an AdMob application ID: $appId")
    unitIds.entries.firstOrNull { !Regex("""ca-app-pub-\d{16}/\d{10}""").matches(it.value) }?.let {
        throw GradleException("${it.key} is not an AdMob ad unit ID: ${it.value}")
    }
    if (publisher == googleSampleAdMobAppId.substringBefore("~")) {
        throw GradleException("ADMOB_APP_ID is Google's sample publisher, not this app's AdMob account.")
    }
    val foreign = unitIds.filterValues { !it.startsWith("$publisher/") }.keys
    if (foreign.isNotEmpty()) {
        throw GradleException("${foreign.joinToString()} must belong to the ADMOB_APP_ID publisher $publisher.")
    }
    return appId
}

androidComponents {
    onVariants { variant ->
        // Resolved lazily, so only building the production release can fail on a bad configuration.
        val appId =
            if (variant.flavorName == "production" && variant.buildType == "release") {
                providers.provider { productionAdMobAppId() }
            } else {
                providers.provider { googleSampleAdMobAppId }
            }
        variant.manifestPlaceholders.put("admobApplicationId", appId)
    }
}

flutter {
    source = "../.."
}
