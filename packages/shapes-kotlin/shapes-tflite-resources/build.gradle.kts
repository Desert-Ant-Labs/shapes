import com.vanniktech.maven.publish.JavaLibrary
import com.vanniktech.maven.publish.JavadocJar

// Bundled model files for Shapes on Android (the Android counterpart of the
// SwiftPM `ShapesTFLiteResources` product). The model files (shapes.tflite,
// shapes_meta.json) are staged into src/main/resources by
// `mise run android-natives`; this module packages them as classpath resources.
// The main `ai.desertant:shapes` artifact depends on this module by default
// because Shapes is small enough to bundle automatically.
plugins {
    `java-library`
    id("com.vanniktech.maven.publish") version "0.34.0"
}

group = "ai.desertant"
version = "0.6.0"

// The model files are staged (gitignored) by the root project's Swift build
// task; depend on it so a fresh checkout cannot produce or publish an empty
// model JAR, and fail fast if staging somehow left files missing.
val stageModel = rootProject.tasks.named("buildSwiftNatives")
tasks.processResources {
    dependsOn(stageModel)
}
tasks.withType<Jar>().matching { it.name == "sourcesJar" }.configureEach {
    dependsOn(stageModel)
    // The model binaries are the main jar's content; keep the sources jar
    // (required by Maven Central) minimal instead of duplicating ~14 MB.
    exclude("*.tflite", "*.json")
}
tasks.jar {
    doFirst {
        val resources = file("src/main/resources")
        val required = listOf("shapes.tflite", "shapes_meta.json")
        val missing = required.filterNot { resources.resolve(it).isFile }
        check(missing.isEmpty()) {
            "model files missing from $resources: $missing (run `mise run android-natives`)"
        }
    }
}

mavenPublishing {
    publishToMavenCentral()
    if (providers.gradleProperty("signingInMemoryKey").isPresent) {
        signAllPublications()
    }
    coordinates("ai.desertant", "shapes-tflite-resources", version.toString())
    configure(JavaLibrary(javadocJar = JavadocJar.Empty(), sourcesJar = true))
    pom {
        name.set("Shapes LiteRT resources")
        description.set("Bundled on-device Shapes model files for Android (no network at runtime).")
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
