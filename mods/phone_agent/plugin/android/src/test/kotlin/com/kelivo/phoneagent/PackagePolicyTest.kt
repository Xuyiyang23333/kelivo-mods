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
            "com.xiaomi.misettings",
            "com.coloros.settings",
            "com.oplus.settings",
            "com.samsung.android.settings",
            "com.huawei.systemmanager",
        ).forEach { packageName ->
            assertEquals(packageName, "system_window_denied", codeOf(packageName))
        }
    }

    @Test
    fun `rejects vendor package installers`() {
        listOf(
            "com.android.packageinstaller",
            "com.google.android.packageinstaller",
            "com.miui.packageinstaller",
        ).forEach { packageName ->
            assertEquals(packageName, "system_window_denied", codeOf(packageName))
        }
    }

    @Test
    fun `rejects vendor permission controllers and certificate installer`() {
        listOf(
            "com.android.permissioncontroller",
            "com.google.android.permissioncontroller",
            "com.lbe.security.miui",
            "com.android.certinstaller",
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
        assertFalse(WindowType.UNKNOWN.allowsObservation)
    }

    private fun observe(packageName: String?, windowType: WindowType = WindowType.APPLICATION) {
        policy.requireObservable(packageName, windowType)
    }

    private fun observeCode(
        packageName: String?,
        windowType: WindowType = WindowType.APPLICATION,
    ): String = assertThrows(PhoneAgentError::class.java) {
        observe(packageName, windowType)
    }.code

    private fun observeMessage(
        packageName: String?,
        windowType: WindowType = WindowType.APPLICATION,
    ): String = assertThrows(PhoneAgentError::class.java) {
        observe(packageName, windowType)
    }.message.orEmpty()

    @Test
    fun `observation allows application windows`() {
        observe(TEST_PACKAGE)
    }

    @Test
    fun `observation allows input method windows`() {
        observe(TEST_PACKAGE, WindowType.INPUT_METHOD)
    }

    @Test
    fun `observation allows packages outside the input allow list`() {
        // 未批准应用也必须可观察，否则模型无法向用户解释为什么需要授权。
        observe("com.example.app")
        observe("com.example.app", WindowType.INPUT_METHOD)
    }

    @Test
    fun `observation does not report the input allow list`() {
        val message = assertThrows(PhoneAgentError::class.java) {
            observe("com.example.app", WindowType.SYSTEM)
        }.message.orEmpty()

        assertFalse(message.contains("package_not_allowed"))
        assertFalse(message.contains("permission_required"))
        assertFalse(message.contains(TEST_PACKAGE))
    }

    @Test
    fun `observation rejects non observable window types`() {
        listOf(
            WindowType.SYSTEM,
            WindowType.ACCESSIBILITY_OVERLAY,
            WindowType.SPLIT_SCREEN_DIVIDER,
            WindowType.UNKNOWN,
        ).forEach { type ->
            assertEquals(
                type.name,
                "system_window_denied",
                observeCode(TEST_PACKAGE, type),
            )
            assertFalse(type.name, type.allowsObservation)
        }
    }

    @Test
    fun `observation rejects a missing package`() {
        assertEquals("no_window", observeCode(null))
        assertEquals("no_window", observeCode(""))
        assertEquals("no_window", observeCode("   "))
    }

    @Test
    fun `observation applies the hard baseline`() {
        listOf(
            "com.android.systemui",
            "com.android.settings",
            "com.lbe.security.miui",
            "com.android.certinstaller",
        ).forEach { packageName ->
            assertEquals(packageName, "system_window_denied", observeCode(packageName))
            assertTrue(packageName, observeMessage(packageName).contains("hard_baseline"))
        }
    }

    @Test
    fun `observation rejects the kelivo host package but not the test package`() {
        assertEquals("system_window_denied", observeCode(KELIVO_PACKAGE))
        observe(TEST_PACKAGE)
    }

    @Test
    fun `hard baseline is judged before the observation window type`() {
        val message = observeMessage("com.android.settings", WindowType.SYSTEM)

        assertTrue(message.contains("hard_baseline"))
        assertFalse(message.contains("window_type_"))
    }

    @Test
    fun `observation window type denial carries a fixed tag without content`() {
        val system = observeMessage(TEST_PACKAGE, WindowType.SYSTEM)
        val overlay = observeMessage(TEST_PACKAGE, WindowType.ACCESSIBILITY_OVERLAY)
        val divider = observeMessage(TEST_PACKAGE, WindowType.SPLIT_SCREEN_DIVIDER)
        val unknown = observeMessage(TEST_PACKAGE, WindowType.UNKNOWN)

        assertTrue(system.contains("window_type_system"))
        assertTrue(overlay.contains("window_type_overlay"))
        assertTrue(divider.contains("window_type_split_divider"))
        assertTrue(unknown.contains("window_type_unknown"))
        assertFalse(system.contains(TEST_PACKAGE))
        assertFalse(unknown.contains(TEST_PACKAGE))
    }

    @Test
    fun `observation allow sets stay asymmetric with input`() {
        observe(TEST_PACKAGE, WindowType.INPUT_METHOD)
        assertEquals(
            "system_window_denied",
            codeOf(TEST_PACKAGE, windowType = WindowType.INPUT_METHOD),
        )
        assertTrue(WindowType.INPUT_METHOD.allowsObservation)
        assertFalse(WindowType.INPUT_METHOD.allowsInput)
        assertTrue(WindowType.APPLICATION.allowsObservation)
        assertTrue(WindowType.APPLICATION.allowsInput)
    }

    @Test
    fun `window snapshot matching is exact on window id`() {
        val snapshot = listOf(3739 to 3, 3750 to 1)

        assertEquals(WindowType.APPLICATION, WindowType.resolveFromSnapshot(3750, snapshot))
        assertEquals(WindowType.SYSTEM, WindowType.resolveFromSnapshot(3739, snapshot))
    }

    @Test
    fun `a lagging snapshot does not match a missing window`() {
        // M28 设备实测：rootInActiveWindow 属于 3750，而 windows 只列出 3739。
        // 同一快照匹配不到就必须是 UNKNOWN，不能退回用快照里唯一那个窗口的类型。
        val lagging = listOf(3739 to 3)

        assertEquals(WindowType.UNKNOWN, WindowType.resolveFromSnapshot(3750, lagging))
        assertEquals(WindowType.UNKNOWN, WindowType.resolveFromSnapshot(3750, emptyList()))
    }

    @Test
    fun `a refreshed snapshot resolves the window that was missing`() {
        val first = listOf(3739 to 3)
        val second = listOf(3739 to 3, 3750 to 1)

        assertEquals(WindowType.UNKNOWN, WindowType.resolveFromSnapshot(3750, first))
        assertEquals(WindowType.APPLICATION, WindowType.resolveFromSnapshot(3750, second))
    }

    @Test
    fun `snapshot matching ignores undefined platform types`() {
        assertEquals(
            WindowType.UNKNOWN,
            WindowType.resolveFromSnapshot(3750, listOf(3750 to 99)),
        )
    }

    @Test
    fun `observation still rejects a window whose id is missing from the snapshot`() {
        val lagging = listOf(3739 to 3)
        val resolved = WindowType.resolveFromSnapshot(3750, lagging)

        assertEquals("system_window_denied", observeCode(TEST_PACKAGE, resolved))
        assertTrue(observeMessage(TEST_PACKAGE, resolved).contains("window_type_unknown"))
    }
}
