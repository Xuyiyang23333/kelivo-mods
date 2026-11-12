package com.kelivo.phoneagent

/**
 * 前台可视化事件。只在真实工具观察或系统接受动作后发出；
 * 被拒绝的动作不产生事件。
 */
internal sealed class OverlayEvent {
    data object Observing : OverlayEvent()

    data class Node(val bounds: Bounds, val action: NodeAction) : OverlayEvent()

    data class Gesture(
        val action: GestureAction,
        val startX: Float,
        val startY: Float,
        val endX: Float,
        val endY: Float,
        val durationMillis: Long,
    ) : OverlayEvent()

    data class System(val action: SystemAction) : OverlayEvent()

    data object Captured : OverlayEvent()
}

internal enum class OverlayKind { OBSERVE, NODE, GESTURE, SYSTEM, CAPTURED }

/** 一次可视化的绘制参数；只含几何和动作类型，不含文本、包名或坐标数值标签。 */
internal data class OverlayPlan(
    val kind: OverlayKind,
    val durationMillis: Long,
    val centerX: Float = 0f,
    val centerY: Float = 0f,
    val bounds: Bounds? = null,
    val startX: Float = 0f,
    val startY: Float = 0f,
    val endX: Float = 0f,
    val endY: Float = 0f,
    val travelMillis: Long = 0L,
    val nodeAction: NodeAction? = null,
    val gestureAction: GestureAction? = null,
    val systemAction: SystemAction? = null,
)

/** 纯 JVM 几何与时长。叠加层绘制和测试共用同一套换算。 */
internal object OverlayVisuals {
    const val OBSERVE_MILLIS = 700L
    const val CAPTURED_MILLIS = 500L
    const val NODE_MILLIS = 600L
    const val NODE_LONG_PRESS_MILLIS = 900L
    const val SYSTEM_MILLIS = 500L
    const val GESTURE_TAIL_MILLIS = 200L
    const val MIN_TRAVEL_MILLIS = 50L
    const val MAX_TRAVEL_MILLIS = 2000L
    const val MAX_VISIBLE_MILLIS = 2500L
    const val HIDE_TIMEOUT_MILLIS = 250L
    const val HIDE_SETTLE_MILLIS = 48L

    fun plan(event: OverlayEvent, screenWidth: Int, screenHeight: Int): OverlayPlan? {
        if (screenWidth <= 0 || screenHeight <= 0) return null
        return when (event) {
            OverlayEvent.Observing -> OverlayPlan(OverlayKind.OBSERVE, OBSERVE_MILLIS)
            OverlayEvent.Captured -> OverlayPlan(OverlayKind.CAPTURED, CAPTURED_MILLIS)
            is OverlayEvent.System -> OverlayPlan(
                kind = OverlayKind.SYSTEM,
                durationMillis = SYSTEM_MILLIS,
                systemAction = event.action,
            )
            is OverlayEvent.Node -> {
                val center = center(event.bounds) ?: return null
                OverlayPlan(
                    kind = OverlayKind.NODE,
                    durationMillis = if (event.action == NodeAction.LONG_CLICK) {
                        NODE_LONG_PRESS_MILLIS
                    } else {
                        NODE_MILLIS
                    },
                    centerX = clamp(center.first, screenWidth),
                    centerY = clamp(center.second, screenHeight),
                    bounds = event.bounds,
                    nodeAction = event.action,
                )
            }
            is OverlayEvent.Gesture -> {
                val travel = gestureTravelMillis(event.durationMillis)
                OverlayPlan(
                    kind = OverlayKind.GESTURE,
                    durationMillis = (travel + GESTURE_TAIL_MILLIS)
                        .coerceAtMost(MAX_VISIBLE_MILLIS),
                    startX = clamp(event.startX, screenWidth),
                    startY = clamp(event.startY, screenHeight),
                    endX = clamp(event.endX, screenWidth),
                    endY = clamp(event.endY, screenHeight),
                    travelMillis = travel,
                    gestureAction = event.action,
                )
            }
        }
    }

