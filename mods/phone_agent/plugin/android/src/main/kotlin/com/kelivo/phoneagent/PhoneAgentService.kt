package com.kelivo.phoneagent

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.KeyguardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Point
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.provider.Telephony
import android.telecom.TelecomManager
import android.view.Display
import android.view.Surface
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityManager
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import java.util.concurrent.Executors
import java.util.concurrent.RejectedExecutionException
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * 独立无障碍服务。所有观测、句柄和输入都在单 worker 上串行执行；
 * 手势和截图异步完成，期间后续请求返回 `busy`。
 */
class PhoneAgentService : AccessibilityService() {
    companion object {
        private const val QUEUE_TIMEOUT_MS = 15_000L

        /**
         * 窗口类型解析的有界重试预算。只用于短时等待系统 windows 列表同步，
         * 避免长时间阻塞 worker。
         */
        private const val WINDOW_TYPE_BUDGET_MS = 300L
        private const val WINDOW_TYPE_RETRY_DELAY_MS = 40L

        @Volatile
        private var connected: PhoneAgentService? = null

        fun status(context: Context): Map<String, Any> {
            val manager = context.getSystemService(AccessibilityManager::class.java)
            val component = ComponentName(context, PhoneAgentService::class.java)
            val enabled = manager
                ?.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
                ?.any {
                    ComponentName(
                        it.resolveInfo.serviceInfo.packageName,
                        it.resolveInfo.serviceInfo.name,
                    ) == component
                } == true
            return linkedMapOf(
                "supported" to (Build.VERSION.SDK_INT >= 30),
                "enabled" to enabled,
                "connected" to (enabled && connected != null),
                "androidSdkInt" to Build.VERSION.SDK_INT,
            )
        }

        internal fun dispatch(
            method: String,
            args: Map<String, Any?>?,
            complete: (Any?, PhoneAgentError?) -> Unit,
        ) {
            val service = connected
            if (service == null) {
                complete(
                    null,
                    PhoneAgentError(
                        "service_unavailable",
                        "Enable the Kelivo Phone Agent accessibility service in Android Accessibility settings, then retry. If it is already enabled, turn it off and on again.",
                    ),
                )
                return
            }
            service.execute(method, args, complete)
        }
    }

    private val worker = Executors.newSingleThreadExecutor()
    private val screenshotWorker = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val generation = AtomicLong()
    private val requests = mutableSetOf<(Any?, PhoneAgentError?) -> Unit>()

    @Volatile
    private var destroyed = false

    @Volatile
    private var currentEpoch = 0L

    @Volatile
    private var pendingScreenshot: ((Any?, PhoneAgentError?) -> Unit)? = null

    private lateinit var registry: ObservationRegistry
    private lateinit var executor: NodeActionExecutor
    private lateinit var screenshots: ScreenshotCapture
    private lateinit var treeBudget: ActionBudget
    private lateinit var overlay: PhoneAgentOverlay

    /** 应用边界策略（硬基线 + 窗口类型）。 */
    private lateinit var policy: PackagePolicy

    /**
     * 最近一次 `TYPE_WINDOWS_CHANGED` 事件的时间戳（`SystemClock.elapsedRealtime`）。
     * 窗口类型解析失败时用它判断“平台是否刚刚报告过窗口变化”，从而在新事件到达后
     * 立刻重读，而不是在固定退避里空转。
     */
    private val lastWindowsChanged = AtomicLong(0)

