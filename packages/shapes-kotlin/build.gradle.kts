import com.vanniktech.maven.publish.AndroidSingleVariantLibrary
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// Android library (AAR) with prebuilt native libraries. Gradle drives the
// native build: `apply(from = "swift-android.gradle.kts")` runs `mise run
// android-natives` (static-stdlib Swift JNI + ONNX Runtime) before packaging,
// dropping the per-ABI libShapesAndroid.so into src/main/jniLibs. This AAR
// ships no model: it downloads on demand by default. Bundling is opt-in via
// the `:shapes-onnx-resources` artifact.
//
// Publishing: the AAR contains a prebuilt Swift native, so JitPack (which
// builds from source) cannot produce it. `mise run publish-android` publishes
// ai.desertant:shapes to Maven Central via the Central portal (the vanniktech
// plugin handles upload, validation, and in-memory GPG signing; credentials
// come from the environment, usually via mise.local.toml.
plugins {
    id("com.android.library") version "8.7.3"
    id("org.jetbrains.kotlin.android") version "2.1.21"
    id("org.jetbrains.kotlin.plugin.serialization") version "2.1.21"
    id("com.vanniktech.maven.publish") version "0.34.0"
}

apply(from = "swift-android.gradle.kts")

group = "ai.desertant"
version = "0.1.0"

android {
    namespace = "ai.desertant.shapes"
    compileSdk = 35

    defaultConfig {
        minSdk = 31 // platform libicu (NFKC) is available from API 31
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
    }

    buildTypes {
        release { isMinifyEnabled = false }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    compilerOptions { jvmTarget.set(JvmTarget.JVM_17) }
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
    // Bundle the model for the instrumented bundled-model tests.
    androidTestImplementation(project(":shapes-onnx-resources"))
}

mavenPublishing {
    publishToMavenCentral()
    // Sign only when a key is provided (CI/release); local publishToMavenLocal
    // stays keyless. ORG_GRADLE_PROJECT_signingInMemoryKey maps to this property.
    if (providers.gradleProperty("signingInMemoryKey").isPresent) {
        signAllPublications()
    }
    coordinates("ai.desertant", "shapes", version.toString())
    configure(AndroidSingleVariantLibrary(variant = "release", sourcesJar = true, publishJavadocJar = true))
    pom {
        name.set("Shapes")
        description.set(
            "On-device single-stroke shape recognition for Android: turns a hand-drawn stroke into " +
                "a clean line, rectangle, triangle, ellipse, or star.")
        url.set("https://github.com/Desert-Ant-Labs/shapes")
        licenses {
            license {
                name.set("Desert Ant Labs Source-Available License 1.0")
                url.set("https://license.desertant.ai/1.0")
                distribution.set("repo")
            }
        }
        developers {
            developer {
                id.set("desert-ant-labs")
                name.set("Desert Ant Labs")
                email.set("contact@desertant.ai")
                url.set("https://desertant.ai")
            }
        }
        scm {
            url.set("https://github.com/Desert-Ant-Labs/shapes")
            connection.set("scm:git:git://github.com/Desert-Ant-Labs/shapes.git")
            developerConnection.set("scm:git:ssh://git@github.com/Desert-Ant-Labs/shapes.git")
        }
    }
}
