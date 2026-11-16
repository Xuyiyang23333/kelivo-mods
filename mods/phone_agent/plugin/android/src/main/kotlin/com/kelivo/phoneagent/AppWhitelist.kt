package com.kelivo.phoneagent

import java.io.File

/**
 * 前台应用的签名身份。`sha256Values` 是**当前**签名证书 SHA-256 的排序去重集合：
 * 单签名包只有一项；多签名包（实测 `com.android.vending` 为 2 项）必须整集合相等，
 * 任一枚新增或替换都算签名变化，按未批准处理（fail closed）。
 *
 * 只保留能通过格式校验的 64 位小写十六进制；无法解析时不构造本对象。
 */
internal data class SigningIdentity(
    val packageName: String,
    val sha256Values: List<String>,
    val displayName: String? = null,
) {
    /** 展示与工具结果使用的身份前缀：排序后第一枚哈希的前 8 个十六进制字符。 */
    val signingPrefix: String get() = sha256Values.first().take(PREFIX_LENGTH)

    val isMultiSigner: Boolean get() = sha256Values.size > 1

    companion object {
        const val PREFIX_LENGTH = 8
        private const val SHA256_HEX_LENGTH = 64

        fun isSha256Hex(value: String): Boolean =
            value.length == SHA256_HEX_LENGTH &&
                value.all { it in '0'..'9' || it in 'a'..'f' }

        /**
         * 规范化签名集合：去空白、转小写、去重、排序，并丢弃格式不合法的项。
         * 返回空集合表示“无法确定签名”，调用方必须按解析失败处理。
         */
        fun normalizeSha256(values: Iterable<String?>): List<String> =
            values.mapNotNull { it?.trim()?.lowercase() }
                .filter(::isSha256Hex)
                .distinct()
                .sorted()
    }
}

/** 一条用户批准记录：`(包名, 签名集合)` 双匹配，全局共享、长期有效。 */
internal data class WhitelistEntry(
    val packageName: String,
    val signingSha256Values: List<String>,
    val approvedAtMillis: Long,
    val lastApprovedAtMillis: Long,
    val sourceAssistantId: String?,
) {
    val signingPrefix: String get() = signingSha256Values.first().take(SigningIdentity.PREFIX_LENGTH)

    fun matches(identity: SigningIdentity): Boolean =
        identity.packageName == packageName && identity.sha256Values == signingSha256Values
}

/** 白名单的本地持久化介质。生产实现写应用私有文件，测试实现留在内存。 */
internal interface WhitelistStorage {
    fun read(): String

    fun write(value: String)
}

internal class InMemoryWhitelistStorage(private var value: String = "") : WhitelistStorage {
    override fun read(): String = value

    override fun write(value: String) {
        this.value = value
    }
}

/**
 * 应用私有文件存储。先写临时文件再改名，避免写入中断留下半条记录；
 * 改名失败时退回直接覆盖。路径不进入工具结果、不进聊天备份、不上传。
 */
internal class FileWhitelistStorage(private val file: File) : WhitelistStorage {
    override fun read(): String =
        runCatching { if (file.isFile) file.readText() else "" }.getOrDefault("")

    override fun write(value: String) {
        runCatching { file.parentFile?.mkdirs() }
        val temp = File(file.path + ".tmp")
        val written = runCatching {
            temp.writeText(value)
            temp.renameTo(file)
        }.getOrDefault(false)
        if (!written) {
            runCatching { file.writeText(value) }
            runCatching { temp.delete() }
        }
    }
}

internal data class ApproveResult(
    val approved: Boolean,
    val reason: String?,
    val entry: WhitelistEntry?,
) {
    companion object {
        /** 当前签名解析失败：不写入，fail closed。 */
        const val REASON_SIGNING_UNAVAILABLE = "signing_unavailable"

        /** 当前签名与批准请求保存的签名不一致：置为失效，不写入。 */
        const val REASON_SIGNING_MISMATCH = "signing_mismatch"

        /**
         * 目标是构建配置的预批准条目：它已直接放行，不写用户白名单，也不产生批准
         * 提示，因此批准/撤销都拒绝，避免留下不可撤销的冗余条目。
         */
        const val REASON_PRE_APPROVED = "pre_approved"
    }
}

