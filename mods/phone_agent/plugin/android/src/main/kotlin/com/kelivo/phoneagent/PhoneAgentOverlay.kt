package com.kelivo.phoneagent

import android.accessibilityservice.AccessibilityService
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.RectF
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.Choreographer
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import kotlin.math.PI
import kotlin.math.sin

/**
 * 前台可视化叠加层。窗口由独立无障碍服务添加，服务断连即随连接销毁；
 * 不申请普通悬浮窗权限，不修改上游宿主。
 *
 * 所有窗口和动画状态只在主线程读写，其他线程调用会被 post 到主线程。
 * 叠加层只显示无文本图形，不显示输入文字、密码、截图字节、节点文本、包名或坐标数值。
 */
internal class PhoneAgentOverlay(
    private val service: AccessibilityService,
    private val screenSize: () -> Pair<Int, Int>,
    private val handler: Handler = Handler(Looper.getMainLooper()),
) : OverlayGate {
    private val windowManager = service.getSystemService(WindowManager::class.java)
    private val state = OverlayState(now = { SystemClock.uptimeMillis() })
    private val scheduler = MainThreadScheduler(handler)
    private val attachment = OverlayAttachmentTracker()
    private val gate = OverlayCaptureGate(scheduler, ::hideNow)

    private var view: OverlayView? = null

    @Volatile
    private var disabled = false

    @Volatile
    private var closed = false

    /** 清理代次：clear/release/hide 后，之前入队的旧事件全部失效。 */
    private val showGate = OverlayShowGate()

    fun observe(isActive: () -> Boolean = { true }) =
        show(OverlayEvent.Observing, isActive)

    fun node(
        bounds: Bounds,
        action: NodeAction,
        isActive: () -> Boolean = { true },
    ) = show(OverlayEvent.Node(bounds, action), isActive)

    fun gesture(
        action: GestureAction,
        startX: Float,
        startY: Float,
        endX: Float,
        endY: Float,
        durationMillis: Long,
        isActive: () -> Boolean = { true },
    ) = show(
        OverlayEvent.Gesture(action, startX, startY, endX, endY, durationMillis),
        isActive,
    )

    fun system(action: SystemAction, isActive: () -> Boolean = { true }) =
        show(OverlayEvent.System(action), isActive)

    fun captured(isActive: () -> Boolean = { true }) =
        show(OverlayEvent.Captured, isActive)

    /** 只清理当前视觉，不影响进行中的截图隐藏握手。 */
    fun clear() {
        post {
            bumpGeneration()
            state.clear()
            removeView()
        }
    }

    /** 服务中断、断连或旋转后清理；不永久禁用可视化。 */
    fun release() {
        post {
            bumpGeneration()
            gate.resumeAfterCapture()
            state.resume()
            removeView()
        }
    }

    /** 服务销毁后不再接受新事件。 */
    fun shutdown() {
        closed = true
        release()
    }

    override fun hideForCapture(proceed: () -> Unit, onFailure: () -> Unit) {
        post { gate.hideForCapture(proceed, onFailure) }
    }

    override fun resumeAfterCapture() {
        post {
            gate.resumeAfterCapture()
            state.resume()
        }
    }

    /**
     * 事件在主线程真正绘制前再次校验：清理代次必须未变（clear/release/hide 先于 show），
     * 且调用方的 `isActive` 仍为 true（手势未取消、服务代次未变）。
     * `expectedGeneration` 由动作开始时捕获，用于让动作后发生的 clear/切窗使旧动作失效。
     */
    fun show(
        event: OverlayEvent,
        isActive: () -> Boolean = { true },
        expectedGeneration: Long? = null,
    ) {
        val requestGeneration = expectedGeneration ?: showGate.capture()
        post {
            if (disabled || closed) return@post
            if (!showGate.shouldShow(requestGeneration, isActive())) return@post
            val (width, height) = screenSize()
            val plan = OverlayVisuals.plan(event, width, height) ?: return@post
            if (!state.begin(plan)) return@post
            render(plan)
        }
    }

    /** 动作开始时捕获的清理代次；动作后 clear/切窗会让旧视觉失效。 */
    fun currentGeneration(): Long = showGate.capture()

    private fun render(plan: OverlayPlan) {
        if (!attachment.canAdd()) {
            // 上一次移除结果未知，不能再叠加新窗口；截图会由 gate fail closed。
            state.clear()
            return
        }
        if (!removeView()) {
            state.clear()
            return
        }
        val (width, height) = screenSize()
        if (width <= 0 || height <= 0) {
            state.clear()
            return
        }
        val overlay = OverlayView(service, plan) { finishedView -> finish(plan, finishedView) }
        val layoutParams = WindowManager.LayoutParams(
            width,
            height,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            if (Build.VERSION.SDK_INT >= 28) {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            }
            title = "PhoneAgentOverlay"
        }
        try {
            windowManager.addView(overlay, layoutParams)
            view = overlay
            attachment.onAddSucceeded()
        } catch (error: Exception) {
            disabled = true
            state.clear()
            attachment.onAddFailed()
            Log.w(TAG, "overlay_add_failed")
        }
    }

    /**
     * 动画结束回调按具体 View 清理，不依赖当前 plan：即使 resume 已清空 plan，
     * 仍会尝试移除该 View；移除失败则进入未知附着状态，后续截图 fail closed。
     */
    private fun finish(plan: OverlayPlan, finishedView: OverlayView) {
        if (state.plan() === plan) state.clear()
        // 动画在 onDraw 内结束，延后一帧再移除窗口，避免在绘制过程中 detach。
        handler.post {
            if (view === finishedView) removeView()
        }
    }

    /** 主线程：移除窗口并抑制新视觉，供截图隐藏握手使用。 */
    private fun hideNow(): OverlayHideResult {
        state.suppress()
        bumpGeneration()
        return when (attachment.hideResult()) {
            OverlayHideResult.NONE -> OverlayHideResult.NONE
            OverlayHideResult.FAILED -> OverlayHideResult.FAILED
            OverlayHideResult.HIDDEN ->
                if (removeView()) OverlayHideResult.HIDDEN else OverlayHideResult.FAILED
        }
    }

    /** 只有成功移除才清空引用；失败或状态未知时保留，后续截图不能静默继续。 */
    private fun removeView(): Boolean {
        val current = view
        if (current == null) return !attachment.isUnknown()
        return try {
            windowManager.removeViewImmediate(current)
            view = null
            attachment.onRemoveSucceeded()
            true
        } catch (error: Exception) {
            attachment.onRemoveFailed()
            false
        }
    }

    private fun bumpGeneration() {
        showGate.bumpGeneration()
    }

    private fun post(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            block()
        } else {
            handler.post(block)
        }
    }

    private class MainThreadScheduler(private val handler: Handler) : OverlayScheduler {
        private val frames = mutableSetOf<Choreographer.FrameCallback>()
        private val delayed = mutableSetOf<Runnable>()

        override fun postFrame(callback: () -> Unit) {
            val frame = object : Choreographer.FrameCallback {
                override fun doFrame(frameTimeNanos: Long) {
                    frames.remove(this)
                    callback()
                }
            }
            frames += frame
            Choreographer.getInstance().postFrameCallback(frame)
        }

        override fun postDelayed(delayMillis: Long, callback: () -> Unit) {
            val runnable = object : Runnable {
                override fun run() {
                    delayed.remove(this)
                    callback()
                }
            }
            delayed += runnable
            handler.postDelayed(runnable, delayMillis)
        }

        override fun removePending() {
            if (frames.isNotEmpty()) {
                val choreographer = Choreographer.getInstance()
                frames.forEach { choreographer.removeFrameCallback(it) }
                frames.clear()
            }
            delayed.forEach { handler.removeCallbacks(it) }
            delayed.clear()
        }
    }

    private class OverlayView(
        context: Context,
        private val plan: OverlayPlan,
        private val onFinished: (OverlayView) -> Unit,
    ) : View(context) {
        private val startedAt = SystemClock.uptimeMillis()
        private val density = resources.displayMetrics.density
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        private var finished = false

        init {
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val elapsed = SystemClock.uptimeMillis() - startedAt
            val progress = if (plan.durationMillis <= 0L) {
                1f
            } else {
                (elapsed.toFloat() / plan.durationMillis).coerceIn(0f, 1f)
            }
            when (plan.kind) {
                OverlayKind.OBSERVE -> drawObserve(canvas, progress)
                OverlayKind.CAPTURED -> drawCaptured(canvas, progress)
                OverlayKind.NODE -> drawNode(canvas, progress, elapsed)
                OverlayKind.GESTURE -> drawGesture(canvas, elapsed)
                OverlayKind.SYSTEM -> drawSystem(canvas, progress)
            }
            if (progress >= 1f) {
                finish()
            } else {
                postInvalidateOnAnimation()
            }
        }

        private fun finish() {
            if (finished) return
            finished = true
            onFinished(this)
        }

        private fun dp(value: Float): Float = value * density

        private fun stroke(widthDp: Float, color: Int, alpha: Float) {
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = dp(widthDp)
            paint.color = color
            paint.alpha = (alpha.coerceIn(0f, 1f) * 255).toInt()
            paint.strokeCap = Paint.Cap.ROUND
            paint.strokeJoin = Paint.Join.ROUND
        }

        private fun fill(color: Int, alpha: Float) {
            paint.style = Paint.Style.FILL
            paint.color = color
            paint.alpha = (alpha.coerceIn(0f, 1f) * 255).toInt()
        }

        private fun drawObserve(canvas: Canvas, progress: Float) {
            val pulse = sin(progress * PI).toFloat()
            stroke(2f, ACCENT, 0.55f * pulse)
            canvas.drawRect(dp(1f), dp(1f), width - dp(1f), height - dp(1f), paint)
            val centerX = width / 2f
            val centerY = dp(56f)
            for (index in 0 until 3) {
                val phase = (progress * 3f - index).coerceIn(0f, 1f)
                fill(ACCENT, 0.75f * sin(phase * PI).toFloat())
                canvas.drawCircle(centerX + (index - 1) * dp(14f), centerY, dp(3.5f), paint)
            }
        }

        private fun drawCaptured(canvas: Canvas, progress: Float) {
            val fade = 1f - progress
            stroke(2f, ACCENT, 0.55f * fade)
            canvas.drawRect(dp(1f), dp(1f), width - dp(1f), height - dp(1f), paint)
            val centerX = width / 2f
            val centerY = height / 2f
            stroke(3f, ACCENT, 0.9f * fade)
            canvas.drawCircle(centerX, centerY, dp(28f), paint)
            canvas.drawLine(
                centerX - dp(11f),
                centerY,
                centerX - dp(3f),
                centerY + dp(9f),
                paint,
            )
            canvas.drawLine(
                centerX - dp(3f),
                centerY + dp(9f),
                centerX + dp(12f),
                centerY - dp(9f),
                paint,
            )
        }

        private fun drawNode(canvas: Canvas, progress: Float, elapsed: Long) {
            val action = plan.nodeAction ?: NodeAction.CLICK
            val fade = 1f - progress
            plan.bounds?.let { bounds ->
                stroke(1.5f, STROKE_LIGHT, 0.8f * fade)
                canvas.drawRoundRect(
                    RectF(
                        bounds.left.toFloat(),
                        bounds.top.toFloat(),
                        bounds.right.toFloat(),
                        bounds.bottom.toFloat(),
                    ),
                    dp(8f),
                    dp(8f),
                    paint,
                )
            }
            val radius = dp(18f) * (0.6f + 0.6f * progress)
            when (action) {
                NodeAction.LONG_CLICK -> {
                    stroke(3f, ACCENT, 0.9f * fade)
                    canvas.drawArc(
                        plan.centerX - radius,
                        plan.centerY - radius,
                        plan.centerX + radius,
                        plan.centerY + radius,
                        -90f,
                        360f * progress,
                        false,
                        paint,
                    )
                }
                NodeAction.SET_TEXT -> {
                    stroke(2.5f, ACCENT, if ((elapsed / 250) % 2 == 0L) 0.9f else 0.35f)
                    canvas.drawLine(
                        plan.centerX,
                        plan.centerY - dp(10f),
                        plan.centerX,
                        plan.centerY + dp(10f),
                        paint,
                    )
                }
                NodeAction.SCROLL_FORWARD,
                NodeAction.SCROLL_BACKWARD,
                NodeAction.SCROLL_UP,
                NodeAction.SCROLL_DOWN,
                NodeAction.SCROLL_LEFT,
                NodeAction.SCROLL_RIGHT,
                -> {
                    stroke(2.5f, ACCENT, 0.9f * fade)
                    val (dirX, dirY) = when (action) {
                        NodeAction.SCROLL_FORWARD, NodeAction.SCROLL_UP -> 0f to -1f
                        NodeAction.SCROLL_BACKWARD, NodeAction.SCROLL_DOWN -> 0f to 1f
                        NodeAction.SCROLL_LEFT -> -1f to 0f
                        else -> 1f to 0f
                    }
                    drawChevron(canvas, plan.centerX, plan.centerY, dirX, dirY, dp(10f))
                }
                else -> {
                    stroke(2.5f, ACCENT, 0.9f * fade)
                    canvas.drawCircle(plan.centerX, plan.centerY, radius, paint)
                }
            }
        }

        private fun drawGesture(canvas: Canvas, elapsed: Long) {
            val travel = plan.travelMillis.coerceAtLeast(1L)
            val travelProgress = (elapsed.toFloat() / travel).coerceIn(0f, 1f)
            val currentX = plan.startX + (plan.endX - plan.startX) * travelProgress
            val currentY = plan.startY + (plan.endY - plan.startY) * travelProgress
            stroke(3f, ACCENT, 0.45f)
            canvas.drawLine(plan.startX, plan.startY, currentX, currentY, paint)
            fill(ACCENT, 0.95f)
            canvas.drawCircle(currentX, currentY, dp(7f), paint)
            if (travelProgress >= 1f) {
                val tailLength = (plan.durationMillis - travel).coerceAtLeast(1L)
                val tail = ((elapsed - travel).toFloat() / tailLength).coerceIn(0f, 1f)
                stroke(2.5f, ACCENT, 0.8f * (1f - tail))
                canvas.drawCircle(plan.endX, plan.endY, dp(10f) + dp(8f) * tail, paint)
            }
        }

        private fun drawSystem(canvas: Canvas, progress: Float) {
            val alpha = 0.9f * (1f - progress * 0.6f)
            val capsuleWidth = dp(56f)
            val capsuleHeight = dp(36f)
            val left = width / 2f - capsuleWidth / 2f
            val top = dp(56f)
            fill(SURFACE_DARK, 0.85f)
            canvas.drawRoundRect(
                RectF(left, top, left + capsuleWidth, top + capsuleHeight),
                dp(18f),
                dp(18f),
                paint,
            )
            val centerX = width / 2f
            val centerY = top + capsuleHeight / 2f
            stroke(2.5f, LIGHT, alpha)
            when (plan.systemAction) {
                SystemAction.BACK -> drawChevron(canvas, centerX, centerY, -1f, 0f, dp(9f))
                SystemAction.HOME -> canvas.drawRoundRect(
                    RectF(
                        centerX - dp(9f),
                        centerY - dp(9f),
                        centerX + dp(9f),
                        centerY + dp(9f),
                    ),
                    dp(4f),
                    dp(4f),
                    paint,
                )
                SystemAction.RECENTS, null -> {
                    canvas.drawRoundRect(
                        RectF(
                            centerX - dp(11f),
                            centerY - dp(8f),
                            centerX + dp(5f),
                            centerY + dp(8f),
                        ),
                        dp(3f),
                        dp(3f),
                        paint,
                    )
                    canvas.drawRoundRect(
                        RectF(
                            centerX - dp(5f),
                            centerY - dp(4f),
                            centerX + dp(11f),
                            centerY + dp(12f),
                        ),
                        dp(3f),
                        dp(3f),
                        paint,
                    )
                }
            }
        }

        private fun drawChevron(
            canvas: Canvas,
            centerX: Float,
            centerY: Float,
            dirX: Float,
            dirY: Float,
            size: Float,
        ) {
            val normalX = -dirY
            val normalY = dirX
            val tipX = centerX + dirX * size
            val tipY = centerY + dirY * size
            val backX = centerX - dirX * size * 0.4f
            val backY = centerY - dirY * size * 0.4f
            canvas.drawLine(
                backX + normalX * size * 0.8f,
                backY + normalY * size * 0.8f,
                tipX,
                tipY,
                paint,
            )
            canvas.drawLine(
                backX - normalX * size * 0.8f,
                backY - normalY * size * 0.8f,
                tipX,
                tipY,
                paint,
            )
        }
    }

    companion object {
        private const val TAG = "PhoneAgentOverlay"

        private val ACCENT = Color.rgb(0, 137, 153)
        private val LIGHT = Color.rgb(249, 250, 253)
        private val STROKE_LIGHT = Color.rgb(200, 204, 211)
        private val SURFACE_DARK = Color.rgb(31, 33, 39)
    }
}
