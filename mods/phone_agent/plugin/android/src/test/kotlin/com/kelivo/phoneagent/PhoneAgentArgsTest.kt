package com.kelivo.phoneagent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

class PhoneAgentArgsTest {
    @Test
    fun `int uses the default and validates the range`() {
        assertEquals(120, PhoneAgentArgs.int(null, "max_nodes", 120, 1, 200))
        assertEquals(5, PhoneAgentArgs.int(mapOf("offset" to 5), "offset", 0, 0, 100))

        assertThrows(PhoneAgentError::class.java) {
            PhoneAgentArgs.int(mapOf("max_nodes" to 0), "max_nodes", 120, 1, 200)
        }
        assertThrows(PhoneAgentError::class.java) {
            PhoneAgentArgs.int(mapOf("max_nodes" to 1.5), "max_nodes", 120, 1, 200)
        }
    }

    @Test
    fun `normalized coordinates reject non finite and out of range values`() {
        assertEquals(0.5, PhoneAgentArgs.normalized(mapOf("x" to 0.5), "x"), 0.0)

        listOf(-0.1, 1.1, Double.NaN, Double.POSITIVE_INFINITY).forEach { value ->
            assertThrows(PhoneAgentError::class.java) {
                PhoneAgentArgs.normalized(mapOf("x" to value), "x")
            }
        }
    }

    @Test
    fun `set text allows an empty string but caps the length`() {
        assertEquals("", PhoneAgentArgs.text(mapOf("text" to ""), "text"))

        assertThrows(PhoneAgentError::class.java) {
            PhoneAgentArgs.text(mapOf("text" to "a".repeat(10_001)), "text")
        }
    }

    @Test
    fun `optional strings distinguish absent and blank values`() {
        assertNull(PhoneAgentArgs.optionalString(null, "node_id"))
        assertEquals("n0", PhoneAgentArgs.optionalString(mapOf("node_id" to "n0"), "node_id"))

        assertThrows(PhoneAgentError::class.java) {
            PhoneAgentArgs.optionalString(mapOf("node_id" to "  "), "node_id")
        }
    }
}
