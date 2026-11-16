package com.kelivo.phoneagent

/**
 * 一条批准请求的生命周期状态。除 [PENDING] 外都是**终态**，写入后不再变更。
 *
 * 终态语义（plan 7.5.13）：
 * - [APPROVED]：用户在聊天卡片或通知栏批准，且白名单写入成功。
 * - [DENIED]：用户在任一端拒绝。
 * - [EXPIRED]：TTL 到期自动失效。模型侧的 `permission_required` 早已返回，过期不需要
 *   通知模型，下次调用会重新触发一条新请求。
 * - [SUPERSEDED]：同一 `(包名, 签名集合)` 出现了更新的请求（例如模型重试触发了新请求）。
 * - [DISMISSED]：本地清理（切换会话、应用重启、服务断连），不代表用户拒绝。
 * - [FAILED]：批准尝试被原生侧拒绝写入（签名解析失败或签名已变化）。
 */
internal enum class ApprovalRequestState(val wire: String) {
    PENDING("pending"),
    APPROVED("approved"),
    DENIED("denied"),
    EXPIRED("expired"),
    SUPERSEDED("superseded"),
    DISMISSED("dismissed"),
    FAILED("failed"),
    ;

    val isTerminal: Boolean get() = this != PENDING
}

/**
 * 一条待用户处理的批准请求。只保存**应用身份**与关联上下文，
 * 不保存节点文本、截图、输入内容或界面内容摘要。
 *
 * [signingSha256Values] 由原生侧在创建请求时解析并保存，**不接受 Dart 传入**
 * （Dart 不是放行点）；批准写入时用它做 `signing_mismatch` 比对。
 * 解析失败时为空集合，此时批准会以 `signing_unavailable` 失败。
 */
internal data class ApprovalRequestRecord(
    val id: String,
    val packageName: String,
    val signingSha256Values: List<String>,
    val displayName: String?,
    val toolCallId: String?,
    val conversationId: String?,
    val assistantId: String?,
    val createdAtMillis: Long,
    val expiresAtMillis: Long,
    val state: ApprovalRequestState,
    val resolvedAtMillis: Long? = null,
    val failureReason: String? = null,
) {
    val signingPrefix: String
        get() = signingSha256Values.firstOrNull()?.take(SigningIdentity.PREFIX_LENGTH) ?: ""

    val signingUnavailable: Boolean get() = signingSha256Values.isEmpty()

    /** 同一目标应用：包名与签名集合都相同。 */
    fun sameTarget(packageName: String, sha256Values: List<String>): Boolean =
        this.packageName == packageName && signingSha256Values == sha256Values
}

/** [ApprovalRequests.resolve] 的结果。[approveResult] 只在本次真的尝试写入时非空。 */
internal data class ApprovalResolution(
    val request: ApprovalRequestRecord,
    val approveResult: ApproveResult? = null,
) {
    val state: ApprovalRequestState get() = request.state
}

/**
 * 独立于工具调用的批准请求状态机（plan 7.5.6/7.5.13）。
 *
 * 为什么不是 `Completer` 等待：工具调用在未批准时**已经同步返回** `permission_required`
 * （Dart 通道 35s、原生排队 15s，等待必然退化成 `timeout`）。因此请求是独立状态记录，
 * 自带 TTL、单终态与显式清理。
 *
 * 纯 JVM：时间与 id 生成从构造函数注入，便于测试确定性地推进 TTL。
 *
 * 关键约束：
 * - **单终态**：已进入终态的记录不再接受任何 resolve；迟到回调（通知重放、连点、
 *   两个入口同时点击）只读到既有终态，**不写白名单**。
 * - **进程内状态**：应用进程被杀后请求自然消失，迟到的通知回调找不到请求即不写入。
 * - **取代**：同一 `(包名, 签名集合)` 出现新请求时旧请求置 `SUPERSEDED`，避免同一应用
 *   在多张卡片/多条通知上被重复批准。
 */