    override fun onCreate() {
        super.onCreate()
        policy = PackagePolicy()
        registry = ObservationRegistry(
            now = { SystemClock.elapsedRealtime() },
            rootProvider = { rootInActiveWindow?.let(::AndroidPhoneNode) },
        )
        treeBudget = ActionBudget(
            limit = 60,
            windowMillis = 60_000,
            now = { SystemClock.elapsedRealtime() },
        )
        overlay = PhoneAgentOverlay(service = this, screenSize = ::screenSize)
        executor = NodeActionExecutor(
            service = this,
            registry = registry,
            policy = policy,
            beforeAction = {
                ensureUnlocked()
                ensureActive()
            },
            roleHolders = ::resolveRoleHolders,
            visual = { event, isActive, generation ->
                val guard = visualGuard()
                overlay.show(event, { guard() && isActive() }, generation)
            },
            visualGeneration = { overlay.currentGeneration() },
            clearVisual = { overlay.clear() },
        )
        screenshots = ScreenshotCapture(
            service = this,
            throttle = ScreenshotThrottle(now = { SystemClock.elapsedRealtime() }),
            worker = screenshotWorker,
            beforeCapture = {
                ensureUnlocked()
                ensureActive()
            },
            gate = overlay,
            currentWindow = ::currentWindow,
        )
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        destroyed = false
        connected = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // 观测按需读取，不保留窗口内容；只在其他应用窗口状态变化时清理残留可视化，
        // 避免旧动作图形画到权限窗口或新前台应用上。自身 overlay 不触发清理。
        val change = event ?: return
        if (change.eventType == AccessibilityEvent.TYPE_WINDOWS_CHANGED) {
            lastWindowsChanged.set(SystemClock.elapsedRealtime())
            return
        }
        if (change.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val foreground = change.packageName?.toString() ?: return
        if (foreground != packageName && this::overlay.isInitialized) {
            overlay.clear()
        }
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (this::overlay.isInitialized) overlay.clear()
    }

    override fun onInterrupt() {
        interruptPending()
    }

    override fun onUnbind(intent: Intent?): Boolean {
        if (connected === this) connected = null
        destroyed = true
        interruptPending()
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        if (connected === this) connected = null
        destroyed = true
        interruptPending()
        if (this::overlay.isInitialized) overlay.shutdown()
        worker.shutdown()
        screenshotWorker.shutdown()
        super.onDestroy()
    }

    private fun execute(
        method: String,
        args: Map<String, Any?>?,
        complete: (Any?, PhoneAgentError?) -> Unit,
    ) {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            handler.post { execute(method, args, complete) }
            return
        }
        if (destroyed) {
            complete(null, serviceUnavailable())
            return
        }
        val epoch = generation.get()
        val enqueuedAt = SystemClock.elapsedRealtime()
        val finished = AtomicBoolean(false)
        lateinit var reply: (Any?, PhoneAgentError?) -> Unit
        reply = { value, error ->
            val deliver = {
                if (finished.compareAndSet(false, true)) {
                    requests.remove(reply)
                    if (epoch == generation.get() && !destroyed) {
                        complete(value, error)
                    } else {
                        complete(null, interrupted())
                    }
                }
            }
            if (Looper.myLooper() == Looper.getMainLooper()) {
                deliver()
            } else {
                handler.post { deliver() }
            }
        }
        requests.add(reply)
        try {
            worker.execute {
                if (SystemClock.elapsedRealtime() - enqueuedAt > QUEUE_TIMEOUT_MS) {
                    reply(
                        null,
                        PhoneAgentError(
                            "timeout",
                            "The request waited too long behind another action and was not executed. Retry when the phone is idle.",
                        ),
                    )
                } else {
                    currentEpoch = epoch
                    if (epoch != generation.get() || destroyed) {
                        reply(null, interrupted())
                    } else {
                        dispatchOnWorker(method, args, reply)
                    }
                }
            }
        } catch (error: RejectedExecutionException) {
            reply(null, serviceUnavailable())
        }
    }

    private fun dispatchOnWorker(
        method: String,
        args: Map<String, Any?>?,
        reply: (Any?, PhoneAgentError?) -> Unit,
    ) {
        try {
            ensureActive()
            if (executor.isBusy() || screenshots.isBusy()) {
                reply(
                    null,
                    PhoneAgentError(
                        "busy",
                        "Another phone agent action is still running. Wait for its result before the next call.",
                    ),
                )
                return
            }
            ensureUnlocked()
            when (method) {
                "readTree" -> {
                    val result = readTree(args)
                    reply(result, null)
                }
                "screenshot" -> captureScreenshot(reply)
                "input" -> input(args, reply)
                "clearScreenshot" -> {
                    registry.clearScreenshot()
                    reply(linkedMapOf("cleared" to true), null)
                }
                else -> reply(
                    null,
                    PhoneAgentError(
                        "invalid_argument",
                        "Unknown phone agent method: $method",
                    ),
                )
            }
        } catch (error: PhoneAgentError) {
            reply(null, error)
        } catch (error: Exception) {
            registry.invalidateAll()
            reply(
                null,
                PhoneAgentError(
                    "internal_error",
                    error.message ?: "The phone agent failed.",
                ),
            )
        }
    }

