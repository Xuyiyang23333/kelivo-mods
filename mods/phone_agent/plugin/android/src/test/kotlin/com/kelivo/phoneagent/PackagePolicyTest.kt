package com.kelivo.phoneagent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class PackagePolicyTest {
    private val policy = PackagePolicy()

    @Test
    fun `allows the test package`() {
        policy.requireInputAllowed("com.psyche.kelivo.phoneagent")
    }

    @Test
    fun `rejects other packages`() {
        val error = assertThrows(PhoneAgentError::class.java) {
            policy.requireInputAllowed("com.example.app")
        }

        assertEquals("package_not_allowed", error.code)
    }

    @Test
    fun `rejects system windows`() {
        val error = assertThrows(PhoneAgentError::class.java) {
            policy.requireInputAllowed("com.android.systemui")
        }

        assertEquals("system_window_denied", error.code)
    }

    @Test
    fun `rejects permission dialogs`() {
        val error = assertThrows(PhoneAgentError::class.java) {
            policy.requireInputAllowed("com.google.android.permissioncontroller")
        }

        assertEquals("system_window_denied", error.code)
    }

    @Test
    fun `rejects a missing package`() {
        val error = assertThrows(PhoneAgentError::class.java) {
            policy.requireInputAllowed(null)
        }

        assertEquals("no_window", error.code)
    }
}
