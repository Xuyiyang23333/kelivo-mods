package com.kelivo.phoneagent

import android.accessibilityservice.AccessibilityService
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Display
import java.io.ByteArrayOutputStream
import java.util.ArrayDeque
import java.util.concurrent.Executor
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.roundToInt

internal data class CapturedScreenshot(
    val bytes: ByteArray,
    val imageWidth: Int,
    val imageHeight: Int,
    val screenWidth: Int,
    val screenHeight: Int,
    val windowId: Int,
    val packageName: String?,
    val rotation: Int,
)

internal sealed class ScreenshotOutcome {
    data class Success(val screenshot: CapturedScreenshot) : ScreenshotOutcome()
    data class Failure(val error: PhoneAgentError) : ScreenshotOutcome()
}

/** 截图限频：至少间隔 1 秒，每分钟最多 30 张。 */
internal class ScreenshotThrottle(
    private val minIntervalMillis: Long = 1000,
    private val maxPerMinute: Int = 30,
    private val now: () -> Long,
) {
    private var lastAt = Long.MIN_VALUE
    private val recent = ArrayDeque<Long>()

    @Synchronized
    fun tryAcquire(): Boolean {
        val current = now()
        if (lastAt != Long.MIN_VALUE && current - lastAt < minIntervalMillis) {
            return false
        }
        while (recent.isNotEmpty() && current - recent.first() >= 60_000) {
            recent.removeFirst()
        }
        if (recent.size >= maxPerMinute) return false
        lastAt = current
        recent.addLast(current)
        return true
    }
}

/** 纯函数部分，便于单元测试。 */
internal object ScreenshotMasker {
    fun scaledBounds(
        bounds: Bounds,
        scaleX: Double,
        scaleY: Double,
        width: Int,
        height: Int,
    ): Bounds {
        val left = floor(bounds.left * scaleX).toInt().coerceIn(0, width)
        val top = floor(bounds.top * scaleY).toInt().coerceIn(0, height)
        val right = ceil(bounds.right * scaleX).toInt().coerceIn(0, width)
        val bottom = ceil(bounds.bottom * scaleY).toInt().coerceIn(0, height)
        return Bounds(left, top, maxOf(left, right), maxOf(top, bottom))
    }

    /**
     * 截图位图必须与捕获前的屏幕保持相同宽高比。旋转、分屏或尺寸变化会让
     * 密码 bounds 与图片错位，此时应丢弃截图而不是发出错位遮挡的图片。
     */
    fun matchesAspectRatio(
        bitmapWidth: Int,
        bitmapHeight: Int,
        screenWidth: Int,
        screenHeight: Int,
        tolerance: Double = 0.01,
    ): Boolean {
        if (bitmapWidth <= 0 || bitmapHeight <= 0 || screenWidth <= 0 || screenHeight <= 0) {
            return false
        }
        val expected = screenWidth.toDouble() / screenHeight
        val actual = bitmapWidth.toDouble() / bitmapHeight
        return abs(actual - expected) <= expected * tolerance
    }
}

/**
 * API 30+ 截图：缩放到长边不超过 1600，按密码节点 bounds 涂黑。
 * 截图字节不写日志；secure window 只由 Android 错误码判定。
 */