/**
 * 用户白名单。写入幂等：同一 `(包名, 签名集合)` 重复批准只更新最后批准时间并保留
 * 首次来源，不产生第二条记录；签名集合变化时按新批准处理（旧的同一包名记录被替换）。
 * 撤销立即生效：下一次判定重新读存储，不缓存放行结果。
 */
internal class WhitelistStore(
    private val storage: WhitelistStorage,
) {
    private var loaded = false
    private val entries = linkedMapOf<String, WhitelistEntry>()

    @Synchronized
    fun all(): List<WhitelistEntry> {
        ensureLoaded()
        return entries.values.toList()
    }

    @Synchronized
    fun find(packageName: String): WhitelistEntry? {
        ensureLoaded()
        return entries[packageName]
    }

    @Synchronized
    fun approve(
        identity: SigningIdentity,
        now: Long,
        sourceAssistantId: String?,
        expectedSha256Values: List<String>? = null,
    ): ApproveResult {
        if (identity.sha256Values.isEmpty()) {
            return ApproveResult(false, ApproveResult.REASON_SIGNING_UNAVAILABLE, null)
        }
        if (expectedSha256Values != null &&
            SigningIdentity.normalizeSha256(expectedSha256Values) != identity.sha256Values
        ) {
            return ApproveResult(false, ApproveResult.REASON_SIGNING_MISMATCH, null)
        }
        ensureLoaded()
        val existing = entries[identity.packageName]
        val entry = if (existing != null && existing.signingSha256Values == identity.sha256Values) {
            existing.copy(
                lastApprovedAtMillis = now,
                sourceAssistantId = existing.sourceAssistantId ?: sourceAssistantId,
            )
        } else {
            WhitelistEntry(
                packageName = identity.packageName,
                signingSha256Values = identity.sha256Values,
                approvedAtMillis = now,
                lastApprovedAtMillis = now,
                sourceAssistantId = sourceAssistantId,
            )
        }
        entries[identity.packageName] = entry
        persist()
        return ApproveResult(true, null, entry)
    }

    @Synchronized
    fun revoke(packageName: String): Boolean {
        ensureLoaded()
        val removed = entries.remove(packageName) != null
        if (removed) persist()
        return removed
    }

    private fun ensureLoaded() {
        if (loaded) return
        loaded = true
        for (line in storage.read().lineSequence()) {
            val entry = parse(line) ?: continue
            entries[entry.packageName] = entry
        }
    }

    private fun parse(line: String): WhitelistEntry? {
        if (line.isBlank() || line == HEADER) return null
        val parts = line.split('\t')
        if (parts.size != 5) return null
        val packageName = parts[0].trim()
        if (packageName.isEmpty()) return null
        val hashes = SigningIdentity.normalizeSha256(parts[1].split(','))
        if (hashes.isEmpty()) return null
        val approvedAt = parts[2].toLongOrNull() ?: return null
        val lastApprovedAt = parts[3].toLongOrNull() ?: approvedAt
        val source = parts[4].takeIf { it.isNotBlank() }
        return WhitelistEntry(packageName, hashes, approvedAt, lastApprovedAt, source)
    }

    private fun persist() {
        val text = buildString {
            appendLine(HEADER)
            for (entry in entries.values) {
                append(entry.packageName)
                append('\t')
                append(entry.signingSha256Values.joinToString(","))
                append('\t')
                append(entry.approvedAtMillis)
                append('\t')
                append(entry.lastApprovedAtMillis)
                append('\t')
                append(entry.sourceAssistantId.orEmpty())
                append('\n')
            }
        }
        storage.write(text)
    }

    companion object {
        const val HEADER = "# kelivo phone agent whitelist v1"
    }
}

