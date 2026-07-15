package ai.desertant.shapes

import ai.desertant.core.HostBridge

/**
 * JNI surface over `libShapesAndroid.so`, built by `mise run android-natives`.
 * Android only: `libShapesAndroid.so` statically links its runtime.
 * Instance-based: each `Shapes` is an opaque native handle (a `Long`). Points
 * cross as a little-endian f64 byte array; the recognized shape comes back as an
 * FFIBuffer typed binary buffer.
 *
 * `jsonParseTree` / `httpTree` / `httpDownload` are the host callbacks the
 * native runtime looks up on this class. They forward to
 * `ai.desertant.core.HostBridge`.
 */
internal object ShapesNative {
    @Volatile private var loaded = false

    fun ensureLoaded() {
        if (loaded) return
        synchronized(this) {
            if (loaded) return
            System.loadLibrary("ShapesAndroid")
            loaded = true
        }
    }

    @JvmStatic external fun create(cacheRoot: ByteArray?, directory: ByteArray?): Long
    @JvmStatic external fun createBundled(metaJson: ByteArray, model: ByteArray): Long
    @JvmStatic external fun destroy(handle: Long)
    @JvmStatic external fun isDownloaded(handle: Long): Int
    @JvmStatic external fun download(handle: Long): Int
    @JvmStatic external fun run(handle: Long, pointBytes: ByteArray, minimumConfidence: Double): ByteArray?

    @JvmStatic
    fun jsonParseTree(jsonUtf8: ByteArray): ByteArray = HostBridge.jsonParseTree(jsonUtf8)

    // HTTP host callbacks the Swift ModelStore uses to download on demand.
    @JvmStatic
    fun httpTree(urlUtf8: ByteArray): ByteArray = HostBridge.httpTree(urlUtf8)

    @JvmStatic
    fun httpDownload(urlUtf8: ByteArray, destUtf8: ByteArray): Int = HostBridge.httpDownload(urlUtf8, destUtf8)
}