    /** 退化 bounds（无面积）不绘制；中心按整数边界直接取平均。 */
    fun center(bounds: Bounds): Pair<Float, Float>? {
        if (bounds.right <= bounds.left || bounds.bottom <= bounds.top) return null
        return (bounds.left + bounds.right) / 2f to (bounds.top + bounds.bottom) / 2f
    }

    fun clamp(value: Float, size: Int): Float {
        if (size <= 1) return 0f
        return value.coerceIn(0f, (size - 1).toFloat())
    }

    /** 手势视觉复用真实 `duration_ms`（输入层已校验 50–2000ms），尾段单独另算。 */
    fun gestureTravelMillis(durationMillis: Long): Long =
        durationMillis.coerceIn(MIN_TRAVEL_MILLIS, MAX_TRAVEL_MILLIS)

    /**
     * 截图前密码窗口遍历的过滤规则：只跳过能可靠确认属于本服务自己的
     * accessibility overlay 窗口（root 存在且 root 包名等于自身包）。
     * 其他服务或应用的窗口，以及 root 包名不可读的窗口，都继续参与遮挡；
     * 不能因为无法区分就屏蔽其他窗口，也不把未知身份当作自身窗口。
     */
    fun isOwnOverlayWindow(
        isAccessibilityOverlay: Boolean,
        rootPackageName: String?,
        ownPackageName: String?,
    ): Boolean {
        if (!isAccessibilityOverlay) return false
        if (rootPackageName == null || ownPackageName == null) return false
        return rootPackageName == ownPackageName
    }

    /**
     * 截图隐藏等待期间前台窗口是否已变化。窗口不可读也算变化，
     * 避免用旧密码 bounds 和旧包名发送新窗口的截图。
     */
    fun windowChanged(original: WindowState, latest: WindowState?): Boolean =
        latest != original
}

/**
 * 入队事件的清理代次。事件在主线程真正绘制前用入队时捕获的代次和调用方的
 * `isActive` 再校验一次，覆盖 clear/release/旋转/切窗先于 show 的时序。
 */
internal class OverlayShowGate {
    @Volatile
    private var generation = 0L

    fun bumpGeneration() {
        generation++
    }

    fun capture(): Long = generation

    fun shouldShow(capturedGeneration: Long, isActive: Boolean): Boolean =
        capturedGeneration == generation && isActive
}

/**
 * 叠加层窗口的附着状态。移除失败或状态未知时不允许截图静默继续，
 * 也不允许再添加新窗口，直到一次成功移除把状态恢复为 detached。
 */
internal class OverlayAttachmentTracker {
    private var attached = false
    private var unknown = false

    fun onAddSucceeded() {
        attached = true
        unknown = false
    }

    fun onAddFailed() {
        attached = false
        unknown = false
    }

    fun onRemoveSucceeded() {
        attached = false
        unknown = false
    }

    fun onRemoveFailed() {
        unknown = true
    }

    fun isAttached(): Boolean = attached

    fun isUnknown(): Boolean = unknown

    /** 未知附着状态不能继续添加窗口，避免叠加层失控。 */
    fun canAdd(): Boolean = !unknown

    /** 截图前隐藏窗口的预期结果：未附着时无需等待，未知时 fail closed。 */
    fun hideResult(): OverlayHideResult = when {
        unknown -> OverlayHideResult.FAILED
        attached -> OverlayHideResult.HIDDEN
        else -> OverlayHideResult.NONE
    }
}

/**
 * 主线程可视化状态。截图隐藏期间 `begin` 返回 false，避免在截图过程中重新添加窗口。
 * `revision` 用于让迟到的回调和旧动画失效。
 */
