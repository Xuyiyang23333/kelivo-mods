package com.kelivo.phoneagent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class NodeActionExecutorTest {
    private val window = WindowState(7, "com.psyche.kelivo", 100, 100, 0)

    private fun handle(actions: Set<NodeAction>): Pair<SavedHandle, FakeNode> {
        val root = FakeNode(text = "root")
        val child = FakeNode(text = "child", isClickable = true, actions = actions)
        root.children += child
        val observation = NodeTreeReader().read(
            root = root,
            windowId = 7,
            packageName = "com.psyche.kelivo",
            screenWidth = 100,
            screenHeight = 100,
            rotation = 0,
            createdAt = 0L,
            interactiveOnly = false,
        )
        val registry = ObservationRegistry(now = { 0L })
        registry.beginTree(observation)
        return registry.handle("n1", window) to child
    }

    @Test
    fun `action removed from the current node is rejected before perform`() {
        val (saved, child) = handle(setOf(NodeAction.CLICK))
        child.actions = emptySet()
        var beforeCalled = false

        val error = assertThrows(PhoneAgentError::class.java) {
            performNodeAction(saved, NodeAction.CLICK, null) { beforeCalled = true }
        }

        assertEquals("action_unavailable", error.code)
        assertFalse(beforeCalled)
        assertTrue(child.performed.isEmpty())
    }

    @Test
    fun `available action is performed after the precondition`() {
        val (saved, child) = handle(setOf(NodeAction.CLICK))
        var beforeCalled = false

        val accepted = performNodeAction(saved, NodeAction.CLICK, null) { beforeCalled = true }

        assertTrue(accepted)
        assertTrue(beforeCalled)
        assertEquals(listOf(NodeAction.CLICK), child.performed)
    }

    @Test
    fun `set_text on a non-editable node is rejected`() {
        val (saved, child) = handle(setOf(NodeAction.SET_TEXT))
        var beforeCalled = false

        val error = assertThrows(PhoneAgentError::class.java) {
            performNodeAction(saved, NodeAction.SET_TEXT, "x") { beforeCalled = true }
        }

        assertEquals("action_unavailable", error.code)
        assertFalse(beforeCalled)
        assertTrue(child.performed.isEmpty())
    }
}
