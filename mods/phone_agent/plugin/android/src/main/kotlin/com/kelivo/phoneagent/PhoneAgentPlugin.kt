package com.kelivo.phoneagent

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicBoolean

/** Flutter 插件入口。通道名固定为 `kelivo/phone_agent`。 */
class PhoneAgentPlugin : FlutterPlugin {
    companion object {
        const val CHANNEL_NAME = "kelivo/phone_agent"
        private const val SCREENSHOT_TIMEOUT_MS = 20_000L
        private const val TREE_TIMEOUT_MS = 15_000L
        private const val INPUT_TIMEOUT_MS = 20_000L
    }

    private var channel: MethodChannel? = null
    private lateinit var appContext: Context
    private val handler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        val methodChannel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        methodChannel.setMethodCallHandler(::handle)
        channel = methodChannel
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "status" -> result.success(PhoneAgentService.status(appContext))
            "openAccessibilitySettings" -> openAccessibilitySettings(result)
            "screenshot" -> dispatch("screenshot", null, SCREENSHOT_TIMEOUT_MS, result)
            "clearScreenshot" -> dispatch("clearScreenshot", null, TREE_TIMEOUT_MS, result)
            "readTree" -> dispatch("readTree", call.arguments, TREE_TIMEOUT_MS, result)
            "input" -> dispatch("input", call.arguments, INPUT_TIMEOUT_MS, result)
            else -> result.notImplemented()
        }
    }

    private fun dispatch(
        method: String,
        rawArguments: Any?,
        timeoutMs: Long,
        result: MethodChannel.Result,
    ) {
        val args = when (rawArguments) {
            null -> null
            is Map<*, *> -> rawArguments.entries.associate {
                it.key.toString() to it.value
            }
            else -> {
                result.error(
                    "invalid_argument",
                    "Arguments must be a map.",
                    null,
                )
                return
            }
        }
        val finished = AtomicBoolean(false)
        val timeout = Runnable {
            if (finished.compareAndSet(false, true)) {
                result.error(
                    "timeout",
                    "The phone agent did not answer $method in time. Check that the accessibility service is enabled and the phone is unlocked, then retry.",
                    null,
                )
            }
        }
        handler.postDelayed(timeout, timeoutMs)
        try {
            PhoneAgentService.dispatch(method, args) { value, error ->
                handler.post {
                    if (finished.compareAndSet(false, true)) {
                        handler.removeCallbacks(timeout)
                        if (error != null) {
                            result.error(error.code, error.message, null)
                        } else {
                            result.success(value)
                        }
                    }
                }
            }
        } catch (error: Exception) {
            if (finished.compareAndSet(false, true)) {
                handler.removeCallbacks(timeout)
                result.error(
                    "internal_error",
                    error.message ?: "The phone agent failed to start $method.",
                    null,
                )
            }
        }
    }

    private fun openAccessibilitySettings(result: MethodChannel.Result) {
        try {
            appContext.startActivity(
                Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
            result.success(null)
        } catch (error: Exception) {
            result.error(
                "settings_unavailable",
                error.message ?: "Could not open Accessibility settings.",
                null,
            )
        }
    }
}
