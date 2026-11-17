package com.kelivo.phoneagent

/**
 * 前台窗口类型。策略层只认本枚举：平台常量到枚举的映射集中在
 * [fromPlatformType]，其他取值一律归入 [UNKNOWN]。
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

    /**
     * 观察允许应用、输入法和未知类型（平台 windows 列表短暂滞后时不必误杀读树/截图），
     * 仅明确拦截系统窗口、无障碍叠加层和分屏分割线。
     */
    val allowsObservation: Boolean
        get() = this == APPLICATION || this == INPUT_METHOD || this == UNKNOWN

    /** 拒绝消息中的固定标识；不含窗口标题、类名、包名或节点内容。 */
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

        fun resolveFromSnapshot(windowId: Int, entries: List<Pair<Int, Int>>): WindowType =
            entries.firstOrNull { it.first == windowId }
                ?.let { fromPlatformType(it.second) }
                ?: UNKNOWN
    }
}

/** 私有测试应用的包名。 */
internal const val TEST_PACKAGE = "com.psyche.kelivo.phoneagent"

/**
 * 承载助手的 Kelivo 包（上游 applicationId）。私有测试构建会把它改成
 * [TEST_PACKAGE]，两者按精确包名区分。
 */
internal const val KELIVO_PACKAGE = "com.psyche.kelivo"

/**
 * 静态硬基线：系统 UI、权限控制器、包安装器、证书安装器与设置（含常见厂商变体）。
 * 防止助手自动进入系统权限/设置/安装页面改权限或操作敏感入口。
 */
internal val HARD_BASELINE_PACKAGES: Set<String> = setOf(
    "com.android.systemui",
    "com.android.permissioncontroller",
    "com.google.android.permissioncontroller",
    "com.lbe.security.miui",
    "com.android.packageinstaller",
    "com.google.android.packageinstaller",
    "com.miui.packageinstaller",
    "com.android.certinstaller",
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
 * 运行时角色解析结果。默认电话/短信持有者只能运行时查询；查询失败时按最严处理。
 */
internal sealed class RoleHolders {
    data class Resolved(val packages: Set<String>) : RoleHolders()

    data object Unavailable : RoleHolders()
}

internal fun roleHolderSet(values: Iterable<String?>): Set<String> =
    values.filterNotNull().filter { it.isNotBlank() }.toSet()

/**
 * 实用精简版应用边界策略（纯函数式判定）：
 * - 输入：`no_window` → 硬基线 → 角色解析失败 → 默认电话/短信持有者 → 窗口类型（仅 `APPLICATION`）
 * - 观察：`no_window` → 硬基线 → 窗口类型（拦截 `SYSTEM` / `ACCESSIBILITY_OVERLAY` / `SPLIT_SCREEN_DIVIDER`）
 * - 启动（`open_app`）：拦截硬基线与自身承载包
 *
 * 不对第三方普通应用加白名单审批门槛，任何已安装应用均可直接观察与控制。
 */
internal class PackagePolicy(
    private val hardBaselinePackages: Set<String> = HARD_BASELINE_PACKAGES,
    private val kelivoPackage: String = KELIVO_PACKAGE,
) {
    fun isHardBaseline(packageName: String): Boolean =
        packageName == kelivoPackage || packageName in hardBaselinePackages

    fun requireInputAllowed(
        packageName: String?,
        windowType: WindowType,
        roleHolders: RoleHolders,
    ) {
        val foreground = requireForeground(
            packageName,
            "No foreground app is available. Ask the user to open the app, then retry.",
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
                "The foreground app is the default phone or SMS app ($foreground, role_holder). Ask the user to return to the app, then retry.",
            )
        }
        if (!windowType.allowsInput) {
            throw PhoneAgentError(
                "system_window_denied",
                "Input into this window type is not allowed (${windowType.denialTag}). Ask the user to return to the app, then retry.",
            )
        }
    }

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

    fun requireLaunchAllowed(packageName: String) {
        requireNotHardBaseline(packageName)
    }

    private fun requireForeground(packageName: String?, message: String): String {
        if (packageName.isNullOrBlank()) {
            throw PhoneAgentError("no_window", message)
        }
        return packageName
    }

    private fun requireNotHardBaseline(packageName: String) {
        if (isHardBaseline(packageName)) {
            throw PhoneAgentError(
                "system_window_denied",
                "The foreground window belongs to the system or a protected app ($packageName, hard_baseline). Ask the user to dismiss it and return to the app, then retry.",
            )
        }
    }
}
