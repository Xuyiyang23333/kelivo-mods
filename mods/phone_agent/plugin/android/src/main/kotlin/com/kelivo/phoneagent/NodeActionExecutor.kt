package com.kelivo.phoneagent

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import java.util.ArrayDeque
import java.util.concurrent.atomic.AtomicBoolean

internal sealed class InputRequest {
    data class NodeActionRequest(
        val action: NodeAction,
        val nodeId: String,
        val text: String? = null,
    ) : InputRequest()

    data class GestureRequest(
        val action: GestureAction,
        val x: Double,
        val y: Double,
        val endX: Double? = null,
        val endY: Double? = null,
        val durationMs: Long? = null,
    ) : InputRequest()

    data class SystemRequest(val action: SystemAction) : InputRequest()
}

internal sealed class InputOutcome {
    data class Success(val action: String, val message: String) : InputOutcome()
    data class Failure(val error: PhoneAgentError) : InputOutcome()
}

/** 归一化坐标换算。越界、NaN 和无穷大一律拒绝。 */
internal object CoordinateMapper {
    fun toPixel(value: Double, size: Int, name: String): Float {
        if (!value.isFinite() || value < 0.0 || value > 1.0) {
            throw PhoneAgentError(
                "invalid_argument",
                "$name must be a normalized coordinate between 0 and 1.",
            )
        }
        if (size <= 0) {
            throw PhoneAgentError(
                "stale_observation",
                "The screen size is unavailable. Take a new screenshot.",
            )
        }
        return (value * size).toFloat().coerceIn(0f, (size - 1).toFloat())
    }
}

/**
 * 首版输入白名单。开发者只能在私有 Mod 中修改此集合。
 * 系统窗口无论是否在白名单内都拒绝。
 */
internal class PackagePolicy(
    private val allowedPackages: Set<String> = setOf("com.psyche.kelivo.phoneagent"),
    private val systemPackages: Set<String> = setOf(
        "com.android.systemui",
        "com.android.permissioncontroller",
        "com.google.android.permissioncontroller",
        "com.android.packageinstaller",
        "com.google.android.packageinstaller",
    ),
) {
    fun requireInputAllowed(packageName: String?) {
        if (packageName.isNullOrBlank()) {
            throw PhoneAgentError(
                "no_window",
                "No foreground app is available. Ask the user to open the test app, then retry.",
            )
        }
        if (packageName in systemPackages) {
            throw PhoneAgentError(
                "system_window_denied",
                "The foreground window is a system window ($packageName). Ask the user to dismiss it and return to the test app.",
            )
        }
        if (packageName !in allowedPackages) {
            throw PhoneAgentError(
                "package_not_allowed",
                "Input is limited to ${allowedPackages.joinToString()} in this build. The foreground app is $packageName.",
            )
        }
    }
}

/** 滑动窗口动作预算，防止单次生成内无限循环输入。 */
internal class ActionBudget(
    private val limit: Int = 120,
    private val windowMillis: Long = 60_000,
    private val now: () -> Long,
) {
    private val timestamps = ArrayDeque<Long>()

    @Synchronized
    fun tryConsume(): Boolean {
        val current = now()
        while (timestamps.isNotEmpty() && current - timestamps.first() >= windowMillis) {
            timestamps.removeFirst()
        }
        if (timestamps.size >= limit) return false
        timestamps.addLast(current)
        return true
    }
}

/**
 * 节点、坐标和系统输入。所有调用都在服务单 worker 上串行执行；
 * 手势完成前保持单飞，后续请求返回 `busy`。
 */
