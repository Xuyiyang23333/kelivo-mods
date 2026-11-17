package com.kelivo.phoneagent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneAgentResultTest {
    private fun record(
        id: String = "n0",
        password: Boolean = false,
        text: String? = "hello",
    ) = NodeRecord(
        id = id,
        parentId = null,
        bounds = Bounds(0, 0, 100, 50),
        className = "android.widget.TextView",
        text = text,
        description = null,
        hint = null,
        stateDescription = null,
        viewId = "com.psyche.kelivo:id/title",
        enabled = true,
        clickable = true,
        longClickable = false,
        editable = false,
        supportsSetText = false,
        scrollable = false,
        checkable = false,
        checked = false,
        focused = false,
        selected = false,
        password = password,
    )

    @Test
    fun `tree page has pagination fields and no snapshot id`() {
        val page = TreePage(
            records = listOf(record()),
            offset = 0,
            nextOffset = 1,
            total = 2,
            truncated = false,
            textTruncated = false,
            packageName = "com.psyche.kelivo",
            screenWidth = 1080,
            screenHeight = 2400,
        )

        val result = PhoneAgentResult.treePage(page)

        assertFalse(result.containsKey("snapshot_id"))
        assertEquals(0, result["offset"])
        assertEquals(1, result["next_offset"])
        assertEquals(2, result["total"])
        assertEquals("com.psyche.kelivo", result["package_name"])
        assertEquals(1080, result["width"])
        assertEquals(2400, result["height"])
        @Suppress("UNCHECKED_CAST")
        val nodes = result["nodes"] as List<Map<String, Any?>>
        assertEquals(1, nodes.size)
        assertEquals("n0", nodes[0]["node_id"])
    }

    @Test
    fun `password nodes never expose text fields`() {
        val node = PhoneAgentResult.node(
            record(password = true, text = "secret"),
        )

        assertEquals(true, node["password"])
        assertFalse(node.containsKey("text"))
        assertFalse(node.containsKey("description"))
        assertFalse(node.containsKey("hint"))
        assertFalse(node.containsKey("state_description"))
    }

    @Test
    fun `normal nodes include interaction flags`() {
        val node = PhoneAgentResult.node(record())

        assertEquals("hello", node["text"])
        assertEquals(true, node["clickable"])
        assertEquals(true, node["enabled"])
        assertEquals("com.psyche.kelivo:id/title", node["resource_id"])
        assertNull(node["password"])
    }

    @Test
    fun `screenshot result has image and screen dimensions`() {
        val result = PhoneAgentResult.screenshot(
            CapturedScreenshot(
                bytes = byteArrayOf(1, 2, 3),
                imageWidth = 800,
                imageHeight = 600,
                screenWidth = 1080,
                screenHeight = 2400,
                windowId = 7,
                packageName = KELIVO_PACKAGE,
                rotation = 0,
                windowType = WindowType.APPLICATION,
            ),
        )

        assertFalse(result.containsKey("snapshot_id"))
        assertEquals(800, result["imageWidth"])
        assertEquals(600, result["imageHeight"])
        assertEquals(1080, result["screenWidth"])
        assertEquals(2400, result["screenHeight"])
        assertEquals("com.psyche.kelivo", result["packageName"])
        assertTrue((result["bytes"] as ByteArray).isNotEmpty())
    }

    @Test
    fun `input success reports the action`() {
        val result = PhoneAgentResult.inputSuccess("tap", "Action accepted.")

        assertEquals(true, result["success"])
        assertEquals("tap", result["action"])
        assertEquals("Action accepted.", result["message"])
        assertFalse(result.containsKey("snapshot_id"))
    }

    @Test
    fun `apps list and open app payloads omit snapshot id`() {
        val apps = PhoneAgentResult.appsList(
            listOf(mapOf("name" to "Notes", "package_name" to "com.example.notes")),
        )
        assertEquals(1, (apps["apps"] as List<*>).size)

        val launched = PhoneAgentResult.openAppSuccess("com.example.notes")
        assertEquals(true, launched["success"])
        assertEquals("open_app", launched["action"])
        assertEquals("com.example.notes", launched["package_name"])
        assertFalse(launched.containsKey("snapshot_id"))

        val waited = PhoneAgentResult.waitSuccess(1200)
        assertEquals(true, waited["success"])
        assertEquals("wait", waited["action"])
        assertEquals(1200L, waited["duration_ms"])
        assertFalse(waited.containsKey("snapshot_id"))
    }
}
