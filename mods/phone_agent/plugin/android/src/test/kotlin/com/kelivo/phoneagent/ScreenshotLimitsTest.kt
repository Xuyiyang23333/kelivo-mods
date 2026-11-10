package com.kelivo.phoneagent

import android.accessibilityservice.AccessibilityService
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class ScreenshotLimitsTest {
    private var now = 0L

    @Test
    fun `enforces the minimum interval`() {
        val throttle = ScreenshotThrottle(
            minIntervalMillis = 1000,
            maxPerMinute = 10,
            now = { now },
        )

        assertTrue(throttle.tryAcquire())
        now = 500
        assertFalse(throttle.tryAcquire())
        now = 1000
        assertTrue(throttle.tryAcquire())
    }

    @Test
    fun `enforces the per minute limit`() {
        val throttle = ScreenshotThrottle(
            minIntervalMillis = 1000,
            maxPerMinute = 2,
            now = { now },
        )

        assertTrue(throttle.tryAcquire())
        now = 1000
        assertTrue(throttle.tryAcquire())
        now = 2000
        assertFalse(throttle.tryAcquire())
        now = 61_000
        assertTrue(throttle.tryAcquire())
    }

    @Test
    fun `scales password bounds`() {
        val scaled = ScreenshotMasker.scaledBounds(
            Bounds(10, 20, 110, 220),
            scaleX = 0.5,
            scaleY = 0.5,
            width = 800,
            height = 600,
        )

        assertEquals(Bounds(5, 10, 55, 110), scaled)
    }

    @Test
    fun `clamps password bounds to the image`() {
        val scaled = ScreenshotMasker.scaledBounds(
            Bounds(-10, -10, 1000, 1000),
            scaleX = 1.0,
            scaleY = 1.0,
            width = 100,
            height = 100,
        )

        assertEquals(Bounds(0, 0, 100, 100), scaled)
    }

    @Test
    fun `expands fractional password bounds to cover the whole area`() {
        val scaled = ScreenshotMasker.scaledBounds(
            Bounds(10, 10, 20, 20),
            scaleX = 0.33,
            scaleY = 0.33,
            width = 100,
            height = 100,
        )

        assertEquals(Bounds(3, 3, 7, 7), scaled)
    }

    @Test
    fun `accepts screenshots with the same aspect ratio`() {
        assertTrue(ScreenshotMasker.matchesAspectRatio(1080, 2400, 1080, 2400))
        assertTrue(ScreenshotMasker.matchesAspectRatio(540, 1200, 1080, 2400))
    }

    @Test
    fun `rejects rotated or resized screenshots`() {
        assertFalse(ScreenshotMasker.matchesAspectRatio(2400, 1080, 1080, 2400))
        assertFalse(ScreenshotMasker.matchesAspectRatio(1080, 2340, 1080, 2400))
        assertFalse(ScreenshotMasker.matchesAspectRatio(0, 2400, 1080, 2400))
        assertFalse(ScreenshotMasker.matchesAspectRatio(1080, 2400, 0, 2400))
    }

    @Test
    fun `maps Android screenshot errors to actionable codes`() {
        assertEquals(
            "rate_limited",
            ScreenshotCapture.mapError(
                AccessibilityService.ERROR_TAKE_SCREENSHOT_INTERVAL_TIME_SHORT,
            ).code,
        )
        assertEquals(
            "screenshot_blocked",
            ScreenshotCapture.mapError(
                AccessibilityService.ERROR_TAKE_SCREENSHOT_SECURE_WINDOW,
            ).code,
        )
        assertEquals(
            "screenshot_blocked",
            ScreenshotCapture.mapError(
                AccessibilityService.ERROR_TAKE_SCREENSHOT_INVALID_DISPLAY,
            ).code,
        )
        assertEquals(
            "screenshot_blocked",
            ScreenshotCapture.mapError(
                AccessibilityService.ERROR_TAKE_SCREENSHOT_INTERNAL_ERROR,
            ).code,
        )
        assertEquals("screenshot_blocked", ScreenshotCapture.mapError(999).code)
    }

    @Test
    fun `collects password bounds and their direct children`() {
        val root = FakeNode()
        val password = FakeNode(isPassword = true, bounds = Bounds(10, 10, 90, 40))
        password.children += FakeNode(bounds = Bounds(10, 10, 90, 40))
        root.children += password

        val bounds = ScreenshotCapture.collectPasswordBounds(listOf(root), 100, 100)

        assertEquals(
            listOf(Bounds(10, 10, 90, 40), Bounds(10, 10, 90, 40)),
            bounds,
        )
        assertEquals(1, root.recycleCount)
        assertEquals(1, password.recycleCount)
    }

    @Test
    fun `collects password bounds from every window root`() {
        val first = FakeNode()
        first.children += FakeNode(isPassword = true, bounds = Bounds(10, 10, 90, 40))
        val second = FakeNode()
        val secondPassword = FakeNode(isPassword = true, bounds = Bounds(0, 50, 100, 80))
        secondPassword.children += FakeNode(bounds = Bounds(0, 50, 100, 80))
        second.children += secondPassword

        val bounds = ScreenshotCapture.collectPasswordBounds(listOf(first, second), 100, 100)

        assertEquals(
            listOf(
                Bounds(10, 10, 90, 40),
                Bounds(0, 50, 100, 80),
                Bounds(0, 50, 100, 80),
            ),
            bounds,
        )
        assertEquals(1, first.recycleCount)
        assertEquals(1, second.recycleCount)
        assertEquals(1, secondPassword.recycleCount)
    }

    @Test
    fun `recycles every window root when traversal fails`() {
        val broken = FakeNode().apply { failOnChildCount = true }
        val healthy = FakeNode()

        val error = assertThrows(IllegalStateException::class.java) {
            ScreenshotCapture.collectPasswordBounds(listOf(broken, healthy), 100, 100)
        }

        assertEquals("childCount failed", error.message)
        assertEquals(1, broken.recycleCount)
        assertEquals(1, healthy.recycleCount)
    }
}
