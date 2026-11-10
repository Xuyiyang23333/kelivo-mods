package com.kelivo.phoneagent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class CoordinateMapperTest {
    @Test
    fun `maps normalized coordinates into pixels`() {
        assertEquals(0f, CoordinateMapper.toPixel(0.0, 1000, "x"), 0.001f)
        assertEquals(500f, CoordinateMapper.toPixel(0.5, 1000, "x"), 0.001f)
        assertEquals(999f, CoordinateMapper.toPixel(1.0, 1000, "x"), 0.001f)
    }

    @Test
    fun `rejects invalid normalized values`() {
        listOf(-0.1, 1.1, Double.NaN, Double.POSITIVE_INFINITY).forEach { value ->
            val error = assertThrows(PhoneAgentError::class.java) {
                CoordinateMapper.toPixel(value, 1000, "x")
            }
            assertEquals("invalid_argument", error.code)
        }
    }

    @Test
    fun `rejects an unknown screen size`() {
        val error = assertThrows(PhoneAgentError::class.java) {
            CoordinateMapper.toPixel(0.5, 0, "x")
        }

        assertEquals("stale_observation", error.code)
    }
}
