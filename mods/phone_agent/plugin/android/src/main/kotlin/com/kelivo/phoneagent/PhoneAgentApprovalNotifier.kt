package com.kelivo.phoneagent

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/**
 * 批准请求的通知栏载体（plan 7.5.6）。
 *
 * **不复用上游 `NotificationService`**：上游只有“点击打开会话”
 * （`notification_service.dart:102` 的 `onDidReceiveNotificationResponse`），
 * 交付代码里 `AndroidNotificationAction` 零命中，因此批准 action 必须是新增基础设施。
 *
 * 约束：
 * - 通知只显示**应用身份**（包名 + 签名前缀 + 可选显示名），不显示节点文本、窗口标题
 *   或界面内容。文案走插件自己的 `strings.xml`（与上游 ARB 分离，插件不 import
 *   `package:Kelivo/...`）。
 * - action 用 `PendingIntent.getBroadcast` 指向 [PhoneAgentApprovalReceiver]，带请求 id
 *   与决策；**幂等性由 [ApprovalRequests] 保证**，通知重放/连点/进程重启后的迟到回调
 *   都拿不到 pending 请求，因此不会写入白名单。
 * - 通知是否真的显示取决于系统通知权限（API 33+ 需 `POST_NOTIFICATIONS`）。没有权限时
 *   静默失败：**批准卡片仍在聊天里可用**，不因为通知发不出去而改变任何判定。
 */
internal class PhoneAgentApprovalNotifier(private val context: Context) {
    private val manager: NotificationManager? =
        context.getSystemService(NotificationManager::class.java)

    fun show(record: ApprovalRequestRecord) {
        val notification = build(record) ?: return
        try {
            ensureChannel()
            manager?.notify(tag(record.id), NOTIFICATION_ID, notification)
        } catch (error: Exception) {
            // 没有通知权限或系统拒绝时静默失败；聊天卡片与 Mods 页不受影响。
        }
    }

    fun cancel(requestId: String) {
        try {
            manager?.cancel(tag(requestId), NOTIFICATION_ID)
        } catch (error: Exception) {
            // 通知已不存在时忽略。
        }
    }

    fun cancelAll() {
        try {
            manager?.cancelAll()
        } catch (error: Exception) {
            // 忽略：清理失败不影响判定，请求状态机已经置终态。
        }
    }

    private fun build(record: ApprovalRequestRecord): Notification? {
        if (Build.VERSION.SDK_INT < 26) return null
        val identity = if (record.signingUnavailable) {
            record.packageName
        } else {
            "${record.packageName} (${record.signingPrefix})"
        }
        val title = context.getString(R.string.kelivo_phone_agent_approval_title)
        val body = context.getString(R.string.kelivo_phone_agent_approval_body, identity)
        val allow = action(
            record.id,
            approve = true,
            label = context.getString(R.string.kelivo_phone_agent_approval_allow),
        )
        val deny = action(
            record.id,
            approve = false,
            label = context.getString(R.string.kelivo_phone_agent_approval_deny),
        )
        return Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .addAction(allow)
            .addAction(deny)
            .build()
    }

    private fun action(requestId: String, approve: Boolean, label: String): Notification.Action {
        val intent = Intent(context, PhoneAgentApprovalReceiver::class.java)
            .setAction(PhoneAgentApprovalReceiver.ACTION_RESOLVE)
            .putExtra(PhoneAgentApprovalReceiver.EXTRA_REQUEST_ID, requestId)
            .putExtra(PhoneAgentApprovalReceiver.EXTRA_APPROVE, approve)
        val pending = PendingIntent.getBroadcast(
            context,
            requestCode(requestId, approve),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Action.Builder(null, label, pending).build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < 26) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.kelivo_phone_agent_approval_channel),
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = context.getString(R.string.kelivo_phone_agent_approval_channel_description)
            setShowBadge(true)
        }
        manager?.createNotificationChannel(channel)
    }

    /** 每个请求的两个 action 各自需要稳定的 request code，避免被 `FLAG_UPDATE_CURRENT` 覆盖。 */
    private fun requestCode(requestId: String, approve: Boolean): Int =
        (requestId.hashCode() * 31 + if (approve) 1 else 0) and 0x7fffffff

    private fun tag(requestId: String): String = "kelivo_phone_agent_approval:$requestId"

    companion object {
        const val CHANNEL_ID = "kelivo_phone_agent_approval"

        /** 每条请求一条独立通知（tag 区分），因此通知 id 可以固定。 */
        const val NOTIFICATION_ID = 0x4b41
    }
}
