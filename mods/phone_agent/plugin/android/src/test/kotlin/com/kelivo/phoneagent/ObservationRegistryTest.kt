package com.kelivo.phoneagent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class ObservationRegistryTest {
    private var now = 0L
    private lateinit var registry: ObservationRegistry
    private val window = WindowState(7, "com.psyche.kelivo", 100, 100, 0)

    @Before
    fun setUp() {
        now = 0L
        registry = ObservationRegistry(now = { now })
    }

    private fun observation(text: String = "hello"): Pair<FakeNode, TreeObservation> {
        val root = FakeNode(text = text)
        root.children += FakeNode(text = "child", isClickable = true)
        val observation = NodeTreeReader().read(
            root = root,
            windowId = 7,
            packageName = "com.psyche.kelivo",
            screenWidth = 100,
            screenHeight = 100,
            rotation = 0,
            createdAt = now,
            interactiveOnly = false,
        )
        return root to observation
    }

    @Test
    fun `pages without renumbering`() {
        val (_, observation) = observation()
        registry.beginTree(observation)

        val first = registry.page(0, 1, window)
        assertEquals(1, first.records.size)
        assertEquals("n0", first.records[0].id)
        assertEquals(1, first.nextOffset ?: -1)

        val second = registry.page(1, 1, window)
        assertEquals(1, second.records.size)
        assertEquals("n1", second.records[0].id)
        assertNull(second.nextOffset)
        assertEquals(2, second.total)
    }

    @Test
    fun `page beyond the end is empty`() {
        val (_, observation) = observation()
        registry.beginTree(observation)

        val page = registry.page(10, 5, window)

        assertTrue(page.records.isEmpty())
        assertNull(page.nextOffset)
        assertEquals(2, page.total)
    }

    @Test
    fun `tree expires after the ttl`() {
        val (_, observation) = observation()
        registry.beginTree(observation)
        now = ObservationRegistry.DEFAULT_TTL_MILLIS + 1

        val error = assertThrows(PhoneAgentError::class.java) {
            registry.page(0, 1, window)
        }

        assertEquals("stale_observation", error.code)
    }

    @Test
    fun `window change invalidates the tree`() {
        val (_, observation) = observation()
        registry.beginTree(observation)

        val error = assertThrows(PhoneAgentError::class.java) {
            registry.page(0, 1, window.copy(packageName = "com.other.app"))
        }

        assertEquals("stale_observation", error.code)
    }

    @Test
    fun `valid handles can be reused`() {
        val (_, observation) = observation()
        registry.beginTree(observation)

        val first = registry.handle("n1", window)
        val second = registry.handle("n1", window)

        assertEquals("n1", first.id)
        assertEquals("child", first.record.text)
        assertEquals("n1", second.id)
    }

    @Test
    fun `fingerprint change invalidates a handle`() {
        val (root, observation) = observation()
        registry.beginTree(observation)
        registry.handle("n1", window)
        (root.children[0] as FakeNode).text = "changed"

        val error = assertThrows(PhoneAgentError::class.java) {
            registry.handle("n1", window)
        }

        assertEquals("stale_handle", error.code)
    }

    @Test
    fun `refresh failure invalidates a handle`() {
        val (root, observation) = observation()
        registry.beginTree(observation)
        (root.children[0] as FakeNode).refreshResult = false

        val error = assertThrows(PhoneAgentError::class.java) {
            registry.handle("n1", window)
        }

        assertEquals("stale_handle", error.code)
    }

    @Test
    fun `invisible handle is rejected`() {
        val (root, observation) = observation()
        registry.beginTree(observation)
        (root.children[0] as FakeNode).isVisibleToUser = false

        val error = assertThrows(PhoneAgentError::class.java) {
            registry.handle("n1", window)
        }

        assertEquals("stale_handle", error.code)
    }

    @Test
    fun `unknown handle is rejected`() {
        val (_, observation) = observation()
        registry.beginTree(observation)

        val error = assertThrows(PhoneAgentError::class.java) {
            registry.handle("n99", window)
        }

        assertEquals("stale_handle", error.code)
    }

    @Test
    fun `window change invalidates handles`() {
        val (_, observation) = observation()
        registry.beginTree(observation)

        val error = assertThrows(PhoneAgentError::class.java) {
            registry.handle("n0", window.copy(rotation = 1))
        }

        assertEquals("stale_handle", error.code)
    }

    @Test
    fun `a new observation renumbers handles`() {
        val (_, first) = observation("first")
        registry.beginTree(first)
        val (_, second) = observation("second")
        registry.beginTree(second)

        val handle = registry.handle("n0", window)

        assertEquals("second", handle.record.text)
    }

    @Test
    fun `clearing the screenshot keeps tree handles reusable`() {
        val (_, observation) = observation()
        registry.beginTree(observation)
        registry.recordScreenshot(
            ScreenshotObservation(800, 600, 100, 100, 7, "com.psyche.kelivo", 0, now),
        )
        registry.clearScreenshot()

        val handle = registry.handle("n1", window)

        assertEquals("n1", handle.id)
        assertEquals("child", handle.record.text)
    }

    @Test
    fun `screenshot observation validates the window`() {
        registry.recordScreenshot(
            ScreenshotObservation(800, 600, 100, 100, 7, "com.psyche.kelivo", 0, now),
        )

        val screenshot = registry.requireScreenshot(window)
        assertEquals(800, screenshot.imageWidth)

        val error = assertThrows(PhoneAgentError::class.java) {
            registry.requireScreenshot(window.copy(rotation = 1))
        }
        assertEquals("stale_observation", error.code)
    }

    @Test
    fun `screenshot is required before coordinates`() {
        val error = assertThrows(PhoneAgentError::class.java) {
            registry.requireScreenshot(window)
        }

        assertEquals("screenshot_required", error.code)
    }

    @Test
    fun `screenshot expires after the ttl`() {
        registry.recordScreenshot(
            ScreenshotObservation(800, 600, 100, 100, 7, "com.psyche.kelivo", 0, now),
        )
        now = ObservationRegistry.DEFAULT_TTL_MILLIS + 1

        val expired = assertThrows(PhoneAgentError::class.java) {
            registry.requireScreenshot(window)
        }
        assertEquals("stale_observation", expired.code)

        val missing = assertThrows(PhoneAgentError::class.java) {
            registry.requireScreenshot(window)
        }
        assertEquals("screenshot_required", missing.code)
    }

    @Test
    fun `invalidate all clears handles`() {
        val (_, observation) = observation()
        registry.beginTree(observation)
        registry.invalidateAll()

        val error = assertThrows(PhoneAgentError::class.java) {
            registry.handle("n0", window)
        }

        assertEquals("stale_handle", error.code)
    }
}
