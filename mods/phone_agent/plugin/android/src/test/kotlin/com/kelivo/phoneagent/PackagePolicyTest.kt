package com.kelivo.phoneagent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class PackagePolicyTest {
    private val policy = PackagePolicy()
    private val noRoles = RoleHolders.Resolved(emptySet())

    private fun requireInput(
        packageName: String?,
        windowType: WindowType = WindowType.APPLICATION,
        roleHolders: RoleHolders = noRoles,
    ) {
        policy.requireInputAllowed(packageName, windowType, roleHolders)
    }

    private fun inputError(
        packageName: String?,
        windowType: WindowType = WindowType.APPLICATION,
        roleHolders: RoleHolders = noRoles,
    ): PhoneAgentError = assertThrows(PhoneAgentError::class.java) {
        requireInput(packageName, windowType, roleHolders)
    }

    private fun observeError(
        packageName: String?,
        windowType: WindowType = WindowType.APPLICATION,
    ): PhoneAgentError = assertThrows(PhoneAgentError::class.java) {
        policy.requireObservable(packageName, windowType)
    }

    @Test
    fun `any normal third party app is allowed for input, observation and launch`() {
        requireInput("com.example.app")
        requireInput(TEST_PACKAGE)
        requireInput("com.google.android.apps.nexuslauncher")
        policy.requireObservable("com.example.app", WindowType.APPLICATION)
        policy.requireObservable("com.example.app", WindowType.INPUT_METHOD)
        policy.requireObservable("com.example.app", WindowType.UNKNOWN)
        policy.requireLaunchAllowed("com.example.app")
    }

    @Test
    fun `missing foreground package returns no_window`() {
        assertEquals("no_window", inputError(null).code)
        assertEquals("no_window", inputError("   ").code)
        assertEquals("no_window", observeError(null).code)
        assertEquals("no_window", observeError("").code)
    }

    @Test
    fun `hard baseline packages and kelivo host are denied on input, observe and launch`() {
        val blocked = listOf(
            KELIVO_PACKAGE,
            "com.android.systemui",
            "com.android.permissioncontroller",
            "com.google.android.permissioncontroller",
            "com.lbe.security.miui",
            "com.android.packageinstaller",
            "com.google.android.packageinstaller",
            "com.miui.packageinstaller",
            "com.android.certinstaller",
            "com.android.settings",
            "com.xiaomi.misettings",
            "com.miui.securitycenter",
        )
        for (pkg in blocked) {
            val inputErr = inputError(pkg)
            assertEquals(pkg, "system_window_denied", inputErr.code)
            assertTrue(pkg, inputErr.message.contains("hard_baseline"))

            val obsErr = observeError(pkg)
            assertEquals(pkg, "system_window_denied", obsErr.code)
            assertTrue(pkg, obsErr.message.contains("hard_baseline"))

            val launchErr = assertThrows(PhoneAgentError::class.java) {
                policy.requireLaunchAllowed(pkg)
            }
            assertEquals(pkg, "system_window_denied", launchErr.code)
        }
    }

    @Test
    fun `role holders and unavailable role resolution deny input`() {
        val unavailable = inputError("com.example.app", roleHolders = RoleHolders.Unavailable)
        assertEquals("system_window_denied", unavailable.code)
        assertTrue(unavailable.message.contains("role_resolution_failed"))

        val dialer = inputError(
            "com.google.android.dialer",
            roleHolders = RoleHolders.Resolved(setOf("com.google.android.dialer")),
        )
        assertEquals("system_window_denied", dialer.code)
        assertTrue(dialer.message.contains("role_holder"))
    }

    @Test
    fun `input only allows APPLICATION window type`() {
        val rejectedTypes = listOf(
            WindowType.INPUT_METHOD,
            WindowType.SYSTEM,
            WindowType.ACCESSIBILITY_OVERLAY,
            WindowType.SPLIT_SCREEN_DIVIDER,
            WindowType.UNKNOWN,
        )
        for (type in rejectedTypes) {
            val err = inputError("com.example.app", windowType = type)
            assertEquals(type.name, "system_window_denied", err.code)
            assertTrue(type.name, err.message.contains(type.denialTag))
        }
    }

    @Test
    fun `observation denies explicit system, overlay and split divider windows`() {
        val rejectedTypes = listOf(
            WindowType.SYSTEM,
            WindowType.ACCESSIBILITY_OVERLAY,
            WindowType.SPLIT_SCREEN_DIVIDER,
        )
        for (type in rejectedTypes) {
            val err = observeError("com.example.app", windowType = type)
            assertEquals(type.name, "system_window_denied", err.code)
            assertTrue(type.name, err.message.contains(type.denialTag))
        }
    }

    @Test
    fun `hard baseline takes precedence over window type`() {
        val err = inputError("com.android.settings", windowType = WindowType.SYSTEM)
        assertEquals("system_window_denied", err.code)
        assertTrue(err.message.contains("hard_baseline"))
    }

    @Test
    fun `platform window constants map and resolve from snapshot`() {
        assertEquals(WindowType.APPLICATION, WindowType.fromPlatformType(1))
        assertEquals(WindowType.INPUT_METHOD, WindowType.fromPlatformType(2))
        assertEquals(WindowType.SYSTEM, WindowType.fromPlatformType(3))
        assertEquals(WindowType.ACCESSIBILITY_OVERLAY, WindowType.fromPlatformType(4))
        assertEquals(WindowType.SPLIT_SCREEN_DIVIDER, WindowType.fromPlatformType(5))
        assertEquals(WindowType.UNKNOWN, WindowType.fromPlatformType(0))
        assertEquals(WindowType.UNKNOWN, WindowType.fromPlatformType(99))

        assertEquals(
            WindowType.APPLICATION,
            WindowType.resolveFromSnapshot(10, listOf(9 to 3, 10 to 1)),
        )
        assertEquals(
            WindowType.UNKNOWN,
            WindowType.resolveFromSnapshot(11, listOf(9 to 3, 10 to 1)),
        )
    }
}
