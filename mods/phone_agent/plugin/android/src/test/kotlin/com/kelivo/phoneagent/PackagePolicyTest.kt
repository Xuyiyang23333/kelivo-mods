package com.kelivo.phoneagent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class PackagePolicyTest {
    private val hashA = "a".repeat(64)
    private val hashB = "b".repeat(64)

    private val resolvable = mutableMapOf(
        "com.example.app" to listOf(hashA),
        "com.example.vendor" to listOf(hashA),
    )
    private val storage = InMemoryWhitelistStorage()
    private val approvals = AppApprovals(
        resolver = SigningResolver { packageName ->
            resolvable[packageName]?.let {
                SigningIdentity(packageName, SigningIdentity.normalizeSha256(it), "Example")
            }
        },
        store = WhitelistStore(storage),
    )

    private fun policy(
        denyPackages: Set<String> = emptySet(),
        preApprovedPackages: Set<String> = setOf(TEST_PACKAGE),
    ) = PackagePolicy(
        approvals = approvals,
        denyPackages = denyPackages,
        preApprovedPackages = preApprovedPackages,
    )

    private val policy = policy()
    private val noRoles = RoleHolders.Resolved(emptySet())

    private fun approve(packageName: String, vararg hashes: String) {
        resolvable[packageName] = if (hashes.isEmpty()) listOf(hashA) else hashes.toList()
        val outcome = approvals.approve(packageName, now = 1L, sourceAssistantId = null)
        assertTrue(packageName, outcome.approved)
    }

    private fun require(
        packageName: String?,
        windowType: WindowType = WindowType.APPLICATION,
        roleHolders: RoleHolders = noRoles,
        using: PackagePolicy = policy,
    ) {
        using.requireInputAllowed(packageName, windowType, roleHolders)
    }

    private fun codeOf(
        packageName: String?,
        windowType: WindowType = WindowType.APPLICATION,
        roleHolders: RoleHolders = noRoles,
        using: PackagePolicy = policy,
    ): String = assertThrows(PhoneAgentError::class.java) {
        require(packageName, windowType, roleHolders, using)
    }.code

    private fun messageOf(
        packageName: String?,
        windowType: WindowType = WindowType.APPLICATION,
        roleHolders: RoleHolders = noRoles,
        using: PackagePolicy = policy,
    ): String = assertThrows(PhoneAgentError::class.java) {
        require(packageName, windowType, roleHolders, using)
    }.message.orEmpty()

    private fun observe(
        packageName: String?,
        windowType: WindowType = WindowType.APPLICATION,
        using: PackagePolicy = policy,
    ) {
        using.requireObservable(packageName, windowType)
    }

    private fun observeCode(
        packageName: String?,
        windowType: WindowType = WindowType.APPLICATION,
        using: PackagePolicy = policy,
    ): String = assertThrows(PhoneAgentError::class.java) {
        observe(packageName, windowType, using)
    }.code

    private fun observeMessage(
        packageName: String?,
        windowType: WindowType = WindowType.APPLICATION,
        using: PackagePolicy = policy,
    ): String = assertThrows(PhoneAgentError::class.java) {
        observe(packageName, windowType, using)
    }.message.orEmpty()

    private fun detailsOf(
        packageName: String,
        observation: Boolean,
        using: PackagePolicy = policy,
    ): Map<String, Any?> = assertThrows(PhoneAgentError::class.java) {
        if (observation) observe(packageName, using = using) else require(packageName, using = using)
    }.details.orEmpty()

    @Test
    fun `permission required carries the structured app identity for input`() {
        val details = detailsOf("com.example.app", observation = false)

        assertEquals("com.example.app", details["package_name"])
        assertEquals("aaaaaaaa", details["signing_prefix"])
        assertEquals("Example", details["display_name"])
        assertEquals(true, details["signing_available"])
        assertEquals(false, details["observation"])
        // 结构化载荷不得夹带节点文本、窗口标题或界面内容字段。
        assertEquals(
            setOf(
                "package_name",
                "signing_prefix",
                "display_name",
                "signing_available",
                "observation",
            ),
            details.keys,
        )
    }

    @Test
    fun `permission required carries the structured app identity for observation`() {
        val details = detailsOf("com.example.app", observation = true)

        assertEquals("com.example.app", details["package_name"])
        assertEquals("aaaaaaaa", details["signing_prefix"])
        assertEquals(true, details["observation"])
    }

    @Test
    fun `permission required marks an unavailable signature without a hash`() {
        resolvable.remove("com.example.app")

        val details = detailsOf("com.example.app", observation = false)

        assertEquals("com.example.app", details["package_name"])
        assertNull(details["signing_prefix"])
        assertEquals(false, details["signing_available"])
    }

    @Test
    fun `a hard baseline denial carries no approval identity`() {
        val error = assertThrows(PhoneAgentError::class.java) {
            observe("com.android.systemui")
        }

        assertEquals("system_window_denied", error.code)
        assertNull(error.details)
    }

    @Test
    fun `the build pre approved test package needs no user approval`() {
        require(TEST_PACKAGE)
        observe(TEST_PACKAGE)
        assertTrue(approvals.approvedApps().isEmpty())
    }

    @Test
    fun `an unapproved third party app requires approval for input`() {
        assertEquals("permission_required", codeOf("com.example.app"))
    }

    @Test
    fun `an approved third party app accepts input`() {
        approve("com.example.app")

        require("com.example.app")
    }

    @Test
    fun `a signing change turns an approved app back into permission required`() {
        approve("com.example.app")
        require("com.example.app")

        resolvable["com.example.app"] = listOf(hashB)

        val message = messageOf("com.example.app")
        assertEquals("permission_required", codeOf("com.example.app"))
        assertTrue(message.contains("bbbbbbbb"))
        assertFalse(message.contains(hashA))
    }

    @Test
    fun `an unreadable signing certificate fails closed with a fixed tag`() {
        approve("com.example.app")
        resolvable.remove("com.example.app")

        val message = messageOf("com.example.app")

        assertEquals("permission_required", codeOf("com.example.app"))
        assertTrue(message.contains("signing_unavailable"))
        assertFalse(message.contains("aaaaaaaa"))
    }

    @Test
    fun `revoking blocks the next input immediately`() {
        approve("com.example.app")
        require("com.example.app")

        approvals.revoke("com.example.app")

        assertEquals("permission_required", codeOf("com.example.app"))
    }

    @Test
    fun `the permission required message carries only identity and the next step`() {
        val message = messageOf("com.example.app")

        assertTrue(message.contains("com.example.app"))
        assertTrue(message.contains("aaaaaaaa"))
        assertTrue(message.contains("Example"))
        assertTrue(message.contains("Do not retry the same call repeatedly"))
    }

    @Test
    fun `the observation permission message states nothing was captured`() {
        val message = observeMessage("com.example.app")

        assertTrue(message.contains("com.example.app"))
        assertTrue(message.contains("aaaaaaaa"))
        assertTrue(message.contains("No screenshot or UI text was captured or sent"))
        assertTrue(message.contains("Do not retry the same call repeatedly"))
    }

    @Test
    fun `input and observation permission messages differ`() {
        val input = messageOf("com.example.app")
        val observation = observeMessage("com.example.app")

        assertTrue(input.contains("was not executed and is not queued"))
        assertFalse(observation.contains("was not executed and is not queued"))
        assertTrue(observation.contains("re-observe before acting"))
    }

    @Test
    fun `rejects system windows`() {
        assertEquals("system_window_denied", codeOf("com.android.systemui"))
    }

    @Test
    fun `rejects permission dialogs`() {
        assertEquals("system_window_denied", codeOf("com.google.android.permissioncontroller"))
    }

    @Test
    fun `rejects a missing package`() {
        assertEquals("no_window", codeOf(null))
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
        assertEquals("permission_required", codeOf("com.psyche.kelivo.phoneagent.other"))
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
    fun `hard baseline takes precedence over the user whitelist`() {
        approve("com.android.settings")

        assertEquals("system_window_denied", codeOf("com.android.settings"))
        assertTrue(messageOf("com.android.settings").contains("hard_baseline"))
        assertEquals("system_window_denied", observeCode("com.android.settings"))
    }

    @Test
    fun `window type is judged before the build deny list`() {
        val denied = policy(denyPackages = setOf("com.example.app"))
        val message = messageOf("com.example.app", windowType = WindowType.INPUT_METHOD, using = denied)

        assertTrue(message.contains("window_type_ime"))
        assertFalse(message.contains("package_not_allowed"))
    }

    @Test
    fun `the build deny list reports package not allowed for input`() {
        val denied = policy(denyPackages = setOf("com.example.app"))

        assertEquals("package_not_allowed", codeOf("com.example.app", using = denied))
        assertTrue(messageOf("com.example.app", using = denied).contains("build_denied"))
    }

    @Test
    fun `the build deny list reports package not allowed for observation`() {
        val denied = policy(denyPackages = setOf("com.example.app"))

        assertEquals("package_not_allowed", observeCode("com.example.app", using = denied))
    }

    @Test
    fun `the build deny list is judged before the user whitelist`() {
        approve("com.example.app")
        val denied = policy(denyPackages = setOf("com.example.app"))

        assertEquals("package_not_allowed", codeOf("com.example.app", using = denied))
        assertEquals("package_not_allowed", observeCode("com.example.app", using = denied))
    }

    @Test
    fun `an app outside the deny list requires approval instead of package not allowed`() {
        val denied = policy(denyPackages = setOf("com.example.blocked"))

        assertEquals("permission_required", codeOf("com.example.app", using = denied))
        assertEquals("permission_required", observeCode("com.example.app", using = denied))
    }

    @Test
    fun `approved apps still pass the build deny list check when unlisted`() {
        approve("com.example.app")

        require("com.example.app")
        observe("com.example.app")
    }

    @Test
    fun `unapproved packages are not observable`() {
        assertEquals("permission_required", observeCode("com.example.app"))
        assertTrue(observeMessage("com.example.app").contains("No screenshot or UI text"))
    }

    @Test
    fun `approved packages are observable`() {
        approve("com.example.app")

        observe("com.example.app")
        observe("com.example.app", WindowType.INPUT_METHOD)
    }

    @Test
    fun `observation does not apply the input role holders`() {
        assertEquals(
            "permission_required",
            observeCode("com.miui.dialer", WindowType.APPLICATION),
        )
        assertEquals(
            "system_window_denied",
            codeOf(
                "com.miui.dialer",
                roleHolders = RoleHolders.Resolved(setOf("com.miui.dialer")),
            ),
        )
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
    fun `the cross uid fixture is pre approved only in debuggable builds`() {
        val debugPolicy = policy(preApprovedPackages = buildPreApprovedPackages(debuggable = true))
        val releasePolicy = policy(preApprovedPackages = buildPreApprovedPackages(debuggable = false))

        require(SECURE_FIXTURE_PACKAGE, using = debugPolicy)
        observe(SECURE_FIXTURE_PACKAGE, using = debugPolicy)
        assertEquals(
            "permission_required",
            codeOf(SECURE_FIXTURE_PACKAGE, using = releasePolicy),
        )
        assertEquals(
            "permission_required",
            observeCode(SECURE_FIXTURE_PACKAGE, using = releasePolicy),
        )
    }

    @Test
    fun `pre approved entries never appear in the user whitelist`() {
        val debugPolicy = policy(preApprovedPackages = buildPreApprovedPackages(debuggable = true))

        require(SECURE_FIXTURE_PACKAGE, using = debugPolicy)

        assertTrue(approvals.approvedApps().isEmpty())
    }

    @Test
    fun `pre approvals do not make other apps reachable`() {
        val debugPolicy = policy(preApprovedPackages = buildPreApprovedPackages(debuggable = true))

        assertEquals("permission_required", codeOf("com.example.app", using = debugPolicy))
        assertEquals("permission_required", observeCode("com.example.other", using = debugPolicy))
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

    @Test
    fun `a window that appears later resolves on a subsequent snapshot`() {
        // M28 设备证据：rootWin=5902 时 windows 只有 (5890, 3)；窗口列表补齐后
        // 同一 windowId 才命中。这条用例固定“只有真的出现才通过”，不靠猜。
        val before = listOf(5890 to 3)
        val after = listOf(5890 to 3, 5902 to 1)

        assertEquals(WindowType.UNKNOWN, WindowType.resolveFromSnapshot(5902, before))
        assertEquals(WindowType.APPLICATION, WindowType.resolveFromSnapshot(5902, after))
    }

    @Test
    fun `a null node window still requires the list to match exactly`() {
        // root.window 为 null 时不能退化成“accept whatever the list holds”：
        // 列表里只有别的窗口时仍然拒绝。
        val resolved = WindowType.resolveFromSnapshot(5902, listOf(5890 to 3))

        assertEquals(WindowType.UNKNOWN, resolved)
        assertEquals("system_window_denied", observeCode(TEST_PACKAGE, resolved))
    }
}
