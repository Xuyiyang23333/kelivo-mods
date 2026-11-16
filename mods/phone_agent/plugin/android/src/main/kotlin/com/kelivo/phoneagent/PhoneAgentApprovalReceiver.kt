package com.kelivo.phoneagent

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 通知栏批准 action 的接收端（plan 7.5.6/7.5.13）。
 *
 * 上游没有通知 action 通道，因此这是新增基础设施。它只做一件事：把
 * `(请求 id, 批准/拒绝)` 交给进程内唯一的判定入口 [PhoneAgentService.resolveApproval]，
 * 由 [ApprovalRequests] 校验终态并（仅在 pending 时）调用 `AppApprovals.approve`。
 *
 * 幂等性不在这里实现，也不在通知侧实现：
 * - 用户连点两次、两个 action 同时触发：第二次看到的记录已是终态，**不写白名单**。
 * - 进程被杀后系统重放 action：新建的 [ApprovalRequests] 里没有该 id，直接丢弃。
 * - 请求已过期、已被取代或被清理：同样是终态，不写入。
 *
 * 因此这个 receiver **不需要也做不到**“只信任自己的 PendingIntent”：安全边界是
 * “请求必须仍在 pending 且签名仍匹配”，而不是 intent 来源。
 */
class PhoneAgentApprovalReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != ACTION_RESOLVE) return
        val requestId = intent.getStringExtra(EXTRA_REQUEST_ID)?.trim().orEmpty()
        if (requestId.isEmpty()) return
        val approve = intent.getBooleanExtra(EXTRA_APPROVE, false)
        PhoneAgentService.resolveApproval(context, requestId, approve)
    }

    companion object {
        const val ACTION_RESOLVE = "com.kelivo.phoneagent.action.RESOLVE_APPROVAL"

        const val EXTRA_REQUEST_ID = "request_id"

        const val EXTRA_APPROVE = "approve"
    }
}