/** 包签名解析器。生产实现查 `PackageManager`，纯 JVM 测试注入假实现。 */
internal fun interface SigningResolver {
    /** 解析失败（包不存在、正在更新、无可见性、`PackageManager` 抛异常）返回 null。 */
    fun resolve(packageName: String): SigningIdentity?
}

internal sealed class ApprovalDecision {
    data object Approved : ApprovalDecision()

    /** 未批准。[identity] 为当前解析到的身份，解析失败时为 null（消息里标为 unavailable）。 */
    data class Required(val packageName: String, val identity: SigningIdentity?) :
        ApprovalDecision()
}

/**
 * 批准判定与写入的唯一入口。读取当前签名是**每次判定都做**的动作：不做正缓存，
 * 因此撤销立即生效、签名变化立即失效。
 *
 * [preApprovedPackages] 是构建配置的预批准条目（测试包恒有、debuggable 构建额外有
 * 跨 UID 夹具包）。它们**不写用户白名单、不产生批准提示、不可撤销**，因此批准与
 * 撤销都直接拒绝它们：否则用户白名单里会出现一条永远用不到、也没有界面能撤销的
 * 冗余条目。
 */
internal class AppApprovals(
    private val resolver: SigningResolver,
    private val store: WhitelistStore,
    preApprovedPackages: Set<String> = emptySet(),
) {
    private val preApproved: Set<String> = preApprovedPackages.toSet()

    fun decide(packageName: String): ApprovalDecision {
        val record = store.find(packageName)
        val identity = resolver.resolve(packageName)
        return if (record != null && identity != null && record.matches(identity)) {
            ApprovalDecision.Approved
        } else {
            ApprovalDecision.Required(packageName, identity)
        }
    }

    /**
     * 批准写入前必须重新解析当前签名：解析失败不写入，签名与请求保存的值不一致也不
     * 写入（迟到回调、通知重放都落在这条规则下）。同一 `(包名, 签名)` 幂等。
     */
    fun approve(
        packageName: String,
        now: Long,
        sourceAssistantId: String?,
        expectedSha256Values: List<String>? = null,
    ): ApproveResult {
        if (packageName in preApproved) {
            return ApproveResult(false, ApproveResult.REASON_PRE_APPROVED, null)
        }
        val identity = resolver.resolve(packageName)
        if (identity == null || identity.sha256Values.isEmpty()) {
            return ApproveResult(false, ApproveResult.REASON_SIGNING_UNAVAILABLE, null)
        }
        return store.approve(
            identity = identity,
            now = now,
            sourceAssistantId = sourceAssistantId,
            expectedSha256Values = expectedSha256Values,
        )
    }

    /** 撤销构建配置的预批准条目同样拒绝：它本来就不在用户白名单里。 */
    fun revoke(packageName: String): Boolean {
        if (packageName in preApproved) return false
        return store.revoke(packageName)
    }

    fun approvedApps(): List<WhitelistEntry> = store.all()
}

/**
 * 构建配置预批准条目：直接视为已批准，不写用户白名单、不产生批准提示、
 * 在 Mods 页不可撤销，也不影响其他应用的可达性。
 *
 * [debugPrefixed][debuggable] 为 true 时（debuggable 构建）额外预批准跨 UID 的
 * `FLAG_SECURE` 夹具包，否则异常套件会被自己的白名单门控挡住。release 不预批准
 * 该包名，避免同名第三方包被静默放行。
 */
internal const val SECURE_FIXTURE_PACKAGE = "com.kelivo.phoneagent.securefixture"

internal fun buildPreApprovedPackages(debuggable: Boolean): Set<String> =
    if (debuggable) setOf(TEST_PACKAGE, SECURE_FIXTURE_PACKAGE) else setOf(TEST_PACKAGE)

/**
 * 构建期 deny 清单：只保留**明确不支持或危险**的包，`package_not_allowed` 只对
 * 成员出现。首版成员清单尚未定稿（设计提案：初始为空），因此这里为空；不得把
 * 硬基线集合复制进来充数——硬基线由更早的一层返回 `system_window_denied`。
 */
internal val DENY_PACKAGES: Set<String> = emptySet()
