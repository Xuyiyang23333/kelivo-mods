package com.kelivo.phoneagent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class ObservationRegistryTest {
    private var now = 0L
    private lateinit var registry: ObservationRegistry
    private val window = WindowState(7, TEST_PACKAGE, 100, 100, 0, WindowType.APPLICATION)

    @Before
    fun setUp() {
        now = 0L
        registry = ObservationRegistry(now = { now })
    }

    private fun readTree(root: FakeNode): TreeObservation = NodeTreeReader().read(
        root = root,
        windowId = 7,
        packageName = TEST_PACKAGE,
        screenWidth = 100,
        screenHeight = 100,
        rotation = 0,
        windowType = WindowType.APPLICATION,
        createdAt = now,
        interactiveOnly = false,
    )

    private fun observation(text: String = "hello"): Pair<FakeNode, TreeObservation> {
        val root = FakeNode(text = text)
        root.children += FakeNode(text = "child", isClickable = true)
        return root to readTree(root)
    }

    private fun editableObservation(): Pair<FakeNode, FakeNode> {
        val root = FakeNode(text = "root")
        val field = FakeNode(
            className = "android.widget.EditText",
            text = "",
            isEditable = true,
            isClickable = true,
            actions = setOf(NodeAction.CLICK, NodeAction.SET_TEXT),
        )
        root.children += field
        registry.beginTree(readTree(root))
        return root to field
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
    fun `gaining focus keeps a handle reusable for set_text`() {
        val (_, field) = editableObservation()

        val before = registry.handle("n1", window)
        field.isFocused = true
        val after = registry.handle("n1", window)

        assertEquals("n1", before.id)
        assertEquals("n1", after.id)
        assertTrue(NodeAction.SET_TEXT in after.node.actions)
        assertTrue(after.node.perform(NodeAction.SET_TEXT, "phone agent"))
        assertEquals(listOf(NodeAction.SET_TEXT), field.performed)
    }

    @Test
    fun `losing focus keeps a handle reusable`() {
        val root = FakeNode(text = "root")
        val field = FakeNode(text = "child", isFocused = true)
        root.children += field
        registry.beginTree(readTree(root))

        field.isFocused = false
        val handle = registry.handle("n1", window)

        assertEquals("n1", handle.id)
        assertEquals("child", handle.record.text)
    }

    @Test
    fun `selection change invalidates a handle`() {
        val (root, observation) = observation()
        registry.beginTree(observation)
        (root.children[0] as FakeNode).isSelected = true

        val error = assertThrows(PhoneAgentError::class.java) {
            registry.handle("n1", window)
        }

        assertEquals("stale_handle", error.code)
    }

    @Test
    fun `action change keeps a handle reusable`() {
        val (root, observation) = observation()
        registry.beginTree(observation)
        (root.children[0] as FakeNode).actions = setOf(NodeAction.CLICK)

        val handle = registry.handle("n1", window)

        assertEquals("n1", handle.id)
    }

    @Test
    fun `capability change invalidates a handle`() {
        val (root, observation) = observation()
        registry.beginTree(observation)
        (root.children[0] as FakeNode).isScrollable = true

        val error = assertThrows(PhoneAgentError::class.java) {
            registry.handle("n1", window)
        }

        assertEquals("stale_handle", error.code)
        assertTrue(error.message.contains("isScrollable"))
    }

    @Test
    fun `handle expires after the ttl`() {
        val (_, observation) = observation()
        registry.beginTree(observation)
        now = ObservationRegistry.DEFAULT_TTL_MILLIS + 1

        val error = assertThrows(PhoneAgentError::class.java) {
            registry.handle("n1", window)
        }

        assertEquals("stale_handle", error.code)
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
        assertTrue(error.message.contains("text"))
    }

    @Test
    fun `content change with NUL only reports the field name`() {
        val (root, observation) = observation()
        registry.beginTree(observation)
        (root.children[0] as FakeNode).text = "changed\u0000private-content"

        val error = assertThrows(PhoneAgentError::class.java) {
            registry.handle("n1", window)
        }

        assertEquals("stale_handle", error.code)
        assertTrue(error.message.contains("text"))
        assertFalse(error.message.contains("private-content"))
        assertFalse(error.message.contains("\u0000"))
    }

    @Test
    fun `refresh failure reports refresh_failed without node content`() {
        val (root, observation) = observation()
        registry.beginTree(observation)
        val child = root.children[0] as FakeNode
        child.text = "secret-refresh-content"
        child.refreshResult = false
        child.isVisibleToUser = false
        child.isEnabled = false

        val error = assertThrows(PhoneAgentError::class.java) {
            registry.handle("n1", window)
        }

        assertEquals("stale_handle", error.code)
        assertTrue(error.message.contains("refresh_failed"))
        assertFalse(error.message.contains("not_visible"))
        assertFalse(error.message.contains("not_enabled"))
        assertFalse(error.message.contains("secret-refresh-content"))
    }

    @Test
    fun `invisible node reports not_visible without node content`() {
        val (root, observation) = observation()
        registry.beginTree(observation)
        val child = root.children[0] as FakeNode
        child.text = "secret-hidden-content"
        child.isVisibleToUser = false

        val error = assertThrows(PhoneAgentError::class.java) {
            registry.handle("n1", window)
        }

        assertEquals("stale_handle", error.code)
        assertTrue(error.message.contains("not_visible"))
        assertFalse(error.message.contains("refresh_failed"))
        assertFalse(error.message.contains("not_enabled"))
        assertFalse(error.message.contains("secret-hidden-content"))
    }

    @Test
    fun `disabled node reports not_enabled without node content`() {
        val (root, observation) = observation()
        registry.beginTree(observation)
        val child = root.children[0] as FakeNode
        child.text = "secret-disabled-content"
        child.isEnabled = false

        val error = assertThrows(PhoneAgentError::class.java) {
            registry.handle("n1", window)
        }

        assertEquals("stale_handle", error.code)
        assertTrue(error.message.contains("not_enabled"))
        assertFalse(error.message.contains("refresh_failed"))
        assertFalse(error.message.contains("not_visible"))
        assertFalse(error.message.contains("secret-disabled-content"))
    }

    @Test
    fun `refresh failure re-resolves the same node by path`() {
        val root = FakeNode(text = "root")
        val field = FakeNode(
            className = "android.widget.EditText",
            text = "",
            isEditable = true,
            actions = setOf(NodeAction.CLICK, NodeAction.SET_TEXT),
        )
        root.children += field
        val observation = readTree(root)
        val replacement = FakeNode(text = "root")
        val replacementField = FakeNode(
            className = "android.widget.EditText",
            text = "",
            isEditable = true,
            actions = setOf(NodeAction.CLICK, NodeAction.SET_TEXT),
        )
        replacement.children += replacementField
        registry = ObservationRegistry(now = { now }, rootProvider = { replacement })
        registry.beginTree(observation)
        field.refreshResult = false

        val handle = registry.handle("n1", window)

        assertEquals("n1", handle.id)
        assertTrue(handle.node === replacementField)
        assertTrue(handle.node.perform(NodeAction.SET_TEXT, "x"))
        assertEquals(listOf(NodeAction.SET_TEXT), replacementField.performed)
    }

    @Test
    fun `refresh failure with a changed fingerprint still fails`() {
        val root = FakeNode(text = "root")
        val field = FakeNode(text = "before", isClickable = true)
        root.children += field
        val observation = readTree(root)
        val replacement = FakeNode(text = "root")
        val replacementField = FakeNode(text = "after", isClickable = true)
        replacement.children += replacementField
        registry = ObservationRegistry(now = { now }, rootProvider = { replacement })
        registry.beginTree(observation)
        field.refreshResult = false

        val error = assertThrows(PhoneAgentError::class.java) {
            registry.handle("n1", window)
        }

        assertEquals("stale_handle", error.code)
        assertTrue(error.message.contains("refresh_failed"))
        assertFalse(error.message.contains("after"))
    }

    @Test
    fun `re-resolution recycles intermediate nodes along the path`() {
        val root = FakeNode(text = "root")
        val middle = FakeNode(text = "middle")
        val field = FakeNode(
            className = "android.widget.EditText",
            text = "",
            isEditable = true,
            actions = setOf(NodeAction.CLICK, NodeAction.SET_TEXT),
        )
        middle.children += field
        root.children += middle
        val observation = readTree(root)
        val replacement = FakeNode(text = "root")
        val replacementMiddle = FakeNode(text = "middle")
        val replacementField = FakeNode(
            className = "android.widget.EditText",
            text = "",
            isEditable = true,
            actions = setOf(NodeAction.CLICK, NodeAction.SET_TEXT),
        )
        replacementMiddle.children += replacementField
        replacement.children += replacementMiddle
        registry = ObservationRegistry(now = { now }, rootProvider = { replacement })
        registry.beginTree(observation)
        field.refreshResult = false

        val handle = registry.handle("n2", window)

        assertTrue(handle.node === replacementField)
        // 契约：每层 child() 都返回可独立回收的引用，重解析路上的中间节点各回收一次。
        assertEquals(1, replacement.recycleCount)
        assertEquals(1, replacementMiddle.recycleCount)
        assertEquals(0, replacementField.recycleCount)
        assertTrue(handle.node.perform(NodeAction.SET_TEXT, "ok"))
    }

    @Test
    fun `failed re-resolution still recycles nodes visited along the path`() {
        val root = FakeNode(text = "root")
        val middle = FakeNode(text = "middle")
        val field = FakeNode(text = "child", isClickable = true)
        middle.children += field
        root.children += middle
        val observation = readTree(root)
        val replacement = FakeNode(text = "root")
        val replacementMiddle = FakeNode(text = "middle")
        replacementMiddle.children += FakeNode(text = "changed", isClickable = true)
        replacement.children += replacementMiddle
        registry = ObservationRegistry(now = { now }, rootProvider = { replacement })
        registry.beginTree(observation)
        field.refreshResult = false

        val error = assertThrows(PhoneAgentError::class.java) {
            registry.handle("n2", window)
        }

        assertEquals("stale_handle", error.code)
        assertTrue(error.message.contains("refresh_failed"))
        // 指纹不等时也要回收路径上已取得的节点，避免 AccessibilityNodeInfo 泄漏。
        assertEquals(1, replacement.recycleCount)
        assertEquals(1, replacementMiddle.recycleCount)
    }

    @Test
    fun `refresh failure with a missing path still fails`() {
        val root = FakeNode(text = "root")
        val field = FakeNode(text = "child", isClickable = true)
        root.children += field
        val observation = readTree(root)
        val replacement = FakeNode(text = "root")
        registry = ObservationRegistry(now = { now }, rootProvider = { replacement })
        registry.beginTree(observation)
        field.refreshResult = false

        val error = assertThrows(PhoneAgentError::class.java) {
            registry.handle("n1", window)
        }

        assertEquals("stale_handle", error.code)
        assertTrue(error.message.contains("refresh_failed"))
    }

    @Test
    fun `refresh failure without a root provider still fails`() {
        val root = FakeNode(text = "root")
        val field = FakeNode(text = "child", isClickable = true)
        root.children += field
        val observation = readTree(root)
        registry.beginTree(observation)
        field.refreshResult = false

        val error = assertThrows(PhoneAgentError::class.java) {
            registry.handle("n1", window)
        }

        assertEquals("stale_handle", error.code)
        assertTrue(error.message.contains("refresh_failed"))
    }

    @Test
    fun `successful refresh does not re-resolve`() {
        val root = FakeNode(text = "root")
        val field = FakeNode(text = "child", isClickable = true)
        root.children += field
        val observation = readTree(root)
        var providerCalls = 0
        registry = ObservationRegistry(
            now = { now },
            rootProvider = {
                providerCalls++
                FakeNode(text = "other")
            },
        )
        registry.beginTree(observation)

        val handle = registry.handle("n1", window)

        assertEquals("n1", handle.id)
        assertEquals(0, providerCalls)
    }

    @Test
    fun `re-resolved handle is reused for the next action`() {
        val root = FakeNode(text = "root")
        val field = FakeNode(text = "child", isClickable = true)
        root.children += field
        val observation = readTree(root)
        val replacement = FakeNode(text = "root")
        val replacementField = FakeNode(text = "child", isClickable = true)
        replacement.children += replacementField
        registry = ObservationRegistry(now = { now }, rootProvider = { replacement })
        registry.beginTree(observation)
        field.refreshResult = false

        val first = registry.handle("n1", window)
        val second = registry.handle("n1", window)

        assertTrue(first.node === replacementField)
        assertTrue(second.node === replacementField)
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
    fun `window type change invalidates handles and pages`() {
        val (_, observation) = observation()
        registry.beginTree(observation)

        val page = assertThrows(PhoneAgentError::class.java) {
            registry.page(0, 1, window.copy(windowType = WindowType.SYSTEM))
        }
        assertEquals("stale_observation", page.code)

        registry.beginTree(observation("again").second)
        val handle = assertThrows(PhoneAgentError::class.java) {
            registry.handle("n0", window.copy(windowType = WindowType.INPUT_METHOD))
        }
        assertEquals("stale_handle", handle.code)
    }

    @Test
    fun `window type change invalidates the screenshot`() {
        registry.recordScreenshot(
            ScreenshotObservation(
                800,
                600,
                100,
                100,
                7,
                TEST_PACKAGE,
                0,
                WindowType.APPLICATION,
                now,
            ),
        )

        val error = assertThrows(PhoneAgentError::class.java) {
            registry.requireScreenshot(window.copy(windowType = WindowType.SYSTEM))
        }

        assertEquals("stale_observation", error.code)
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
            ScreenshotObservation(800, 600, 100, 100, 7, TEST_PACKAGE, 0, WindowType.APPLICATION, now),
        )
        registry.clearScreenshot()

        val handle = registry.handle("n1", window)

        assertEquals("n1", handle.id)
        assertEquals("child", handle.record.text)
    }

    @Test
    fun `screenshot observation validates the window`() {
        registry.recordScreenshot(
            ScreenshotObservation(800, 600, 100, 100, 7, TEST_PACKAGE, 0, WindowType.APPLICATION, now),
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
            ScreenshotObservation(800, 600, 100, 100, 7, TEST_PACKAGE, 0, WindowType.APPLICATION, now),
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
