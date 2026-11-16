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
            "approvedApps" -> approvedApps(result)
            "approveApp" -> approveApp(call.arguments, result)
            "revokeApp" -> revokeApp(call.arguments, result)
            "requestApproval" -> requestApproval(call.arguments, result)
            "approvalRequests" -> approvalRequests(result)
            "resolveApproval" -> resolveApproval(call.arguments, result)
            "dismissApprovals" -> dismissApprovals(call.arguments, result)
            "privacyNotice" -> privacyNotice(result)
            "acknowledgePrivacyNotice" -> acknowledgePrivacyNotice(result)
            else -> result.notImplemented()
        }
    }

    /**
     * 白名单查询。批准/撤销/查询不依赖无障碍服务是否连接：Mods 页在服务关闭时
     * 也必须能撤销授权。结果只有包名、签名哈希前 8 位、批准时间与来源助手 id，
     * 不含节点文本、截图或界面内容。
     */
    private fun approvedApps(result: MethodChannel.Result) {
        try {
            val apps = PhoneAgentService.approvals(appContext).approvedApps().map { entry ->
                linkedMapOf<String, Any?>(
                    "package_name" to entry.packageName,
                    "signing_prefix" to entry.signingPrefix,
                    "approved_at" to entry.approvedAtMillis,
                    "last_approved_at" to entry.lastApprovedAtMillis,
                    "source_assistant_id" to entry.sourceAssistantId,
                )
            }
            result.success(linkedMapOf("apps" to apps))
        } catch (error: Exception) {
            result.error(
                "internal_error",
                error.message ?: "Could not read the approved apps.",
                null,
            )
        }
    }

    /**
     * 批准写入。幂等（同一 `(包名, 签名)` 不产生第二条记录、保留首次来源）；
     * 写入前重新解析当前签名，解析失败返回 `signing_unavailable`、与请求保存的
     * 签名不一致返回 `signing_mismatch`，两种情况都不写入（fail closed）。
     *
     * 该入口只供 Kelivo 自己的界面/通知回调使用；模型无法通过它批准，因为承载
     * 助手的 Kelivo 包在硬基线集合内，输入与观察都被拒绝。
     */
    private fun approveApp(rawArguments: Any?, result: MethodChannel.Result) {
        val args = rawArguments as? Map<*, *>
        val packageName = (args?.get("package_name") as? String)?.trim().orEmpty()
        if (packageName.isEmpty()) {
            result.error("invalid_argument", "package_name is required.", null)
            return
        }
        val sourceAssistantId = (args?.get("source_assistant_id") as? String)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        val expected = (args?.get("expected_signing_sha256") as? List<*>)
            ?.mapNotNull { it as? String }
            ?.takeIf { it.isNotEmpty() }
        try {
            val outcome = PhoneAgentService.approvals(appContext).approve(
                packageName = packageName,
                now = System.currentTimeMillis(),
                sourceAssistantId = sourceAssistantId,
                expectedSha256Values = expected,
            )
            if (!outcome.approved) {
                result.error(
                    outcome.reason ?: "approval_failed",
                    if (outcome.reason == ApproveResult.REASON_SIGNING_MISMATCH) {
                        "The signing certificate of $packageName changed since the approval was requested, so it was not approved. Ask the user to approve it again."
                    } else {
                        "The signing certificate of $packageName could not be read, so it was not approved. Ask the user to try again when the app is installed and not updating."
                    },
                    null,
                )
                return
            }
            val entry = outcome.entry
            result.success(
                linkedMapOf<String, Any?>(
                    "package_name" to entry?.packageName,
                    "signing_prefix" to entry?.signingPrefix,
                    "approved_at" to entry?.approvedAtMillis,
                    "outcome" to "approved",
                ),
            )
        } catch (error: Exception) {
            result.error(
                "internal_error",
                error.message ?: "Could not approve the app.",
                null,
            )
        }
    }

    /** 撤销立即生效：下一次判定就会重新返回 `permission_required`。 */
    private fun revokeApp(rawArguments: Any?, result: MethodChannel.Result) {
        val args = rawArguments as? Map<*, *>
        val packageName = (args?.get("package_name") as? String)?.trim().orEmpty()
        if (packageName.isEmpty()) {
            result.error("invalid_argument", "package_name is required.", null)
            return
        }
        try {
            val removed = PhoneAgentService.approvals(appContext).revoke(packageName)
            result.success(
                linkedMapOf<String, Any?>(
                    "package_name" to packageName,
                    "revoked" to removed,
                ),
            )
        } catch (error: Exception) {
            result.error(
                "internal_error",
                error.message ?: "Could not revoke the app.",
                null,
            )
        }
    }

    /**
     * 创建一条待用户处理的批准请求并发出通知。身份由原生侧解析并保存，Dart 只提供
     * 包名与关联上下文（工具调用 id、会话 id、助手 id）。
     *
     * 该入口**只供聊天卡片与通知栏**使用；模型无法触发它（Kelivo 包在硬基线内，
     * 输入与观察都被拒绝）。
     */
    private fun requestApproval(rawArguments: Any?, result: MethodChannel.Result) {
        val args = rawArguments as? Map<*, *>
        val packageName = (args?.get("package_name") as? String)?.trim().orEmpty()
        if (packageName.isEmpty()) {
            result.error("invalid_argument", "package_name is required.", null)
            return
        }
        try {
            val record = PhoneAgentService.requestApproval(
                appContext,
                packageName = packageName,
                toolCallId = (args?.get("tool_call_id") as? String)?.trim(),
                conversationId = (args?.get("conversation_id") as? String)?.trim(),
                approvalAssistantId = (args?.get("approval_assistant_id") as? String)?.trim(),
            )
            result.success(approvalRequestPayload(record))
        } catch (error: Exception) {
            result.error(
                "internal_error",
                error.message ?: "Could not create the approval request.",
                null,
            )
        }
    }

    /** 当前仍待处理的请求（TTL 到期会在这里被置为过期）。不含已处理的历史。 */
    private fun approvalRequests(result: MethodChannel.Result) {
        try {
            val requests = PhoneAgentService.approvalRequests()
                .pending()
                .map(::approvalRequestPayload)
            result.success(linkedMapOf("requests" to requests))
        } catch (error: Exception) {
            result.error(
                "internal_error",
                error.message ?: "Could not read the approval requests.",
                null,
            )
        }
    }

    /**
     * 聊天卡片与通知栏共用的唯一判定入口。**幂等**：请求已是终态时只返回既有状态，
     * 不写白名单。请求已不存在（进程重启后重放）返回 `approval_not_found`。
     */
    private fun resolveApproval(rawArguments: Any?, result: MethodChannel.Result) {
        val args = rawArguments as? Map<*, *>
        val requestId = (args?.get("request_id") as? String)?.trim().orEmpty()
        if (requestId.isEmpty()) {
            result.error("invalid_argument", "request_id is required.", null)
            return
        }
        val approve = args?.get("approve") as? Boolean
        if (approve == null) {
            result.error("invalid_argument", "approve is required.", null)
            return
        }
        try {
            val resolution = PhoneAgentService.resolveApproval(appContext, requestId, approve)
            if (resolution == null) {
                result.error(
                    "approval_not_found",
                    "This approval request is no longer pending. Ask the assistant to try the action again so a new request is created.",
                    null,
                )
                return
            }
            val payload = approvalRequestPayload(resolution.request)
            payload["approve_result"] = resolution.approveResult?.let {
                linkedMapOf<String, Any?>(
                    "approved" to it.approved,
                    "reason" to it.reason,
                )
            }
            result.success(payload)
        } catch (error: Exception) {
            result.error(
                "internal_error",
                error.message ?: "Could not resolve the approval request.",
                null,
            )
        }
    }

    /** 本地清理（切换会话 / 应用重启）：不写白名单、不通知模型。 */
    private fun dismissApprovals(rawArguments: Any?, result: MethodChannel.Result) {
        val args = rawArguments as? Map<*, *>
        val conversationId = (args?.get("conversation_id") as? String)?.trim()
            ?.takeIf { it.isNotEmpty() }
        try {
            PhoneAgentService.dismissApprovals(appContext, conversationId)
            result.success(linkedMapOf("dismissed" to true))
        } catch (error: Exception) {
            result.error(
                "internal_error",
                error.message ?: "Could not dismiss the approval requests.",
                null,
            )
        }
    }

    /** 首次启用隐私确认是否已读（plan 7.5.14，方案 B）。 */
    private fun privacyNotice(result: MethodChannel.Result) {
        try {
            result.success(
                linkedMapOf(
                    "acknowledged" to
                        PhoneAgentService.privacyNotice(appContext).acknowledged(),
                ),
            )
        } catch (error: Exception) {
            result.error(
                "internal_error",
                error.message ?: "Could not read the privacy notice state.",
                null,
            )
        }
    }

    /**
     * 记录用户已读首次启用隐私确认。**这只是告知记录**：不改变任何白名单判定，
     * 也不阻断后续操作。
     */
    private fun acknowledgePrivacyNotice(result: MethodChannel.Result) {
        try {
            PhoneAgentService.privacyNotice(appContext).acknowledge()
            result.success(linkedMapOf("acknowledged" to true))
        } catch (error: Exception) {
            result.error(
                "internal_error",
                error.message ?: "Could not record the privacy notice state.",
                null,
            )
        }
    }

    /**
     * 请求载荷。只含应用身份（包名、签名前缀、可选显示名）与生命周期元数据，
     * 不含节点文本、窗口标题、截图或界面内容。
     */
    private fun approvalRequestPayload(record: ApprovalRequestRecord): LinkedHashMap<String, Any?> =
        linkedMapOf(
            "request_id" to record.id,
            "package_name" to record.packageName,
            "signing_prefix" to record.signingPrefix.takeIf { it.isNotEmpty() },
            "signing_available" to !record.signingUnavailable,
            "display_name" to record.displayName,
            "tool_call_id" to record.toolCallId,
            "conversation_id" to record.conversationId,
            "assistant_id" to record.assistantId,
            "created_at" to record.createdAtMillis,
            "expires_at" to record.expiresAtMillis,
            "state" to record.state.wire,
        )

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
                            result.error(error.code, error.message, error.details)
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