internal class NodeActionExecutor(
    private val service: AccessibilityService,
    private val registry: ObservationRegistry,
    private val policy: PackagePolicy = PackagePolicy(),
    private val budget: ActionBudget = ActionBudget(now = { SystemClock.elapsedRealtime() }),
    private val handler: Handler = Handler(Looper.getMainLooper()),
    private val beforeAction: () -> Unit = {},
    private val visual: (OverlayEvent, () -> Boolean) -> Unit = { _, _ -> },
    private val clearVisual: () -> Unit = {},
) {
    @Volatile
    private var pendingGesture: ((InputOutcome) -> Unit)? = null

    fun isBusy(): Boolean = pendingGesture != null

    fun interrupt() {
        pendingGesture?.invoke(
            InputOutcome.Failure(
                PhoneAgentError(
                    "interrupted",
                    "The phone agent service was interrupted. Take a screenshot before retrying.",
                ),
            ),
        )
    }

    fun execute(
        request: InputRequest,
        current: WindowState,
        complete: (InputOutcome) -> Unit,
    ) {
        try {
            if (!budget.tryConsume()) {
                throw PhoneAgentError(
                    "budget_exceeded",
                    "Too many phone agent actions in the last minute. Wait before continuing.",
                )
            }
            when (request) {
                is InputRequest.NodeActionRequest -> executeNode(request, current, complete)
                is InputRequest.GestureRequest -> executeGesture(request, current, complete)
                is InputRequest.SystemRequest -> executeSystem(request, current, complete)
            }
        } catch (error: PhoneAgentError) {
            complete(InputOutcome.Failure(error))
        }
    }

    private fun executeNode(
        request: InputRequest.NodeActionRequest,
        current: WindowState,
        complete: (InputOutcome) -> Unit,
    ) {
        policy.requireInputAllowed(current.packageName)
        val handle = registry.handle(request.nodeId, current)
        val accepted = performNodeAction(
            handle = handle,
            action = request.action,
            text = request.text,
            beforeAction = beforeAction,
            visual = { bounds, action -> showVisual(OverlayEvent.Node(bounds, action)) },
        )
        registry.clearScreenshot()
        if (!accepted) {
            throw PhoneAgentError(
                "action_failed",
                "The target did not accept the action. Read the tree again and choose an actionable node or use coordinates.",
            )
        }
        complete(
            InputOutcome.Success(
                request.action.wireName(),
                "Action accepted. Read the tree or take a screenshot to verify the result.",
            ),
        )
    }

    private fun executeGesture(
        request: InputRequest.GestureRequest,
        current: WindowState,
        complete: (InputOutcome) -> Unit,
    ) {
        policy.requireInputAllowed(current.packageName)
        if (pendingGesture != null) {
            throw PhoneAgentError(
                "busy",
                "A gesture is still running. Wait for its result before the next call.",
            )
        }
        val observation = registry.requireScreenshot(current)
        val startX = CoordinateMapper.toPixel(request.x, observation.screenWidth, "x")
        val startY = CoordinateMapper.toPixel(request.y, observation.screenHeight, "y")
        val path = Path().apply { moveTo(startX, startY) }
        var endX: Float? = null
        var endY: Float? = null
        if (request.action == GestureAction.SWIPE) {
            endX = CoordinateMapper.toPixel(
                request.endX ?: throw PhoneAgentError(
                    "invalid_argument",
                    "end_x is required for swipe.",
                ),
                observation.screenWidth,
                "end_x",
            )
            endY = CoordinateMapper.toPixel(
                request.endY ?: throw PhoneAgentError(
                    "invalid_argument",
                    "end_y is required for swipe.",
                ),
                observation.screenHeight,
                "end_y",
            )
            path.lineTo(endX, endY)
        }
        val duration = request.durationMs ?: when (request.action) {
            GestureAction.LONG_PRESS -> 600L
            GestureAction.SWIPE -> 350L
            GestureAction.TAP -> 80L
        }
        if (duration !in 50..2000) {
            throw PhoneAgentError("invalid_argument", "duration_ms must be between 50 and 2000.")
        }
        if (request.action == GestureAction.LONG_PRESS && duration < 500) {
            throw PhoneAgentError("invalid_argument", "long_press requires at least 500 ms.")
        }
        registry.clearScreenshot()
        dispatchGesture(request.action, path, duration, complete) { isActive ->
            showVisual(
                OverlayEvent.Gesture(
                    action = request.action,
                    startX = startX,
                    startY = startY,
                    endX = endX ?: startX,
                    endY = endY ?: startY,
                    durationMillis = duration,
                ),
                isActive,
            )
        }
    }

    private fun executeSystem(
        request: InputRequest.SystemRequest,
        current: WindowState,
        complete: (InputOutcome) -> Unit,
    ) {
        policy.requireInputAllowed(current.packageName)
        registry.invalidateAll()
        val globalAction = when (request.action) {
            SystemAction.BACK -> AccessibilityService.GLOBAL_ACTION_BACK
            SystemAction.HOME -> AccessibilityService.GLOBAL_ACTION_HOME
            SystemAction.RECENTS -> AccessibilityService.GLOBAL_ACTION_RECENTS
        }
        beforeAction()
        if (!service.performGlobalAction(globalAction)) {
            throw PhoneAgentError(
                "action_failed",
                "Android rejected the system action. Read the tree or take a screenshot before retrying.",
            )
        }
        showVisual(OverlayEvent.System(request.action))
        complete(
            InputOutcome.Success(
                request.action.wireName,
                "System action accepted. Read the tree or take a screenshot to verify the result.",
            ),
        )
    }

    private fun dispatchGesture(
        action: GestureAction,
        path: Path,
        duration: Long,
        complete: (InputOutcome) -> Unit,
        visual: (() -> Boolean) -> Unit,
    ) {
        val finished = AtomicBoolean(false)
        var visualShown = false
        lateinit var finish: (InputOutcome) -> Unit
        val timeout = Runnable {
            finish(
                InputOutcome.Failure(
                    PhoneAgentError(
                        "gesture_timeout",
                        "Gesture completion is unknown. Take a screenshot before retrying.",
                    ),
                ),
            )
        }
        finish = { outcome ->
            if (finished.compareAndSet(false, true)) {
                handler.removeCallbacks(timeout)
                pendingGesture = null
                if (outcome is InputOutcome.Failure && visualShown) clearVisualSafely()
                complete(outcome)
            }
        }
        pendingGesture = finish
        handler.postDelayed(timeout, duration + 3000)
        try {
            beforeAction()
            val accepted = service.dispatchGesture(
                GestureDescription.Builder()
                    .addStroke(GestureDescription.StrokeDescription(path, 0, duration))
                    .build(),
                object : AccessibilityService.GestureResultCallback() {
                    override fun onCompleted(gestureDescription: GestureDescription?) {
                        handler.post {
                            finish(
                                InputOutcome.Success(
                                    action.wireName,
                                    "Gesture completed. Take a screenshot to verify the result.",
                                ),
                            )
                        }
                    }

                    override fun onCancelled(gestureDescription: GestureDescription?) {
                        handler.post {
                            finish(
                                InputOutcome.Failure(
                                    PhoneAgentError(
                                        "gesture_cancelled",
                                        "The gesture was cancelled. Take a screenshot before retrying.",
                                    ),
                                ),
                            )
                        }
                    }
                },
                handler,
            )
            if (accepted) {
                visualShown = true
                runCatching { visual { !finished.get() } }
            } else {
                finish(
                    InputOutcome.Failure(
                        PhoneAgentError(
                            "gesture_rejected",
                            "Android rejected this gesture. Take a screenshot before retrying.",
                        ),
                    ),
                )
            }
        } catch (error: PhoneAgentError) {
            finish(InputOutcome.Failure(error))
        } catch (error: Exception) {
            finish(
                InputOutcome.Failure(
                    PhoneAgentError(
                        "gesture_failed",
                        error.message ?: "The gesture failed. Take a screenshot before retrying.",
                    ),
                ),
            )
        }
    }

    private fun showVisual(event: OverlayEvent, isActive: () -> Boolean = { true }) {
        runCatching { visual(event, isActive) }
    }

    private fun clearVisualSafely() {
        runCatching { clearVisual() }
    }

    private fun NodeAction.wireName(): String = when (this) {
        NodeAction.CLICK -> "tap"
        NodeAction.LONG_CLICK -> "long_press"
        NodeAction.SET_TEXT -> "set_text"
        NodeAction.SCROLL_FORWARD,
        NodeAction.SCROLL_BACKWARD,
        NodeAction.SCROLL_UP,
        NodeAction.SCROLL_DOWN,
        NodeAction.SCROLL_LEFT,
        NodeAction.SCROLL_RIGHT,
        -> "scroll"
    }
}

