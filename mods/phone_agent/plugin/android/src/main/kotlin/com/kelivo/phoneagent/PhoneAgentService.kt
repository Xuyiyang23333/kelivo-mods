package com.kelivo.phoneagent

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.KeyguardManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
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

    override fun onCreate() {
        super.onCreate()
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
                "readTree" -> reply(readTree(args), null)
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
        val passwordBounds = collectPasswordBounds(current)
        pendingScreenshot = reply
        screenshots.capture(current, passwordBounds) { outcome ->
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
                        reply(PhoneAgentResult.screenshot(shot), null)
                        overlay.captured(visualGuard())
                    }
                    is ScreenshotOutcome.Failure -> reply(null, outcome.error)
                }
            }
        }
    }

    private fun input(args: Map<String, Any?>?, reply: (Any?, PhoneAgentError?) -> Unit) {
        val action = PhoneAgentArgs.string(args, "action")
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
                "Unknown input action: $action. Use tap, long_press, set_text, scroll, swipe, back, home or recents.",
            )
        }
        val current = currentWindow() ?: throw noAccessibleWindowError()
        executor.execute(request, current) { outcome ->
            when (outcome) {
                is InputOutcome.Success -> reply(
                    PhoneAgentResult.inputSuccess(outcome.action, outcome.message),
                    null,
                )
                is InputOutcome.Failure -> reply(null, outcome.error)
            }
        }
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
            windowType = windowType(root.windowId),
        )
    }

    /**
     * 按 `windowId` 从 `windows` 匹配窗口类型。`AccessibilityNodeInfo` 不提供类型，
     * 只能在这里与前台窗口用同一次读取取得；匹配失败或取到未知类型都落到
     * [WindowType.UNKNOWN]，由策略层默认拒绝，不在策略层另读一次 `windows`。
     */
    private fun windowType(windowId: Int): WindowType {
        val windowList = try {
            windows.orEmpty()
        } catch (error: Exception) {
            return WindowType.UNKNOWN
        }
        // 记录命中结果后统一返回，保证列表里每个窗口都被 recycle（与 collectPasswordBounds 一致）。
        var resolved = WindowType.UNKNOWN
        var found = false
        for (window in windowList) {
            try {
                if (!found && window.id == windowId) {
                    found = true
                    resolved = try {
                        WindowType.fromPlatformType(window.type)
                    } catch (error: Exception) {
                        WindowType.UNKNOWN
                    }
                }
            } catch (error: Exception) {
                // 读取 id 失败时无法确认是不是目标窗口，继续找；找不到即 fail closed。
            } finally {
                window.recycle()
            }
        }
        return resolved
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