internal class ScreenshotCapture(
    private val service: AccessibilityService,
    private val throttle: ScreenshotThrottle,
    private val worker: Executor,
    private val handler: Handler = Handler(Looper.getMainLooper()),
    private val maxLongEdge: Int = 1600,
    private val beforeCapture: () -> Unit = {},
) {
    @Volatile
    private var pending = false

    @Volatile
    private var cancel: (() -> Unit)? = null

    fun isBusy(): Boolean = pending

    fun interrupt() {
        cancel?.invoke()
    }

    fun capture(
        current: WindowState,
        passwordBounds: List<Bounds>,
        complete: (ScreenshotOutcome) -> Unit,
    ) {
        if (Build.VERSION.SDK_INT < 30) {
            complete(
                ScreenshotOutcome.Failure(
                    PhoneAgentError(
                        "unsupported_os",
                        "Screenshots require Android 11 (API 30) or later.",
                    ),
                ),
            )
            return
        }
        if (pending) {
            complete(
                ScreenshotOutcome.Failure(
                    PhoneAgentError(
                        "busy",
                        "A screenshot is already running. Wait for its result before the next call.",
                    ),
                ),
            )
            return
        }
        if (!throttle.tryAcquire()) {
            complete(
                ScreenshotOutcome.Failure(
                    PhoneAgentError(
                        "rate_limited",
                        "Screenshots are limited to about one per second. Wait and retry.",
                    ),
                ),
            )
            return
        }
        pending = true
        val finished = AtomicBoolean(false)
        lateinit var finish: (ScreenshotOutcome) -> Unit
        val timeout = Runnable {
            finish(
                ScreenshotOutcome.Failure(
                    PhoneAgentError(
                        "timeout",
                        "The screenshot did not finish in time. Check that the phone is unlocked, then retry.",
                    ),
                ),
            )
        }
        finish = { outcome ->
            if (finished.compareAndSet(false, true)) {
                pending = false
                cancel = null
                handler.removeCallbacks(timeout)
                complete(outcome)
            }
        }
        cancel = {
            finish(
                ScreenshotOutcome.Failure(
                    PhoneAgentError(
                        "interrupted",
                        "The phone agent service was interrupted. Take a new screenshot.",
                    ),
                ),
            )
        }
        handler.postDelayed(timeout, 10_000)
        try {
            beforeCapture()
            service.takeScreenshot(
                Display.DEFAULT_DISPLAY,
                worker,
                object : AccessibilityService.TakeScreenshotCallback {
                    override fun onSuccess(result: AccessibilityService.ScreenshotResult) {
                        finish(process(result, current, passwordBounds))
                    }

                    override fun onFailure(errorCode: Int) {
                        finish(ScreenshotOutcome.Failure(mapError(errorCode)))
                    }
                },
            )
        } catch (error: PhoneAgentError) {
            finish(ScreenshotOutcome.Failure(error))
        } catch (error: Exception) {
            finish(
                ScreenshotOutcome.Failure(
                    PhoneAgentError(
                        "screenshot_blocked",
                        error.message ?: "The screenshot request failed. The window may be secure.",
                    ),
                ),
            )
        }
    }

    private fun process(
        result: AccessibilityService.ScreenshotResult,
        current: WindowState,
        passwordBounds: List<Bounds>,
    ): ScreenshotOutcome {
        val buffer = result.hardwareBuffer
        try {
            val hardware = Bitmap.wrapHardwareBuffer(buffer, result.colorSpace)
                ?: return ScreenshotOutcome.Failure(
                    PhoneAgentError(
                        "screenshot_blocked",
                        "Android returned no readable screenshot. The window may be secure.",
                    ),
                )
            val software = try {
                hardware.copy(Bitmap.Config.ARGB_8888, true)
            } finally {
                hardware.recycle()
            }
            if (software == null) {
                return ScreenshotOutcome.Failure(
                    PhoneAgentError(
                        "screenshot_failed",
                        "Could not copy the screenshot bitmap.",
                    ),
                )
            }
            try {
                return encode(software, current, passwordBounds)
            } finally {
                software.recycle()
            }
        } catch (error: PhoneAgentError) {
            return ScreenshotOutcome.Failure(error)
        } catch (error: Exception) {
            return ScreenshotOutcome.Failure(
                PhoneAgentError(
                    "screenshot_failed",
                    error.message ?: "Screenshot processing failed.",
                ),
            )
        } finally {
            buffer.close()
        }
    }

    private fun encode(
        software: Bitmap,
        current: WindowState,
        passwordBounds: List<Bounds>,
    ): ScreenshotOutcome {
        val bitmapWidth = software.width
        val bitmapHeight = software.height
        if (bitmapWidth <= 0 || bitmapHeight <= 0) {
            return ScreenshotOutcome.Failure(
                PhoneAgentError("screenshot_failed", "Android returned an empty screenshot."),
            )
        }
        if (current.width <= 0 || current.height <= 0 ||
            !ScreenshotMasker.matchesAspectRatio(
                bitmapWidth,
                bitmapHeight,
                current.width,
                current.height,
            )
        ) {
            return ScreenshotOutcome.Failure(
                PhoneAgentError(
                    "stale_observation",
                    "The screen changed while the screenshot was captured. Take a new screenshot before using coordinates.",
                ),
            )
        }
        val longEdge = maxOf(bitmapWidth, bitmapHeight)
        val scale = minOf(1.0, maxLongEdge.toDouble() / longEdge)
        val imageWidth = maxOf(1, (bitmapWidth * scale).roundToInt())
        val imageHeight = maxOf(1, (bitmapHeight * scale).roundToInt())
        val needsMask = passwordBounds.isNotEmpty()
        var owned: Bitmap? = null
        val scaled: Bitmap
        if (imageWidth == bitmapWidth && imageHeight == bitmapHeight) {
            if (needsMask && !software.isMutable) {
                val mutable = software.copy(Bitmap.Config.ARGB_8888, true)
                    ?: return ScreenshotOutcome.Failure(
                        PhoneAgentError(
                            "screenshot_failed",
                            "Could not prepare the screenshot for password masking.",
                        ),
                    )
                owned = mutable
                scaled = mutable
            } else {
                scaled = software
            }
        } else if (needsMask) {
            val target = Bitmap.createBitmap(imageWidth, imageHeight, Bitmap.Config.ARGB_8888)
            try {
                Canvas(target).drawBitmap(
                    software,
                    null,
                    Rect(0, 0, imageWidth, imageHeight),
                    Paint().apply { isFilterBitmap = true },
                )
            } catch (error: Exception) {
                target.recycle()
                throw error
            }
            owned = target
            scaled = target
        } else {
            val target = Bitmap.createScaledBitmap(software, imageWidth, imageHeight, true)
            owned = target
            scaled = target
        }
        try {
            if (needsMask) {
                val scaleX = imageWidth.toDouble() / current.width
                val scaleY = imageHeight.toDouble() / current.height
                val canvas = Canvas(scaled)
                val paint = Paint().apply {
                    color = Color.BLACK
                    style = Paint.Style.FILL
                }
                for (bounds in passwordBounds) {
                    val rect = ScreenshotMasker.scaledBounds(
                        bounds,
                        scaleX,
                        scaleY,
                        imageWidth,
                        imageHeight,
                    )
                    canvas.drawRect(
                        rect.left.toFloat(),
                        rect.top.toFloat(),
                        rect.right.toFloat(),
                        rect.bottom.toFloat(),
                        paint,
                    )
                }
            }
            val bytes = ByteArrayOutputStream().use { output ->
                if (!scaled.compress(Bitmap.CompressFormat.PNG, 100, output)) {
                    return ScreenshotOutcome.Failure(
                        PhoneAgentError(
                            "screenshot_failed",
                            "Could not encode the screenshot.",
                        ),
                    )
                }
                output.toByteArray()
            }
            return ScreenshotOutcome.Success(
                CapturedScreenshot(
                    bytes = bytes,
                    imageWidth = imageWidth,
                    imageHeight = imageHeight,
                    screenWidth = current.width,
                    screenHeight = current.height,
                    windowId = current.windowId,
                    packageName = current.packageName,
                    rotation = current.rotation,
                ),
            )
        } finally {
            if (owned != null && owned !== software) owned.recycle()
        }
    }

    companion object {
        private const val MAX_MASK_NODES = 2500
        private const val MAX_MASK_DEPTH = 40

        /**
         * 将 Android 截图错误码映射为模型可执行的结构化错误。
         *
         * 当前整屏 takeScreenshot(Display.DEFAULT_DISPLAY) 路径不会发出
         * ERROR_TAKE_SCREENSHOT_SECURE_WINDOW；该码是 API 34+ 窗口级
         * takeScreenshotOfWindow 的错误。FLAG_SECURE 窗口可能在成功截图中
         * 以黑色区域出现，这里不做像素猜测，也不承诺检测 secure window。
         */
        internal fun mapError(errorCode: Int): PhoneAgentError = when (errorCode) {
            AccessibilityService.ERROR_TAKE_SCREENSHOT_INTERVAL_TIME_SHORT ->
                PhoneAgentError(
                    "rate_limited",
                    "Android limits screenshots to about one per second. Wait and retry.",
                )
            AccessibilityService.ERROR_TAKE_SCREENSHOT_NO_ACCESSIBILITY_ACCESS ->
                PhoneAgentError(
                    "screenshot_blocked",
                    "The accessibility service lost screenshot access. Disable and re-enable it in Accessibility settings.",
                )
            AccessibilityService.ERROR_TAKE_SCREENSHOT_INVALID_DISPLAY ->
                PhoneAgentError(
                    "screenshot_blocked",
                    "The display is not available for screenshots.",
                )
            // 保留窗口级 API 的错误映射；整屏 takeScreenshot 当前不会发出此码。
            AccessibilityService.ERROR_TAKE_SCREENSHOT_SECURE_WINDOW ->
                PhoneAgentError(
                    "screenshot_blocked",
                    "The current window is secure and cannot be captured. Ask the user to leave the protected screen.",
                )
            AccessibilityService.ERROR_TAKE_SCREENSHOT_INVALID_WINDOW ->
                PhoneAgentError(
                    "screenshot_blocked",
                    "The current window cannot be captured. Ask the user to return to the test app.",
                )
            AccessibilityService.ERROR_TAKE_SCREENSHOT_INTERNAL_ERROR ->
                PhoneAgentError(
                    "screenshot_blocked",
                    "Android could not capture the screen. The window may be secure.",
                )
            else -> PhoneAgentError(
                "screenshot_blocked",
                "Screenshot failed with Android error code $errorCode. The window may be secure.",
            )
        }

        /**
         * 收集所有窗口 root 中密码节点及其直接子节点的 bounds，供整屏截图涂黑。
         * 调用方交出所有 root 的所有权；无论成功或失败，本方法都会回收它们。
         */
        fun collectPasswordBounds(
            roots: List<PhoneNode>,
            screenWidth: Int,
            screenHeight: Int,
        ): List<Bounds> {
            val result = mutableListOf<Bounds>()
            var visited = 0
            var failure: Exception? = null

            fun visit(node: PhoneNode, depth: Int) {
                try {
                    if (visited++ >= MAX_MASK_NODES || depth > MAX_MASK_DEPTH) return
                    if (node.isPassword) {
                        if (node.isVisibleToUser &&
                            node.bounds.intersects(screenWidth, screenHeight)
                        ) {
                            result += node.bounds
                        }
                        for (index in 0 until node.childCount) {
                            val child = node.child(index) ?: continue
                            try {
                                if (child.isVisibleToUser) result += child.bounds
                            } finally {
                                child.recycle()
                            }
                        }
                        return
                    }
                    for (index in 0 until node.childCount) {
                        val child = node.child(index) ?: continue
                        visit(child, depth + 1)
                    }
                } finally {
                    node.recycle()
                }
            }

            for (root in roots) {
                try {
                    visit(root, 0)
                } catch (error: Exception) {
                    if (failure == null) failure = error
                }
            }
            failure?.let { throw it }
            return result
        }
    }
}
