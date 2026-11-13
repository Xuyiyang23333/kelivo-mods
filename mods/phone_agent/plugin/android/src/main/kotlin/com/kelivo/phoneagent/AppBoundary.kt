package com.kelivo.phoneagent

/**
 * 前台窗口类型。策略层只认本枚举：平台常量到枚举的映射集中在
 * [fromPlatformType]，其他取值一律归入 [UNKNOWN] 并默认拒绝（fail closed）。
 */
internal enum class WindowType {
    APPLICATION,
    INPUT_METHOD,
    SYSTEM,
    ACCESSIBILITY_OVERLAY,
    SPLIT_SCREEN_DIVIDER,
    UNKNOWN,
    ;

    val allowsInput: Boolean get() = this == APPLICATION

    /** 观察允许集比输入宽：输入法窗口必须能被看到，否则模型看不见正在输入的界面。 */
    val allowsObservation: Boolean
        get() = this == APPLICATION || this == INPUT_METHOD

    /** 拒绝消息中的固定标识；不含窗口标题、类名、包名或节点内容。输入与观察共用。 */
    val denialTag: String
        get() = when (this) {
            APPLICATION -> "window_type_application"
            INPUT_METHOD -> "window_type_ime"
            SYSTEM -> "window_type_system"
            ACCESSIBILITY_OVERLAY -> "window_type_overlay"
            SPLIT_SCREEN_DIVIDER -> "window_type_split_divider"
            UNKNOWN -> "window_type_unknown"
        }

    companion object {
        /** 与 `AccessibilityWindowInfo.TYPE_*` 的公开常量一致，避免策略层依赖 Android 运行时。 */
        fun fromPlatformType(value: Int): WindowType = when (value) {
            1 -> APPLICATION
            2 -> INPUT_METHOD
            3 -> SYSTEM
            4 -> ACCESSIBILITY_OVERLAY
            5 -> SPLIT_SCREEN_DIVIDER
            else -> UNKNOWN
        }

        /**
         * 在一次 `windows` 快照里按 id 精确匹配窗口类型。快照用平台整数类型表示，
         * 便于纯 JVM 覆盖“列表滞后”的情形：同一份快照匹配不到就是 [UNKNOWN]，
         * 由调用方决定是否重读，绝不按包名、顺序或位置猜。
         */
        fun resolveFromSnapshot(windowId: Int, entries: List<Pair<Int, Int>>): WindowType =
            entries.firstOrNull { it.first == windowId }
                ?.let { fromPlatformType(it.second) }
                ?: UNKNOWN
    }
}

/** 私有测试应用的包名，也是当前构建期输入白名单的唯一成员。 */
internal const val TEST_PACKAGE = "com.psyche.kelivo.phoneagent"

/**
 * 承载助手的 Kelivo 包（上游 applicationId）。私有测试构建会把它改成
 * [TEST_PACKAGE]，两者必须按精确包名区分：前缀或 contains 匹配会让测试应用自我阻断。
 */
internal const val KELIVO_PACKAGE = "com.psyche.kelivo"

/**
 * 静态硬基线：系统 UI、权限控制器、包安装器、证书安装器与设置（含常见厂商变体）。
 * 这些包是“用现有权限扩大权限”的入口，输入一律拒绝，用户不可覆盖。
 *
 * **漏写即等于该入口没有硬基线，且第 3 步白名单上线后会变成真实缺口。**
 * 厂商变体必须按真机 `cmd package resolve-activity` / `dumpsys package` 实测补全，
 * 不能只靠记忆枚举；当前集合是实测过的部分清单，不是完整清单。
 */
internal val HARD_BASELINE_PACKAGES: Set<String> = setOf(
    // 系统 UI 与权限控制器
    "com.android.systemui",
    "com.android.permissioncontroller",
    "com.google.android.permissioncontroller",
    // MIUI 权限授予界面（持有 GrantPermissionsActivity / ReviewPermissionsActivity）
    "com.lbe.security.miui",
    // 包安装器：AOSP / Google / MIUI（含 InstallStart 与 UninstallStart）
    "com.android.packageinstaller",
    "com.google.android.packageinstaller",
    "com.miui.packageinstaller",
    // 证书安装器（android.credentials.INSTALL）
    "com.android.certinstaller",
    // 设置与厂商变体
    "com.android.settings",
    "com.google.android.settings",
    "com.samsung.android.settings",
    "com.miui.securitycenter",
    "com.xiaomi.misettings",
    "com.coloros.settings",
    "com.coloros.safecenter",
    "com.oplus.settings",
    "com.oplus.safecenter",
    "com.vivo.settings",
    "com.bbk.settings",
    "com.huawei.systemmanager",
    "com.hihonor.systemmanager",
)

