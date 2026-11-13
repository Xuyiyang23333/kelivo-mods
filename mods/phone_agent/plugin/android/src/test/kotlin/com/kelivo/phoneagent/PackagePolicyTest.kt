package com.kelivo.phoneagent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class PackagePolicyTest {
    private val policy = PackagePolicy()
    private val noRoles = RoleHolders.Resolved(emptySet())

    private fun require(
        packageName: String?,
        windowType: WindowType = WindowType.APPLICATION,
        roleHolders: RoleHolders = noRoles,
    ) {
        policy.requireInputAllowed(packageName, windowType, roleHolders)
    }

    private fun codeOf(
        packageName: String?,
        windowType: WindowType = WindowType.APPLICATION,
        roleHolders: RoleHolders = noRoles,
    ): String = assertThrows(PhoneAgentError::class.java) {
        require(packageName, windowType, roleHolders)
    }.code

    private fun messageOf(
        packageName: String?,
        windowType: WindowType = WindowType.APPLICATION,
        roleHolders: RoleHolders = noRoles,
    ): String = assertThrows(PhoneAgentError::class.java) {
        require(packageName, windowType, roleHolders)
    }.message.orEmpty()

    @Test
    fun `allows the test package`() {
        require(TEST_PACKAGE)
    }

    @Test
    fun `rejects other packages`() {
        val error = assertThrows(PhoneAgentError::class.java) {
            require("com.example.app")
        }

        assertEquals("package_not_allowed", error.code)
    }

    @Test
    fun `rejects system windows`() {
        val error = assertThrows(PhoneAgentError::class.java) {
            require("com.android.systemui")
        }

        assertEquals("system_window_denied", error.code)
    }

    @Test
    fun `rejects permission dialogs`() {
        val error = assertThrows(PhoneAgentError::class.java) {
            require("com.google.android.permissioncontroller")
        }

        assertEquals("system_window_denied", error.code)
    }

    @Test
    fun `rejects a missing package`() {
        val error = assertThrows(PhoneAgentError::class.java) {
            require(null)
        }

        assertEquals("no_window", error.code)
    }

    @Test
    fun `rejects the settings package`() {
        assertEquals("system_window_denied", codeOf("com.android.settings"))
    }

    @Test
    fun `rejects vendor settings variants`() {
        listOf(
            "com.miui.securitycenter",
            "com.coloros.settings",
            "com.oplus.settings",
            "com.samsung.android.settings",
            "com.huawei.systemmanager",
        ).forEach { packageName ->
            assertEquals(packageName, "system_window_denied", codeOf(packageName))
        }
    }

    @Test
    fun `rejects the default dialer and sms role holders`() {
        val holders = RoleHolders.Resolved(
            roleHolderSet(listOf("com.miui.dialer", "com.android.messaging", null, "")),
        )

        assertEquals("system_window_denied", codeOf("com.miui.dialer", roleHolders = holders))
        assertEquals(
            "system_window_denied",
            codeOf("com.android.messaging", roleHolders = holders),
        )
    }

    @Test
    fun `an unresolved role holder set blocks input`() {
        assertEquals(
            "system_window_denied",
            codeOf(TEST_PACKAGE, roleHolders = RoleHolders.Unavailable),
        )
    }

    @Test
    fun `rejects the kelivo host package but not the test package`() {
        assertEquals("system_window_denied", codeOf(KELIVO_PACKAGE))
        require(TEST_PACKAGE)
    }

    @Test
    fun `the test package is not matched by prefix or contains`() {
        require(TEST_PACKAGE)
        assertEquals("package_not_allowed", codeOf("com.psyche.kelivo.phoneagent.other"))
    }

    @Test
    fun `rejects non application window types`() {
        listOf(
            WindowType.INPUT_METHOD,
            WindowType.SYSTEM,
            WindowType.ACCESSIBILITY_OVERLAY,
            WindowType.SPLIT_SCREEN_DIVIDER,
            WindowType.UNKNOWN,
        ).forEach { type ->
            assertEquals(type.name, "system_window_denied", codeOf(TEST_PACKAGE, windowType = type))
        }
    }

    @Test
    fun `allows application windows in the build allow list`() {
        require(TEST_PACKAGE, windowType = WindowType.APPLICATION)
    }

    @Test
    fun `window type denial carries a fixed tag and no content`() {
        val ime = messageOf(TEST_PACKAGE, windowType = WindowType.INPUT_METHOD)
        val system = messageOf(TEST_PACKAGE, windowType = WindowType.SYSTEM)
        val overlay = messageOf(TEST_PACKAGE, windowType = WindowType.ACCESSIBILITY_OVERLAY)
        val unknown = messageOf(TEST_PACKAGE, windowType = WindowType.UNKNOWN)

        assertTrue(ime.contains("window_type_ime"))
        assertTrue(system.contains("window_type_system"))
        assertTrue(overlay.contains("window_type_overlay"))
        assertTrue(unknown.contains("window_type_unknown"))
        assertFalse(ime.contains(TEST_PACKAGE))
        assertFalse(system.contains(TEST_PACKAGE))
    }

    @Test
    fun `hard baseline takes precedence over the window type`() {
        val message = messageOf("com.android.settings", windowType = WindowType.SYSTEM)

        assertTrue(message.contains("hard_baseline"))
        assertFalse(message.contains("window_type_"))
    }

    @Test
    fun `window type is judged before the build allow list`() {
        val message = messageOf("com.example.app", windowType = WindowType.INPUT_METHOD)

        assertTrue(message.contains("window_type_ime"))
        assertFalse(message.contains("package_not_allowed"))
    }

    @Test
    fun `platform window type mapping falls back to unknown`() {
        assertEquals(WindowType.APPLICATION, WindowType.fromPlatformType(1))
        assertEquals(WindowType.INPUT_METHOD, WindowType.fromPlatformType(2))
        assertEquals(WindowType.SYSTEM, WindowType.fromPlatformType(3))
        assertEquals(WindowType.ACCESSIBILITY_OVERLAY, WindowType.fromPlatformType(4))
        assertEquals(WindowType.SPLIT_SCREEN_DIVIDER, WindowType.fromPlatformType(5))
        assertEquals(WindowType.UNKNOWN, WindowType.fromPlatformType(0))
        assertEquals(WindowType.UNKNOWN, WindowType.fromPlatformType(99))
        assertFalse(WindowType.UNKNOWN.allowsInput)
    }
}