internal class ApprovalRequests(
    private val nowMillis: () -> Long,
    private val idFactory: () -> String = { java.util.UUID.randomUUID().toString() },
    private val ttlMillis: Long = DEFAULT_TTL_MILLIS,
    private val maxRetained: Int = MAX_RETAINED,
) {
    private val records = linkedMapOf<String, ApprovalRequestRecord>()

    @Synchronized
    fun create(
        packageName: String,
        signingSha256Values: List<String>,
        displayName: String?,
        toolCallId: String?,
        conversationId: String?,
        assistantId: String?,
    ): ApprovalRequestRecord {
        val now = nowMillis()
        val hashes = SigningIdentity.normalizeSha256(signingSha256Values)
        supersedeSameTarget(packageName, hashes, now)
        expireStale(now)
        val record = ApprovalRequestRecord(
            id = idFactory(),
            packageName = packageName,
            signingSha256Values = hashes,
            displayName = displayName?.takeIf { it.isNotBlank() },
            toolCallId = toolCallId?.takeIf { it.isNotBlank() },
            conversationId = conversationId?.takeIf { it.isNotBlank() },
            assistantId = assistantId?.takeIf { it.isNotBlank() },
            createdAtMillis = now,
            expiresAtMillis = now + ttlMillis,
            state = ApprovalRequestState.PENDING,
        )
        records[record.id] = record
        trim()
        return record
    }

    /** 当前仍待处理的请求；顺手把 TTL 到期的记录置为 [ApprovalRequestState.EXPIRED]。 */
    @Synchronized
    fun pending(): List<ApprovalRequestRecord> {
        expireStale(nowMillis())
        return records.values.filter { it.state == ApprovalRequestState.PENDING }
    }

    @Synchronized
    fun find(id: String): ApprovalRequestRecord? {
        val record = records[id] ?: return null
        expireStale(nowMillis())
        return records[id] ?: record
    }

    @Synchronized
    fun all(): List<ApprovalRequestRecord> {
        expireStale(nowMillis())
        return records.values.toList()
    }

    /**
     * 处理一次批准或拒绝。幂等：记录已有终态时**不调用** [onApprove]、不写白名单，
     * 直接返回既有终态。TTL 到期同样不写入。
     *
     * 「允许并继续」与「允许」在原生侧**没有区别**：批准只让下一步变得可能，续跑是
     * 聊天侧的调用方拿到 [PhoneAgentResumeOutcome.resumed] 后重新观察再继续。
     * 原生不保存任何恢复意图，也不重放被拒绝的动作（plan 7.5.10）。
     */
    @Synchronized
    fun resolve(
        id: String,
        approve: Boolean,
        onApprove: (ApprovalRequestRecord) -> ApproveResult,
    ): ApprovalResolution? {
        val now = nowMillis()
        expireStale(now)
        val record = records[id] ?: return null
        if (record.state.isTerminal) return ApprovalResolution(record)
        if (!approve) {
            val denied = record.copy(
                state = ApprovalRequestState.DENIED,
                resolvedAtMillis = now,
            )
            records[id] = denied
            return ApprovalResolution(denied)
        }
        val result = onApprove(record)
        val outcome = if (result.approved) {
            record.copy(state = ApprovalRequestState.APPROVED, resolvedAtMillis = now)
        } else {
            record.copy(
                state = ApprovalRequestState.FAILED,
                resolvedAtMillis = now,
                failureReason = result.reason,
            )
        }
        records[id] = outcome
        return ApprovalResolution(outcome, result)
    }

    /** 本地清理单条请求（不写白名单、不通知模型）。已是终态时保持不变。 */
    @Synchronized
    fun dismiss(id: String): ApprovalRequestRecord? {
        val record = records[id] ?: return null
        if (record.state.isTerminal) return record
        val dismissed = record.copy(
            state = ApprovalRequestState.DISMISSED,
            resolvedAtMillis = nowMillis(),
        )
        records[id] = dismissed
        return dismissed
    }

    /** 切换会话/断连清理：只清理该会话的 pending 请求，返回被清理的 id。 */
    @Synchronized
    fun dismissForConversation(conversationId: String): List<String> {
        val ids = records.values
            .filter {
                it.state == ApprovalRequestState.PENDING &&
                    it.conversationId == conversationId
            }
            .map { it.id }
        ids.forEach { dismiss(it) }
        return ids
    }

    @Synchronized
    fun dismissAll(): List<String> {
        val ids = records.values
            .filter { it.state == ApprovalRequestState.PENDING }
            .map { it.id }
        ids.forEach { dismiss(it) }
        return ids
    }

    private fun supersedeSameTarget(
        packageName: String,
        sha256Values: List<String>,
        now: Long,
    ) {
        for ((id, record) in records.entries.toList()) {
            if (record.state != ApprovalRequestState.PENDING) continue
            if (!record.sameTarget(packageName, sha256Values)) continue
            records[id] = record.copy(
                state = ApprovalRequestState.SUPERSEDED,
                resolvedAtMillis = now,
            )
        }
    }

    private fun expireStale(now: Long) {
        for ((id, record) in records.entries.toList()) {
            if (record.state != ApprovalRequestState.PENDING) continue
            if (now < record.expiresAtMillis) continue
            records[id] = record.copy(
                state = ApprovalRequestState.EXPIRED,
                resolvedAtMillis = record.expiresAtMillis,
            )
        }
    }

    /** 只保留最近的 [maxRetained] 条记录，终态记录先被淘汰。 */
    private fun trim() {
        if (records.size <= maxRetained) return
        val removable = records.values
            .filter { it.state.isTerminal }
            .sortedBy { it.resolvedAtMillis ?: 0L }
        for (record in removable) {
            if (records.size <= maxRetained) break
            records.remove(record.id)
        }
    }

    companion object {
        /** 30 分钟：足够用户切回 Kelivo 处理，又不至于让过期卡片长期滞留。 */
        const val DEFAULT_TTL_MILLIS = 30 * 60 * 1000L

        const val MAX_RETAINED = 64
    }
}
