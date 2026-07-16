package ai.desertant.shapes

import ai.desertant.core.FfiReader
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** Options controlling recognition. */
data class Options(
    /**
     * Minimum classifier confidence, on top of each class's calibrated gate.
     * `0.0` (the default) applies only the model's own gates.
     */
    val minimumConfidence: Double = 0.0,
)

/** Thrown when the model cannot be created, loaded, or run. */
class ShapesException(message: String) : Exception(message)

/**
 * On-device single-stroke shape recognition. Mirrors the iOS/Swift SDK: create
 * one `Shapes` and reuse it; the model loads lazily on the first [recognize]
 * (or eagerly via [download]).
 *
 * ```kotlin
 * val shapes = Shapes(context)                       // download on demand, cached
 * val shape = shapes.recognize(strokePoints)         // Shape? (null if rejected)
 * shapes.close()
 * ```
 */
class Shapes private constructor(private val handle: Long) : AutoCloseable {
    /**
     * A recognizer that downloads the model on demand (cached under the app's
     * cacheDir), or, when [directory] is given, treats that directory as the
     * model's home (adopt files there, else download into it). Construction is
     * cheap; the model loads on the first [recognize] (or eagerly via [download]).
     */
    constructor(context: android.content.Context, directory: String? = null)
        : this(createHandle(context.cacheDir.absolutePath, directory))

    companion object {
        /**
         * A recognizer using the model bundled in your app via the
         * `ai.desertant:shapes-tflite-resources` dependency (no network).
         */
        fun bundled(): Shapes {
            ShapesNative.ensureLoaded()
            val handle = ShapesNative.createBundled(
                resource("shapes_meta.json"), resource("shapes.tflite"))
            if (handle == 0L) throw ShapesException(
                "bundled model unavailable; add the `ai.desertant:shapes-tflite-resources` dependency")
            return Shapes(handle)
        }

        private fun createHandle(cacheRoot: String, directory: String?): Long {
            ShapesNative.ensureLoaded()
            val handle = ShapesNative.create(
                cacheRoot.toByteArray(Charsets.UTF_8), directory?.toByteArray(Charsets.UTF_8))
            if (handle == 0L) throw ShapesException("failed to create Shapes")
            return handle
        }

        private fun resource(name: String): ByteArray =
            (Shapes::class.java.getResourceAsStream("/$name")
                ?: throw ShapesException(
                    "bundled model resource not found: $name. Add the " +
                        "`ai.desertant:shapes-tflite-resources` dependency, or use Shapes(context)."))
                .use { it.readBytes() }
    }

    /** Whether the model is available for this recognizer with no network. */
    fun isDownloaded(): Boolean = ShapesNative.isDownloaded(handle) != 0

    /**
     * Download the model ahead of time so the first [recognize] is instant. A
     * no-op once available (see [isDownloaded]). Suspends on a background
     * dispatcher.
     */
    suspend fun download(): Unit = withContext(Dispatchers.IO) {
        if (ShapesNative.download(handle) != 0) throw ShapesException("model download failed")
    }

    /**
     * Recognize a stroke given as ordered [points] (canvas coordinates). Returns
     * the snapped [Shape], or `null` when the stroke is rejected or degenerate.
     * Loads the model lazily on first call.
     */
    suspend fun recognize(points: List<Point>, options: Options = Options()): Shape? =
        withContext(Dispatchers.Default) {
            val bytes = ShapesNative.run(handle, encodePoints(points), options.minimumConfidence)
                ?: throw ShapesException("recognition failed")
            decodeShape(FfiReader(bytes))
        }

    /** Release the native model. The recognizer is unusable afterwards. */
    override fun close() = ShapesNative.destroy(handle)

    /** Serialize points as little-endian f64 pairs (x0,y0,x1,y1,...). */
    private fun encodePoints(points: List<Point>): ByteArray {
        val buf = ByteBuffer.allocate(points.size * 16).order(ByteOrder.LITTLE_ENDIAN)
        for (p in points) {
            buf.putDouble(p.x)
            buf.putDouble(p.y)
        }
        return buf.array()
    }

    /** Decode the FFIWriter buffer produced by the native CABI. */
    private fun decodeShape(r: FfiReader): Shape? {
        if (r.int() == 0) return null
        return when (r.int()) {
            1 -> Shape.Line(point(r), point(r))
            2 -> Shape.Rectangle(points(r))
            3 -> Shape.Triangle(points(r))
            4 -> Shape.Ellipse(point(r), r.double(), r.double(), r.double())
            5 -> Shape.Star(point(r), r.double(), r.double(), r.double(), r.int())
            else -> null
        }
    }

    private fun point(r: FfiReader) = Point(r.double(), r.double())

    private fun points(r: FfiReader): List<Point> {
        val n = r.int()
        return List(n) { point(r) }
    }
}
