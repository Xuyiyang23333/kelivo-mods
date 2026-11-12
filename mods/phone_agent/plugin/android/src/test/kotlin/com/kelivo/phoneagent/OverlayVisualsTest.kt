package com.kelivo.phoneagent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class OverlayVisualsTest {
    private var now = 0L

    private class FakeScheduler : OverlayScheduler {
        val frames = ArrayDeque<() -> Unit>()
        val delayed = mutableListOf<Pair<Long, () -> Unit>>()
        var removeCount = 0

        override fun postFrame(callback: () -> Unit) {
            frames.addLast(callback)
        }

        override fun postDelayed(delayMillis: Long, callback: () -> Unit) {
            delayed += delayMillis to callback
        }

        override fun removePending() {
            frames.clear()
            delayed.clear()
            removeCount++
        }

        fun runFrame() {
            frames.removeFirst().invoke()
        }

        fun runTimeout() {
            val (_, callback) = delayed.removeAt(0)
            callback()
        }

        fun runSettle() {
            val (_, callback) = delayed.removeAt(delayed.lastIndex)
            callback()
        }
    }

    @Test
    fun `bounds center uses the middle of even bounds`() {
        assertEquals(50f to 50f, OverlayVisuals.center(Bounds(0, 0, 100, 100)))
    }

    @Test
    fun `bounds center keeps fractional pixels for odd bounds`() {
        assertEquals(5.5f to 5.5f, OverlayVisuals.center(Bounds(1, 1, 10, 10)))
    }

    @Test
    fun `degenerate bounds produce no node plan`() {
        assertNull(OverlayVisuals.center(Bounds(10, 10, 10, 40)))
        assertNull(OverlayVisuals.center(Bounds(10, 10, 40, 10)))
        assertNull(
            OverlayVisuals.plan(
                OverlayEvent.Node(Bounds(10, 10, 10, 40), NodeAction.CLICK),
                100,
                100,
            ),
        )
    }

    @Test
    fun `node center is clamped to the screen`() {
        val plan = OverlayVisuals.plan(
            OverlayEvent.Node(Bounds(-40, -40, 0, 0), NodeAction.CLICK),
            100,
            200,
        )
        assertEquals(0f, plan?.centerX)
        assertEquals(0f, plan?.centerY)
    }

    @Test
    fun `observe plan has a bounded duration`() {
        val plan = OverlayVisuals.plan(OverlayEvent.Observing, 100, 100)
        assertEquals(OverlayKind.OBSERVE, plan?.kind)
        assertEquals(OverlayVisuals.OBSERVE_MILLIS, plan?.durationMillis)
    }

    @Test
    fun `long press node plan lasts longer than a tap`() {
        val bounds = Bounds(0, 0, 100, 100)
        val tap = OverlayVisuals.plan(OverlayEvent.Node(bounds, NodeAction.CLICK), 100, 100)
        val longPress = OverlayVisuals.plan(
            OverlayEvent.Node(bounds, NodeAction.LONG_CLICK),
            100,
            100,
        )
        assertEquals(OverlayVisuals.NODE_MILLIS, tap?.durationMillis)
        assertEquals(OverlayVisuals.NODE_LONG_PRESS_MILLIS, longPress?.durationMillis)
    }

    @Test
    fun `gesture plan reuses the real coordinates and duration`() {
        val plan = OverlayVisuals.plan(
            OverlayEvent.Gesture(
                action = GestureAction.SWIPE,
                startX = 10f,
                startY = 20f,
                endX = 30f,
                endY = 40f,
                durationMillis = 300,
            ),
            100,
            100,
        )
        assertEquals(OverlayKind.GESTURE, plan?.kind)
        assertEquals(10f, plan?.startX)
        assertEquals(20f, plan?.startY)
        assertEquals(30f, plan?.endX)
        assertEquals(40f, plan?.endY)
        assertEquals(300L, plan?.travelMillis)
        assertEquals(300L + OverlayVisuals.GESTURE_TAIL_MILLIS, plan?.durationMillis)
    }

    @Test
    fun `gesture travel keeps short and long durations visible but bounded`() {
        assertEquals(
            OverlayVisuals.MIN_TRAVEL_MILLIS,
            OverlayVisuals.gestureTravelMillis(50),
        )
        assertEquals(
            OverlayVisuals.MAX_TRAVEL_MILLIS,
            OverlayVisuals.gestureTravelMillis(2000),
        )
        val plan = OverlayVisuals.plan(
            OverlayEvent.Gesture(GestureAction.TAP, 1f, 1f, 1f, 1f, 2000),
            100,
            100,
        )
        assertEquals(
            OverlayVisuals.MAX_TRAVEL_MILLIS + OverlayVisuals.GESTURE_TAIL_MILLIS,
            plan?.durationMillis,
        )
    }

    @Test
    fun `state suppresses new plans while capturing`() {
        val state = OverlayState(now = { now })
        val first = OverlayVisuals.plan(OverlayEvent.Observing, 100, 100)!!
        val second = OverlayVisuals.plan(OverlayEvent.Captured, 100, 100)!!

        assertTrue(state.begin(first))
        state.suppress()
        assertFalse(state.begin(second))
        assertNull(state.plan())
        state.resume()
        assertTrue(state.begin(second))
        assertEquals(second, state.plan())
    }

    @Test
    fun `state clear is idempotent and expiry follows the plan duration`() {
        val state = OverlayState(now = { now })
        val plan = OverlayVisuals.plan(OverlayEvent.Observing, 100, 100)!!
        state.begin(plan)
        now = plan.durationMillis - 1
        assertFalse(state.isExpired())
        now = plan.durationMillis
        assertTrue(state.isExpired())
        state.clear()
        state.clear()
        assertNull(state.plan())
        assertTrue(state.isExpired())
    }

    @Test
    fun `gate proceeds immediately when no window is visible`() {
        val scheduler = FakeScheduler()
        val gate = OverlayCaptureGate(scheduler, { OverlayHideResult.NONE })
        var proceeded = 0
        var failed = 0

        gate.hideForCapture({ proceeded++ }, { failed++ })

        assertEquals(1, proceeded)
        assertEquals(0, failed)
        assertTrue(scheduler.frames.isEmpty())
    }

    @Test
    fun `gate waits two frames and a settle delay before proceeding`() {
        val scheduler = FakeScheduler()
        val gate = OverlayCaptureGate(scheduler, { OverlayHideResult.HIDDEN })
        var proceeded = 0

        gate.hideForCapture({ proceeded++ }, {})
        assertEquals(0, proceeded)
        scheduler.runFrame()
        assertEquals(0, proceeded)
        scheduler.runFrame()
        assertEquals(0, proceeded)
        scheduler.runSettle()
        assertEquals(1, proceeded)
        assertTrue(scheduler.delayed.isEmpty())
    }

    @Test
    fun `gate fails without proceeding when the window cannot be hidden`() {
        val scheduler = FakeScheduler()
        val gate = OverlayCaptureGate(scheduler, { OverlayHideResult.FAILED })
        var proceeded = 0
        var failed = 0

        gate.hideForCapture({ proceeded++ }, { failed++ })

        assertEquals(0, proceeded)
        assertEquals(1, failed)
        assertTrue(scheduler.frames.isEmpty())
    }

    @Test
    fun `gate fails when frames do not arrive in time`() {
        val scheduler = FakeScheduler()
        val gate = OverlayCaptureGate(scheduler, { OverlayHideResult.HIDDEN })
        var proceeded = 0
        var failed = 0

        gate.hideForCapture({ proceeded++ }, { failed++ })
        scheduler.runTimeout()
        assertEquals(1, failed)
        scheduler.runFrame()
        assertEquals(0, proceeded)
        assertTrue(scheduler.frames.isEmpty())
    }

    @Test
    fun `gate ignores late frames after resume`() {
        val scheduler = FakeScheduler()
        val gate = OverlayCaptureGate(scheduler, { OverlayHideResult.HIDDEN })
        var proceeded = 0
        var failed = 0

        gate.hideForCapture({ proceeded++ }, { failed++ })
        gate.resumeAfterCapture()
        scheduler.frames.toList().forEach { it() }
        assertEquals(0, proceeded)
        assertEquals(0, failed)
        gate.resumeAfterCapture()
    }

    @Test
    fun `gate rejects a second capture while one is waiting`() {
        val scheduler = FakeScheduler()
        val gate = OverlayCaptureGate(scheduler, { OverlayHideResult.HIDDEN })
        var firstProceeded = 0
        var secondFailed = 0

        gate.hideForCapture({ firstProceeded++ }, {})
        gate.hideForCapture({}, { secondFailed++ })
        assertEquals(1, secondFailed)
        scheduler.runFrame()
        scheduler.runFrame()
        scheduler.runSettle()
        assertEquals(1, firstProceeded)
    }

    @Test
    fun `own overlay filter only skips this service window`() {
        assertTrue(OverlayVisuals.isOwnOverlayWindow(true, "com.psyche.kelivo.phoneagent", "com.psyche.kelivo.phoneagent"))
        assertTrue(OverlayVisuals.isOwnOverlayWindow(true, null, "com.psyche.kelivo.phoneagent"))
        assertFalse(OverlayVisuals.isOwnOverlayWindow(true, "com.other.app", "com.psyche.kelivo.phoneagent"))
        assertFalse(OverlayVisuals.isOwnOverlayWindow(false, "com.psyche.kelivo.phoneagent", "com.psyche.kelivo.phoneagent"))
        assertFalse(OverlayVisuals.isOwnOverlayWindow(false, null, "com.psyche.kelivo.phoneagent"))
    }
}