    private fun readTree(args: Map<String, Any?>?): Map<String, Any?> {
        val offset = PhoneAgentArgs.int(args, "offset", 0, 0, 1_000_000)
        val maxNodes = PhoneAgentArgs.int(args, "max_nodes", 120, 1, 200)
        val interactiveOnly = PhoneAgentArgs.bool(args, "interactive_only", false)
        val root = rootInActiveWindow ?: throw noAccessibleWindowError()
        val current = windowState(root)
        if (offset == 0) {
            try {
                policy.requireObservable(current.packageName, current.windowType)
            } catch (error: PhoneAgentError) {
                root.recycle()
                throw error
            }
            if (!treeBudget.tryConsume()) {
                root.recycle()
                throw PhoneAgentError(
                    "budget_exceeded",
                    "Too many tree reads in the last minute. Wait before continuing.",
                )
            }
            overlay.observe(visualGuard())
            val observation = NodeTreeReader().read(
                root = AndroidPhoneNode(root),
                windowId = current.windowId,
                packageName = current.packageName,
                screenWidth = current.width,
                screenHeight = current.height,
                rotation = current.rotation,
                windowType = current.windowType,
                createdAt = SystemClock.elapsedRealtime(),
                interactiveOnly = interactiveOnly,
            )
            registry.beginTree(observation)
        } else {
            try {
                return PhoneAgentResult.treePage(
                    registry.page(offset, maxNodes, current),
                )
            } finally {
                root.recycle()
            }
        }
        return PhoneAgentResult.treePage(registry.page(0, maxNodes, current))
    }

    private fun captureScreenshot(reply: (Any?, PhoneAgentError?) -> Unit) {
        if (pendingScreenshot != null || screenshots.isBusy()) {
            reply(
                null,
                PhoneAgentError(
                    "busy",
                    "A screenshot is already running. Wait for its result before the next call.",
                ),
            )
            return
        }
        val root = rootInActiveWindow ?: throw noAccessibleWindowError()
        val current = try {
            windowState(root)
        } finally {
            root.recycle()
        }
        policy.requireObservable(current.packageName, current.windowType)
        val passwordBounds = collectPasswordBounds(current)
        val recentTaps = registry.peekRecentTaps(current)
        pendingScreenshot = reply
        screenshots.capture(current, passwordBounds, recentTaps) { outcome ->
            handler.post {
                pendingScreenshot = null
                when (outcome) {
                    is ScreenshotOutcome.Success -> {
                        val shot = outcome.screenshot
                        registry.recordScreenshot(
                            ScreenshotObservation(
                                imageWidth = shot.imageWidth,
                                imageHeight = shot.imageHeight,
                                screenWidth = shot.screenWidth,
                                screenHeight = shot.screenHeight,
                                windowId = shot.windowId,
                                packageName = shot.packageName,
                                rotation = shot.rotation,
                                windowType = shot.windowType,
                                createdAt = SystemClock.elapsedRealtime(),
                            ),
                        )
                        registry.clearRecentTaps()
                        reply(PhoneAgentResult.screenshot(shot), null)
                        overlay.captured(visualGuard())
                    }
                    is ScreenshotOutcome.Failure -> reply(null, outcome.error)
                }
            }
        }
    }

