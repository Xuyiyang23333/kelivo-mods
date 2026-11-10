package com.kelivo.phoneagent

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ActionBudgetTest {
    private var now = 0L

    @Test
    fun `consumes up to the limit and resets after the window`() {
        val budget = ActionBudget(limit = 2, windowMillis = 1000, now = { now })

        assertTrue(budget.tryConsume())
        assertTrue(budget.tryConsume())
        assertFalse(budget.tryConsume())

        now = 1000
        assertTrue(budget.tryConsume())
    }

    @Test
    fun `keeps a sliding window`() {
        val budget = ActionBudget(limit = 1, windowMillis = 1000, now = { now })

        assertTrue(budget.tryConsume())
        now = 999
        assertFalse(budget.tryConsume())
        now = 1000
        assertTrue(budget.tryConsume())
    }
}
