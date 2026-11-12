package com.kelivo.phoneagent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class NodeTreeReaderTest {
    private fun read(
        root: FakeNode,
        interactiveOnly: Boolean = false,
        reader: NodeTreeReader = NodeTreeReader(),
    ): TreeObservation = reader.read(
        root = root,
        windowId = 7,
        packageName = "com.psyche.kelivo",
        screenWidth = 100,
        screenHeight = 100,
        rotation = 0,
        createdAt = 0,
        interactiveOnly = interactiveOnly,
    )

    @Test
    fun `emits visible nodes with parent ids`() {
        val root = FakeNode(className = "root")
        val child = FakeNode(text = "hello", isClickable = true)
        root.children += child

        val observation = read(root)

        assertEquals(2, observation.records.size)
        assertEquals("n0", observation.records[0].id)
        assertNull(observation.records[0].parentId)
        assertEquals("n1", observation.records[1].id)
        assertEquals("n0", observation.records[1].parentId)
        assertEquals("hello", observation.records[1].text)
        assertTrue(observation.records[1].clickable)
    }

    @Test
    fun `skips invisible and offscreen nodes`() {
        val root = FakeNode()
        root.children += FakeNode(text = "hidden", isVisibleToUser = false)
        root.children += FakeNode(
            text = "offscreen",
            bounds = Bounds(200, 200, 300, 300),
        )

        val observation = read(root)

        assertEquals(1, observation.records.size)
    }

    @Test
    fun `hides password text and its subtree`() {
        val root = FakeNode()
        val password = FakeNode(isPassword = true, text = "secret")
        password.children += FakeNode(text = "child-secret")
        root.children += password

        val observation = read(root)

        assertEquals(2, observation.records.size)
        assertTrue(observation.records[1].password)
        assertNull(observation.records[1].text)
        assertNull(observation.records[1].description)
        assertEquals(listOf("n0", "n1"), observation.records.map { it.id })
    }

    @Test
    fun `interactive only drops text-only nodes`() {
        val root = FakeNode()
        root.children += FakeNode(text = "label")
        root.children += FakeNode(text = "button", isClickable = true)

        val observation = read(root, interactiveOnly = true)

        assertEquals(2, observation.records.size)
        assertEquals("button", observation.records[1].text)
    }

    @Test
    fun `truncates labels by text budget`() {
        val root = FakeNode(text = "abcdefgh")
        val reader = NodeTreeReader(textBudget = 5)

        val observation = read(root, reader = reader)

        assertEquals("abcde", observation.records[0].text)
        assertTrue(observation.textTruncated)
    }

    @Test
    fun `stops at the node cap`() {
        val root = FakeNode()
        repeat(5) { index -> root.children += FakeNode(text = "child-$index") }
        val reader = NodeTreeReader(maxNodes = 2)

        val observation = read(root, reader = reader)

        assertEquals(2, observation.records.size)
        assertTrue(observation.truncated)
    }

    @Test
    fun `stops below the depth cap`() {
        val root = FakeNode()
        val child = FakeNode(text = "child")
        child.children += FakeNode(text = "grandchild")
        root.children += child
        val reader = NodeTreeReader(maxDepth = 1)

        val observation = read(root, reader = reader)

        assertEquals(2, observation.records.size)
        assertTrue(observation.truncated)
    }

    @Test
    fun `records set text support from the action list`() {
        val root = FakeNode(isEditable = true, actions = setOf(NodeAction.SET_TEXT))

        val observation = read(root)

        assertTrue(observation.records[0].editable)
        assertTrue(observation.records[0].supportsSetText)
    }

    @Test
    fun `records child index paths for re-resolution`() {
        val root = FakeNode(text = "root")
        val first = FakeNode(text = "first")
        val nested = FakeNode(text = "nested")
        first.children += nested
        root.children += first
        root.children += FakeNode(text = "second")

        val observation = read(root)

        assertEquals(listOf(emptyList<Int>(), listOf(0), listOf(0, 0), listOf(1)), observation.paths)
    }

    @Test
    fun `does not report truncation for a small tree`() {
        val root = FakeNode()
        root.children += FakeNode(text = "one")

        val observation = read(root)

        assertFalse(observation.truncated)
        assertFalse(observation.textTruncated)
    }
}