    private fun input(
        args: Map<String, Any?>?,
        reply: (Any?, PhoneAgentError?) -> Unit,
    ) {
        val action = PhoneAgentArgs.string(args, "action")
        if (action == "list_apps") {
            reply(listLaunchableApps(), null)
            return
        }
        if (action == "wait") {
            val delayMs = PhoneAgentArgs.optionalLong(args, "duration_ms", 100, 5000) ?: 1_000L
            val deadline = SystemClock.elapsedRealtime() + delayMs
            while (true) {
                ensureActive()
                val remaining = deadline - SystemClock.elapsedRealtime()
                if (remaining <= 0) break
                try {
                    Thread.sleep(minOf(50L, remaining))
                } catch (error: InterruptedException) {
                    Thread.currentThread().interrupt()
                    throw interrupted()
                }
            }
            reply(PhoneAgentResult.waitSuccess(delayMs), null)
            return
        }
        if (action == "open_app") {
            val targetPackage = PhoneAgentArgs.string(args, "package_name").trim()
            if (targetPackage == packageName) {
                throw PhoneAgentError(
                    "system_window_denied",
                    "Cannot launch the host app itself ($targetPackage).",
                )
            }
            policy.requireLaunchAllowed(targetPackage)
            val intent = packageManager.getLaunchIntentForPackage(targetPackage)
                ?: throw PhoneAgentError(
                    "app_not_found",
                    "No launchable app found for $targetPackage. Call list_apps to find an installed package name.",
                )
            registry.invalidateAll()
            if (this::overlay.isInitialized) overlay.clear()
            ensureActive()
            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            reply(PhoneAgentResult.openAppSuccess(targetPackage), null)
            return
        }
        val request = when (action) {
            "tap", "long_press" -> {
                val nodeId = PhoneAgentArgs.optionalString(args, "node_id")
                if (nodeId != null) {
                    InputRequest.NodeActionRequest(
                        action = if (action == "tap") NodeAction.CLICK else NodeAction.LONG_CLICK,
                        nodeId = nodeId,
                    )
                } else {
                    InputRequest.GestureRequest(
                        action = if (action == "tap") GestureAction.TAP else GestureAction.LONG_PRESS,
                        x = PhoneAgentArgs.normalized(args, "x"),
                        y = PhoneAgentArgs.normalized(args, "y"),
                        durationMs = PhoneAgentArgs.optionalLong(args, "duration_ms", 50, 2000),
                    )
                }
            }
            "set_text" -> InputRequest.NodeActionRequest(
                action = NodeAction.SET_TEXT,
                nodeId = PhoneAgentArgs.string(args, "node_id"),
                text = PhoneAgentArgs.text(args, "text"),
            )
            "scroll" -> InputRequest.NodeActionRequest(
                action = NodeAction.fromScrollDirection(
                    PhoneAgentArgs.string(args, "direction"),
                ),
                nodeId = PhoneAgentArgs.string(args, "node_id"),
            )
            "swipe" -> InputRequest.GestureRequest(
                action = GestureAction.SWIPE,
                x = PhoneAgentArgs.normalized(args, "x"),
                y = PhoneAgentArgs.normalized(args, "y"),
                endX = PhoneAgentArgs.normalized(args, "end_x"),
                endY = PhoneAgentArgs.normalized(args, "end_y"),
                durationMs = PhoneAgentArgs.optionalLong(args, "duration_ms", 50, 2000),
            )
            "back", "home", "recents" -> InputRequest.SystemRequest(
                SystemAction.fromWire(action),
            )
            else -> throw PhoneAgentError(
                "invalid_argument",
                "Unknown input action: $action. Use tap, long_press, set_text, scroll, swipe, back, home, recents, list_apps, open_app or wait.",
            )
        }
        val current = currentWindow() ?: throw noAccessibleWindowError()
        executor.execute(request, current) { outcome ->
            when (outcome) {
                is InputOutcome.Success -> {
                    if (request is InputRequest.GestureRequest &&
                        (request.action == GestureAction.TAP ||
                            request.action == GestureAction.LONG_PRESS)
                    ) {
                        registry.recordCoordinateTap(
                            action = request.action.wireName,
                            x = request.x,
                            y = request.y,
                            window = current,
                        )
                    }
                    reply(
                        PhoneAgentResult.inputSuccess(outcome.action, outcome.message),
                        null,
                    )
                }
                is InputOutcome.Failure -> reply(null, outcome.error)
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun listLaunchableApps(): Map<String, Any?> {
        val query = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val apps = packageManager.queryIntentActivities(query, 0)
            .asSequence()
            .filter { info ->
                val pkg = info.activityInfo?.packageName
                !pkg.isNullOrBlank() && pkg != packageName && !policy.isHardBaseline(pkg)
            }
            .distinctBy { it.activityInfo.packageName }
            .map { info ->
                val label = runCatching { info.loadLabel(packageManager)?.toString() }
                    .getOrNull()
                    ?.takeIf { it.isNotBlank() }
                    ?: info.activityInfo.packageName
                linkedMapOf(
                    "name" to label,
                    "package_name" to info.activityInfo.packageName,
                )
            }
            .sortedBy { it["name"]?.lowercase().orEmpty() }
            .toList()
        return PhoneAgentResult.appsList(apps)
    }

    private fun currentWindow(): WindowState? {
        val root = rootInActiveWindow ?: return null
        return try {
            windowState(root)
        } finally {
            root.recycle()
        }
    }

    /**
     * 无可访问窗口时的统一错误。API35 权限弹窗实测活动/聚焦窗口没有可访问 root，
     * 无法取得包名，因此这里只做条件式人工提示，不声称识别具体权限弹窗。
     */
    private fun noAccessibleWindowError(): PhoneAgentError = PhoneAgentError(
        "no_window",
        "No accessible window is available. If a system permission dialog is visible, ask the user to handle or cancel it, then return to the test app and retry.",
    )

    /**
     * 收集整屏所有可访问窗口 root 的密码 bounds。任一窗口无法读取时让截图失败，
     * 避免在漏遮挡的情况下发出截图。只有能可靠确认属于本服务自己的 accessibility
     * overlay 窗口才跳过；root 包名未知或其他包名的窗口继续参与遮挡。
     */
    private fun collectPasswordBounds(current: WindowState): List<Bounds> {
        val windowList = try {
            windows.orEmpty()
        } catch (error: Exception) {
            throw PhoneAgentError(
                "screenshot_failed",
                "Could not list the screen windows to mask password fields. Take a new screenshot.",
            )
        }
        val roots = mutableListOf<PhoneNode>()
        try {
            for (window in windowList) {
                try {
                    val windowRoot = window.root
                    if (windowRoot != null) {
                        val ownOverlay = OverlayVisuals.isOwnOverlayWindow(
                            isAccessibilityOverlay = window.type ==
                                AccessibilityWindowInfo.TYPE_ACCESSIBILITY_OVERLAY,
                            rootPackageName = windowRoot.packageName?.toString(),
                            ownPackageName = packageName,
                        )
                        if (ownOverlay) {
                            windowRoot.recycle()
                        } else {
                            roots += AndroidPhoneNode(windowRoot)
                        }
                    }
                } finally {
                    window.recycle()
                }
            }
        } catch (error: Exception) {
            roots.forEach { runCatching { it.recycle() } }
            throw PhoneAgentError(
                "screenshot_failed",
                "Could not read the screen windows to mask password fields. Take a new screenshot.",
            )
        }
        if (roots.isEmpty()) {
            throw PhoneAgentError(
                "screenshot_failed",
                "No accessible window was available to mask password fields. Ask the user to return to the test app, then retry.",
            )
        }
        return try {
            ScreenshotCapture.collectPasswordBounds(
                roots,
                current.width,
                current.height,
            )
        } catch (error: Exception) {
            throw PhoneAgentError(
                "screenshot_failed",
                "Could not inspect password fields before capturing the screen. Take a new screenshot.",
            )
        }
    }

    private fun windowState(root: AccessibilityNodeInfo): WindowState {
        val (width, height) = screenSize()
        return WindowState(
            windowId = root.windowId,
            packageName = root.packageName?.toString(),
            width = width,
            height = height,
            rotation = rotation(),
            windowType = windowType(root),
        )
    }

    /**
     * 解析前台窗口类型。两个来源按顺序尝试，都只认“就是这个窗口”：
     *
     * 1. **节点自己的窗口** `root.window.type`。它直接就是持有该 root 的窗口，
     *    与 `windowId`、包名同源，不存在跨读取的竞态。
     * 2. **`windows` 列表按 `windowId` 精确匹配**。实测 `windows` 会在服务刚连接、
     *    切窗或键盘起落时短暂（甚至持续）只列出 systemui，而 `rootInActiveWindow`
     *    已经是目标应用；这时按 id 查不到，不能退回“列表里唯一的那个窗口”。
     *    匹配失败时在总预算内重试两条来源（见 [WINDOW_TYPE_BUDGET_MS]）。
     *
     * 两条来源都拿不到才落到 [WindowType.UNKNOWN]，由策略层默认拒绝。不放宽任何
     * 判定，也不按包名、层级顺序或位置猜类型。
     */
    private fun windowType(root: AccessibilityNodeInfo): WindowType {
        // 实测（M28，API35 服务重连后首次截图）：root.window 返回 null，同时
        // windows 只列出别的窗口 id，两条路径同时不可用。因此在总预算内交替
        // 重试两条来源，而不是只重读列表。预算用尽仍是 UNKNOWN（fail closed）。
        //
        // 主线程调用一律零预算：截图隐藏握手后的窗口重校验
        // （ScreenshotCapture.start → currentWindow → windowState）在主线程执行，
        // 那里 sleep 2.5 秒会阻塞 UI 并超出文档承诺的约 250ms 有界握手。该处只做
        // “窗口是否变了”的变更检测，UNKNOWN 已足以产生 stale_observation，
        // 重试没有收益，因此不 sleep、只读一次。
        val onMainThread = Looper.myLooper() == Looper.getMainLooper()
        val deadline = SystemClock.elapsedRealtime() +
            if (onMainThread) 0L else WINDOW_TYPE_BUDGET_MS
        var attempt = 0
        while (true) {
            val fromNode = nodeWindowType(root)
            if (fromNode != null && fromNode != WindowType.UNKNOWN) return fromNode
            val entries = readWindowEntries()
            val resolved = WindowType.resolveFromSnapshot(root.windowId, entries)
            if (resolved != WindowType.UNKNOWN) return resolved
            val remaining = deadline - SystemClock.elapsedRealtime()
            if (remaining <= 0) {
                // 只在真有重试预算时才记录：主线程零预算路径每次截图都会走这里，
                // 无条件打日志会变成噪声。日志只含窗口 id 与平台类型整数，
                // 不含包名、节点文本、窗口标题或截图内容。
                if (!onMainThread) {
                    android.util.Log.d(
                        "PhoneAgentDiag",
                        "windowType exhausted attempts=$attempt rootWin=${root.windowId} " +
                            "entries=${entries.joinToString()}",
                    )
                }
                return WindowType.UNKNOWN
            }
            // 优先等平台的 TYPE_WINDOWS_CHANGED：窗口列表刚变化时重读才有意义，
            // 纯固定退避会在列表尚未更新时反复读到同一份旧快照。
            val seen = lastWindowsChanged.get()
            try {
                Thread.sleep(minOf(WINDOW_TYPE_RETRY_DELAY_MS, remaining))
            } catch (error: InterruptedException) {
                Thread.currentThread().interrupt()
                return WindowType.UNKNOWN
            }
            // 只有“等待期间没有新窗口变化事件”才计数；有事件说明列表可能已更新。
            if (lastWindowsChanged.get() == seen) attempt++
        }
    }

    /** 节点自己的窗口类型；取不到返回 null（与“平台给了未知类型”区分）。 */
    private fun nodeWindowType(root: AccessibilityNodeInfo): WindowType? = try {
        root.window?.let { window ->
            try {
                WindowType.fromPlatformType(window.type)
            } finally {
                window.recycle()
            }
        }
    } catch (error: Exception) {
        null
    }

    /** 读一次 `windows` 的 (id, 平台类型) 快照，并回收每一个窗口。 */
    private fun readWindowEntries(): List<Pair<Int, Int>> {
        val windowList = try {
            windows.orEmpty()
        } catch (error: Exception) {
            return emptyList()
        }
        val entries = ArrayList<Pair<Int, Int>>(windowList.size)
        for (window in windowList) {
            try {
                entries += window.id to window.type
            } catch (error: Exception) {
                // 读取失败时该窗口不参与匹配；全部失败即 fail closed。
            } finally {
                window.recycle()
            }
        }
        return entries
    }

    /**
     * 默认电话/短信持有者。`RoleManager.getRoleHolders` 是 @SystemApi
     * （`MANAGE_ROLE_HOLDERS` 签名权限），公共 SDK 无法调用；这里改用解析
     * `ROLE_DIALER` / `ROLE_SMS` 的公共等价接口：`TelecomManager.defaultDialerPackage`
     * 与 `Telephony.Sms.getDefaultSmsPackage`。
     *
     * 两种情况必须区分：查询抛异常或系统服务缺失表示“不知道”，返回
     * [RoleHolders.Unavailable]，策略层拒绝全部输入；查询返回 null 表示系统明确
     * 回答“没有该角色的默认应用”（例如无短信能力的平板），不算解析失败，
     * 否则会把这类正常设备整体封死。
     */
    private fun resolveRoleHolders(): RoleHolders {
        val telecom = getSystemService(TelecomManager::class.java)
            ?: return RoleHolders.Unavailable
        return try {
            RoleHolders.Resolved(
                roleHolderSet(
                    listOf(telecom.defaultDialerPackage, Telephony.Sms.getDefaultSmsPackage(this)),
                ),
            )
        } catch (error: Exception) {
            RoleHolders.Unavailable
        }
    }

    private fun screenSize(): Pair<Int, Int> {
        val windowManager = getSystemService(WindowManager::class.java)
        return if (Build.VERSION.SDK_INT >= 30) {
            val bounds = windowManager.maximumWindowMetrics.bounds
            bounds.width() to bounds.height()
        } else {
            val point = Point()
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay.getRealSize(point)
            point.x to point.y
        }
    }

    private fun rotation(): Int {
        val display = getSystemService(DisplayManager::class.java)
            .getDisplay(Display.DEFAULT_DISPLAY)
        return display?.rotation ?: Surface.ROTATION_0
    }

    private fun ensureUnlocked() {
        val keyguard = getSystemService(KeyguardManager::class.java)
        val power = getSystemService(PowerManager::class.java)
        if (keyguard?.isKeyguardLocked == true || power?.isInteractive == false) {
            registry.invalidateAll()
            if (this::overlay.isInitialized) overlay.clear()
            throw PhoneAgentError(
                "device_locked",
                "Unlock the phone and keep the screen on, then retry.",
            )
        }
    }

    private fun ensureActive() {
        if (destroyed || currentEpoch != generation.get()) {
            throw interrupted()
        }
    }

    /**
     * 可视化事件在主线程绘制前使用的服务代次守卫。捕获事件发生时的 epoch，
     * 服务中断/断连后旧事件即使已入队也不会重新出现。
     */
    private fun visualGuard(): () -> Boolean {
        val epoch = currentEpoch
        return { !destroyed && epoch == generation.get() }
    }

    private fun interruptPending() {
        generation.incrementAndGet()
        handler.post {
            requests.toList().forEach { it(null, interrupted()) }
            pendingScreenshot = null
        }
        if (this::overlay.isInitialized) overlay.release()
        if (!worker.isShutdown) {
            try {
                worker.execute {
                    if (this::executor.isInitialized) executor.interrupt()
                    if (this::screenshots.isInitialized) screenshots.interrupt()
                    if (this::registry.isInitialized) registry.invalidateAll()
                }
            } catch (error: RejectedExecutionException) {
                // 服务已关闭，pending 请求已经完成。
            }
        }
    }

    private fun serviceUnavailable(): PhoneAgentError = PhoneAgentError(
        "service_unavailable",
        "The phone agent service is not connected. Enable it in Android Accessibility settings, then retry.",
    )

    private fun interrupted(): PhoneAgentError = PhoneAgentError(
        "interrupted",
        "The phone agent service was interrupted. Check that the accessibility service is enabled and retry.",
    )
}
