package ai.desertant.shapes.example

import ai.desertant.shapes.Point
import ai.desertant.shapes.Shape
import ai.desertant.shapes.Shapes
import android.app.Activity
import android.os.Bundle
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Draw one stroke on the canvas; the app recognizes it and shows the clean
 * shape. The first recognition downloads and caches the model.
 */
class MainActivity : Activity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private lateinit var shapes: Shapes
    private lateinit var canvas: StrokeView
    private lateinit var output: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        shapes = Shapes(this)
        setContentView(buildView())
    }

    override fun onDestroy() {
        scope.cancel()
        shapes.close()
        super.onDestroy()
    }

    private fun buildView(): View {
        val density = resources.displayMetrics.density
        fun dp(value: Int) = (value * density).toInt()

        canvas = StrokeView(this)
        output = TextView(this).apply {
            textSize = 16f
            text = "Draw a shape above, then tap Recognize."
        }
        val button = Button(this).apply {
            text = "Recognize"
            setOnClickListener { recognize() }
        }
        val clear = Button(this).apply {
            text = "Clear"
            setOnClickListener { canvas.clear(); output.text = "" }
        }

        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(20), dp(20), dp(20), dp(20))
            addView(TextView(context).apply { text = "Shapes Android Example"; textSize = 24f })
            addView(canvas, ViewGroup.LayoutParams.MATCH_PARENT, dp(320))
            addView(button, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            addView(clear, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
            addView(output, ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT)
        }
    }

    private fun recognize() {
        val points = canvas.points.map { Point(it.first.toDouble(), it.second.toDouble()) }
        if (points.size < 8) { output.text = "Draw a longer stroke."; return }
        output.text = "Recognizing..."
        scope.launch {
            output.text = try {
                describe(shapes.recognize(points))
            } catch (error: Throwable) {
                error.stackTraceToString()
            }
        }
    }

    private fun describe(shape: Shape?): String = when (shape) {
        null -> "Not recognized (try again)."
        is Shape.Line -> "Line"
        is Shape.Rectangle -> "Rectangle (${shape.corners.size} corners)"
        is Shape.Triangle -> "Triangle"
        is Shape.Ellipse -> "Ellipse (r ${"%.0f".format(shape.semiMajor)} x ${"%.0f".format(shape.semiMinor)})"
        is Shape.Star -> "Star (${shape.pointCount} points)"
    }
}

/** A minimal single-stroke drawing view that records the raw points. */
class StrokeView(context: android.content.Context) : View(context) {
    val points = ArrayList<Pair<Float, Float>>()
    private val paint = android.graphics.Paint().apply {
        color = android.graphics.Color.BLACK
        strokeWidth = 6f
        style = android.graphics.Paint.Style.STROKE
        isAntiAlias = true
    }
    private val path = android.graphics.Path()

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.action) {
            MotionEvent.ACTION_DOWN -> { clear(); path.moveTo(event.x, event.y); record(event) }
            MotionEvent.ACTION_MOVE -> { path.lineTo(event.x, event.y); record(event) }
        }
        invalidate()
        return true
    }

    private fun record(event: MotionEvent) { points.add(event.x to event.y) }

    fun clear() { points.clear(); path.reset(); invalidate() }

    override fun onDraw(canvas: android.graphics.Canvas) {
        canvas.drawColor(android.graphics.Color.parseColor("#F0F0F0"))
        canvas.drawPath(path, paint)
    }
}