/**
 * 运行时角色解析结果。默认电话/短信持有者只能运行时查询；查询失败时不能
 * 假装“没有持有者”，按最严处理为 [Unavailable] 并拒绝输入。
 */
internal sealed class RoleHolders {
    data class Resolved(val packages: Set<String>) : RoleHolders()

    data object Unavailable : RoleHolders()
}

internal fun roleHolderSet(values: Iterable<String?>): Set<String> =
    values.filterNotNull().filter { it.isNotBlank() }.toSet()

/**
 * 应用边界策略。纯函数式判定：只读入参，不读 Android 状态、不持有状态，
 * 判定集中在这一处。首版不实现用户白名单，未命中构建期集合仍返回
 * `package_not_allowed`（构建期硬禁止），不与运行时白名单混用。
 *
 * 输入顺序固定：`no_window` → 静态硬基线 → 角色解析失败 → 角色持有者 →
 * 窗口类型 → 构建期白名单。调用方必须在每个输入动作前用**当前**窗口调用，
 * 不能缓存判定结果。
 *
 * 观察顺序固定：`no_window` → 静态硬基线 → 观察窗口类型。观察层不查询角色
 * （角色是输入边界，观察层依赖它会在角色解析失败时让所有设备的读树失败），
 * 也不判构建期白名单与用户白名单。
 */
internal class PackagePolicy(
    private val allowedPackages: Set<String> = setOf(TEST_PACKAGE),
    private val hardBaselinePackages: Set<String> = HARD_BASELINE_PACKAGES,
    private val kelivoPackage: String = KELIVO_PACKAGE,
) {
    fun requireInputAllowed(
        packageName: String?,
        windowType: WindowType,
        roleHolders: RoleHolders,
    ) {
        val foreground = requireForeground(
            packageName,
            "No foreground app is available. Ask the user to open the test app, then retry.",
        )
        requireNotHardBaseline(foreground)
        val holders = when (roleHolders) {
            is RoleHolders.Unavailable -> throw PhoneAgentError(
                "system_window_denied",
                "The default phone and SMS apps could not be resolved, so input is blocked (role_resolution_failed). Ask the user to retry after the system settles.",
            )
            is RoleHolders.Resolved -> roleHolders.packages
        }
        if (foreground in holders) {
            throw PhoneAgentError(
                "system_window_denied",
                "The foreground app is the default phone or SMS app ($foreground, role_holder). Ask the user to return to the test app, then retry.",
            )
        }
        if (!windowType.allowsInput) {
            throw PhoneAgentError(
                "system_window_denied",
                "Input into this window type is not allowed (${windowType.denialTag}). Ask the user to return to the app, then retry.",
            )
        }
        if (foreground !in allowedPackages) {
            throw PhoneAgentError(
                "package_not_allowed",
                "Input is limited to ${allowedPackages.joinToString()} in this build. The foreground app is $foreground.",
            )
        }
    }

    /**
     * 观察边界：读树与截图共用的入口判定。刻意不接收 [RoleHolders] 与白名单：
     * 未批准应用也必须在模型能看到之后才能向用户解释为什么需要授权。
     */
    fun requireObservable(
        packageName: String?,
        windowType: WindowType,
    ) {
        val foreground = requireForeground(
            packageName,
            "No accessible foreground window is available. Ask the user to open the app, then retry.",
        )
        requireNotHardBaseline(foreground)
        if (!windowType.allowsObservation) {
            throw PhoneAgentError(
                "system_window_denied",
                "This window type cannot be observed (${windowType.denialTag}). Ask the user to return to the app, then retry.",
            )
        }
    }

    private fun requireForeground(packageName: String?, message: String): String {
        if (packageName.isNullOrBlank()) {
            throw PhoneAgentError("no_window", message)
        }
        return packageName
    }

    private fun requireNotHardBaseline(packageName: String) {
        if (packageName == kelivoPackage || packageName in hardBaselinePackages) {
            throw PhoneAgentError(
                "system_window_denied",
                "The foreground window belongs to the system or a protected app ($packageName, hard_baseline). Ask the user to dismiss it and return to the test app, then retry.",
            )
        }
    }
}