internal class OverlayState(private val now: () -> Long) {
    private var current: OverlayPlan? = null
    private var startedAt = 0L
    private var suppressed = false
    private var revision = 0L

    fun begin(plan: OverlayPlan): Boolean {
        if (suppressed) return false
        current = plan
        startedAt = now()
        revision++
        return true
    }

    fun suppress() {
        suppressed = true
        current = null
        revision++
    }

    fun resume() {
        suppressed = false
        current = null
        revision++
    }

    fun clear() {
        current = null
        revision++
    }

    fun isSuppressed(): Boolean = suppressed

    fun plan(): OverlayPlan? = current

    fun startedAt(): Long = startedAt

    fun revision(): Long = revision

    fun isExpired(): Boolean {
        val plan = current ?: return true
        return now() - startedAt >= plan.durationMillis
    }
}

internal enum class OverlayHideResult { NONE, HIDDEN, FAILED }

internal interface OverlayScheduler {
    fun postFrame(callback: () -> Unit)

    fun postDelayed(delayMillis: Long, callback: () -> Unit)

    fun removePending()
}

internal interface OverlayGate {
    /** 截图前隐藏叠加层；`proceed` 只会在可以安全截图时调用一次。 */
    fun hideForCapture(proceed: () -> Unit, onFailure: () -> Unit)

    /** 截图结束（成功、失败、超时或中断）后恢复显示能力，不恢复旧动画。 */
    fun resumeAfterCapture()

    companion object {
        val NONE: OverlayGate = object : OverlayGate {
            override fun hideForCapture(proceed: () -> Unit, onFailure: () -> Unit) {
                proceed()
            }

            override fun resumeAfterCapture() = Unit
        }
    }
}

/**
 * 截图隐藏握手：移除窗口后至少等待两帧，再额外等待一个合成周期，
 * 让合成器丢弃叠加层后再截图。没有窗口时零等待；隐藏失败或有界等待超时
 * 都只报告失败，不静默继续截图。本类只在主线程使用（`PhoneAgentOverlay` 负责 post）。
 */
internal class OverlayCaptureGate(
    private val scheduler: OverlayScheduler,
    private val hide: () -> OverlayHideResult,
    private val timeoutMillis: Long = OverlayVisuals.HIDE_TIMEOUT_MILLIS,
    private val settleMillis: Long = OverlayVisuals.HIDE_SETTLE_MILLIS,
) : OverlayGate {
    private var request = 0L
    private var waiting = false

    override fun hideForCapture(proceed: () -> Unit, onFailure: () -> Unit) {
        if (waiting) {
            onFailure()
            return
        }
        val id = ++request
        val result = try {
            hide()
        } catch (error: Exception) {
            OverlayHideResult.FAILED
        }
        when (result) {
            OverlayHideResult.NONE -> proceed()
            OverlayHideResult.FAILED -> onFailure()
            OverlayHideResult.HIDDEN -> {
                waiting = true
                scheduler.postDelayed(timeoutMillis) { failIfCurrent(id, onFailure) }
                scheduler.postFrame { afterFirstFrame(id, proceed) }
            }
        }
    }

    override fun resumeAfterCapture() {
        request++
        waiting = false
        scheduler.removePending()
    }

    private fun afterFirstFrame(id: Long, proceed: () -> Unit) {
        if (!isCurrent(id)) return
        scheduler.postFrame { afterSecondFrame(id, proceed) }
    }

    private fun afterSecondFrame(id: Long, proceed: () -> Unit) {
        if (!isCurrent(id)) return
        scheduler.postDelayed(settleMillis) {
            if (!isCurrent(id)) return@postDelayed
            waiting = false
            scheduler.removePending()
            proceed()
        }
    }

    private fun failIfCurrent(id: Long, onFailure: () -> Unit) {
        if (!isCurrent(id)) return
        waiting = false
        onFailure()
    }

    private fun isCurrent(id: Long): Boolean = waiting && id == request
}
