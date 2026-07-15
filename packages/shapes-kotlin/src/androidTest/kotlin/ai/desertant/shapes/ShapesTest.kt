package ai.desertant.shapes

import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.cos
import kotlin.math.sin

/**
 * Instrumented tests for the Android binding, exercising the real on-device path
 * via JNI: platform JSON via CHostBridge, ONNX Runtime inference, and the
 * static-stdlib runtime. The bundled model comes from the
 * `shapes-onnx-resources` androidTest dependency.
 */
@RunWith(AndroidJUnit4::class)
class ShapesTest {
    private lateinit var shapes: Shapes

    @Before fun setUp() { shapes = Shapes.bundled() }
    @After fun tearDown() { shapes.close() }

    @Test fun recognizesCircleAsEllipse() = runTest {
        val pts = (0..64).map {
            val t = 2.0 * Math.PI * it / 64.0
            Point(100 + 80 * cos(t), 100 + 80 * sin(t))
        }
        val shape = shapes.recognize(pts)
        assertNotNull(shape)
        assertTrue("expected ellipse, got $shape", shape is Shape.Ellipse)
    }

    @Test fun recognizesLine() = runTest {
        val pts = (0..40).map { Point(it * 5.0, it * 2.0) }
        val shape = shapes.recognize(pts)
        assertTrue("expected line, got $shape", shape is Shape.Line)
    }

    @Test fun degenerateReturnsNull() = runTest {
        assertNull(shapes.recognize(listOf(Point(1.0, 1.0))))
    }
}
