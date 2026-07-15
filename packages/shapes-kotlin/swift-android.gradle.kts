// Gradle drives the native build through mise. `mise run android-natives` (defined
// in the repo-root mise.toml) builds libShapesAndroid.so per ABI, copies it +
// libc++_shared.so + libonnxruntime.so into src/main/jniLibs, and stages the
// model into the optional :shapes-onnx-resources module's resources. This task
// runs before the Android merge/package steps.
//
// Requires `mise` on PATH and the config trusted; MISE_TRUSTED_CONFIG_PATHS makes
// the run non-interactive on CI/fresh checkouts.
import org.gradle.api.tasks.Exec

val repoRoot = file("$rootDir/../..")

val buildSwiftNatives by tasks.registering(Exec::class) {
    group = "build"
    description = "Builds the Android native libraries into jniLibs (mise run android-natives)."
    workingDir = repoRoot
    commandLine("mise", "run", "android-natives")
    environment("MISE_TRUSTED_CONFIG_PATHS", repoRoot.absolutePath)
    System.getenv("ANDROID_NDK_HOME")?.let { environment("ANDROID_NDK_HOME", it) }

    inputs.dir("$rootDir/../../Sources")
    inputs.file("$rootDir/../../mise.toml")
    outputs.dir("$rootDir/src/main/jniLibs")
    outputs.dir("$rootDir/shapes-onnx-resources/src/main/resources")
}

tasks.named("preBuild").configure { dependsOn(buildSwiftNatives) }
