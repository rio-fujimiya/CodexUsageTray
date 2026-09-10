plugins {
    id("com.android.application")
}

android {
    namespace = "me.i2for.codexusage"
    compileSdk = 37

    defaultConfig {
        applicationId = "me.i2for.codexusage"
        minSdk = 26
        targetSdk = 37
        versionCode = 3
        versionName = "1.3"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    implementation("androidx.work:work-runtime:2.11.2")
}