/**
 * 节点动作的纯 JVM 前置校验与执行。调用方必须在 `registry.handle()` 刷新后调用，
 * 动作可用性按当前节点重新校验；校验失败时不会执行 `beforeAction`、`perform` 或可视化。
 * `visual` 只在系统接受动作后收到刷新后的 bounds；它抛异常不改变返回值。
 */
internal fun performNodeAction(
    handle: SavedHandle,
    action: NodeAction,
    text: String?,
    beforeAction: () -> Unit = {},
    visual: (Bounds, NodeAction) -> Unit = { _, _ -> },
): Boolean {
    if (handle.record.password) {
        throw PhoneAgentError(
            "password_node_denied",
            "The target is a password field. Direct input is disabled; ask the user to handle it.",
        )
    }
    if (action == NodeAction.SET_TEXT && !handle.record.editable) {
        throw PhoneAgentError(
            "action_unavailable",
            "The target is not editable. Choose an editable field or tap it to focus, then read the tree again.",
        )
    }
    if (action !in handle.node.actions) {
        throw PhoneAgentError(
            "action_unavailable",
            if (action == NodeAction.SET_TEXT) {
                "This field does not currently support setting text. Tap it to focus, then read the tree again before set_text."
            } else {
                "The node does not advertise this action. Choose an actionable node, another scroll direction, or a coordinate gesture."
            },
        )
    }
    if (action == NodeAction.SET_TEXT && text == null) {
        throw PhoneAgentError("invalid_argument", "text is required for set_text.")
    }
    val bounds = handle.node.bounds
    beforeAction()
    val accepted = handle.node.perform(action, text)
    if (accepted) {
        runCatching { visual(bounds, action) }
    }
    return accepted
}
