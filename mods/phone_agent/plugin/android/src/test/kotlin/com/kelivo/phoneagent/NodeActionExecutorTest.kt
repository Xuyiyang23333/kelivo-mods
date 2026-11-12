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
            performNodeAction(
                handle = saved,
                action = NodeAction.CLICK,
                text = null,
                beforeAction = { beforeCalled = true },
            )
        }

        assertEquals("action_unavailable", error.code)
        assertFalse(beforeCalled)
        assertTrue(child.performed.isEmpty())
    }

    @Test
    fun `available action is performed after the precondition`() {
        val (saved, child) = handle(setOf(NodeAction.CLICK))
        var beforeCalled = false

        val accepted = performNodeAction(
            handle = saved,
            action = NodeAction.CLICK,
            text = null,
            beforeAction = { beforeCalled = true },
        )

        assertTrue(accepted)
        assertTrue(beforeCalled)
        assertEquals(listOf(NodeAction.CLICK), child.performed)
    }

    @Test
    fun `set_text on a non-editable node is rejected`() {
        val (saved, child) = handle(setOf(NodeAction.SET_TEXT))
        var beforeCalled = false

        val error = assertThrows(PhoneAgentError::class.java) {
            performNodeAction(
                handle = saved,
                action = NodeAction.SET_TEXT,
                text = "x",
                beforeAction = { beforeCalled = true },
            )
        }

        assertEquals("action_unavailable", error.code)
        assertFalse(beforeCalled)
        assertTrue(child.performed.isEmpty())
    }

    @Test
    fun `rejected action produces no visual`() {
        val (saved, child) = handle(setOf(NodeAction.CLICK))
        child.actions = emptySet()
        val visuals = mutableListOf<Pair<Bounds, NodeAction>>()

        assertThrows(PhoneAgentError::class.java) {
            performNodeAction(
                handle = saved,
                action = NodeAction.CLICK,
                text = null,
                visual = { bounds, action -> visuals += bounds to action },
            )
        }

        assertTrue(visuals.isEmpty())
    }

    @Test
    fun `visual receives the refreshed bounds after the action is accepted`() {
        val (saved, child) = handle(setOf(NodeAction.CLICK))
        child.bounds = Bounds(10, 20, 110, 220)
        val visuals = mutableListOf<Pair<Bounds, NodeAction>>()

        val accepted = performNodeAction(
            handle = saved,
            action = NodeAction.CLICK,
            text = null,
            visual = { bounds, action -> visuals += bounds to action },
        )

        assertTrue(accepted)
        assertEquals(listOf(Bounds(10, 20, 110, 220) to NodeAction.CLICK), visuals)
    }

    @Test
    fun `perform rejection produces no visual`() {
        val (saved, child) = handle(setOf(NodeAction.CLICK))
        child.performResult = false
        val visuals = mutableListOf<Pair<Bounds, NodeAction>>()

        val accepted = performNodeAction(
            handle = saved,
            action = NodeAction.CLICK,
            text = null,
            visual = { bounds, action -> visuals += bounds to action },
        )

        assertFalse(accepted)
        assertTrue(visuals.isEmpty())
        assertEquals(listOf(NodeAction.CLICK), child.performed)
    }

    @Test
    fun `visual failure does not change the accepted result`() {
        val (saved, _) = handle(setOf(NodeAction.CLICK))

        val accepted = performNodeAction(
            handle = saved,
            action = NodeAction.CLICK,
            text = null,
            visual = { _, _ -> throw IllegalStateException("overlay failed") },
        )

        assertTrue(accepted)
    }
}
