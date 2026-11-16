package com.kelivo.phoneagent

import java.io.File

/**
 * 一条审计元数据记录。字段集合**精确固定为七项**（顺序即落盘列序）：
 * 时间戳、助手 id、会话 id、包名、签名证书哈希前 8 位、动作类型、结果码。
 *
 * **明确不记录**：节点文本、输入文本、密码内容、截图或图片字节、界面内容摘要、
 * 坐标数值、窗口标题。新增字段等于扩大外发与推断面，必须先改文档与 JVM 断言。
 *
 * 元数据不是内容，但审计仍能推断“用过哪些应用”，所以不得据此宣称审计不涉及隐私。
 */
internal data class AuditRecord(
    val occurredAtMillis: Long,
    val assistantId: String?,
    val conversationId: String?,
    val packageName: String?,
    val signingPrefix: String?,
    val action: String,
    val resultCode: String,
) {
    companion object {
        /** 落盘列序，测试据此断言“不多不少”。 */
        val FIELD_NAMES: List<String> = listOf(
            "occurredAtMillis",
            "assistantId",
            "conversationId",
            "packageName",
            "signingPrefix",
            "action",
            "resultCode",
        )

        const val HEADER = "# kelivo phone agent audit v1"
    }
}

/**
 * 字段清洗：去掉制表符、换行与首尾空白，并截断到 [MAX_FIELD_LENGTH]。
 * 只为保证 TSV 结构完整，不做内容识别；调用方本身不得把内容传进来。
 */
internal object AuditFields {
    const val MAX_FIELD_LENGTH = 128

    fun clean(value: String?): String {
        if (value == null) return ""
        val builder = StringBuilder(minOf(value.length, MAX_FIELD_LENGTH))
        for (char in value) {
            when (char) {
                '\t', '\n', '\r' -> continue
                else -> builder.append(char)
            }
            if (builder.length >= MAX_FIELD_LENGTH) break
        }
        return builder.toString().trim()
    }
}

/**
 * 动作类型。只输出固定 token，绝不把工具参数原样写进动作名——`set_text` 的
 * 文本、坐标值、节点 id 都因此不可能进入审计。
 *
 * 返回 null 表示该通道方法不审计（`clearScreenshot`、`status`、白名单方法）。
 */
internal object AuditAction {
    private val INPUT_ACTIONS = setOf(
        "tap",
        "long_press",
        "set_text",
        "scroll",
        "swipe",
        "back",
        "home",
        "recents",
    )

    fun forCall(method: String, args: Map<String, Any?>?): String? = when (method) {
        "readTree" -> "readTree"
        "screenshot" -> "screenshot"
        "input" -> {
            val action = args?.get("action") as? String
            if (action != null && action in INPUT_ACTIONS) "input.$action" else "input"
        }
        else -> null
    }
}

/** 调用期间逐步补全的审计上下文；`packageName` 由取到前台窗口的路径写入。 */
internal class AuditContext(val action: String) {
    @Volatile
    var packageName: String? = null

    @Volatile
    var assistantId: String? = null

    @Volatile
    var conversationId: String? = null
}

/**
 * 通道参数里的身份字段。与 [PhoneAgentArgs] 的区别是**从不抛错**：审计身份缺失
 * 只表示“这一项未知”，不能让它把工具调用变成 `invalid_argument`。
 */
internal object AuditIdentity {
    fun from(args: Map<String, Any?>?): Pair<String?, String?> {
        if (args == null) return null to null
        return optional(args, "assistant_id") to optional(args, "conversation_id")
    }

    private fun optional(args: Map<String, Any?>, name: String): String? {
        val value = args[name] as? String ?: return null
        return value.trim().takeIf { it.isNotEmpty() }
    }
}

/** 成功结果码。失败一律用既有结构化错误码，不新增审计专用错误码。 */
internal const val AUDIT_OK = "ok"

/**
 * 记录构建器。把“结果码 + 上下文”折叠成七字段记录的唯一入口，签名前缀由调用方
 * 注入（生产实现查 `PackageManager`，测试注入固定值）。
 *
 * 这里刻意不接受任何工具参数对象：动作名已由 [AuditAction] 收敛为固定 token，
 * 其余六项都是身份/结果元数据，因此节点文本、输入文本、密码、图片字节、界面摘要、
 * 坐标和窗口标题没有进入记录的路径。
 */
internal object AuditRecorder {
    fun build(
        context: AuditContext,
        resultCode: String,
        now: Long,
        signingPrefix: (String?) -> String?,
    ): AuditRecord {
        val packageName = context.packageName
        return AuditRecord(
            occurredAtMillis = now,
            assistantId = context.assistantId,
            conversationId = context.conversationId,
            packageName = packageName,
            signingPrefix = if (packageName.isNullOrBlank()) null else signingPrefix(packageName),
            action = context.action,
            resultCode = resultCode.ifBlank { AUDIT_OK },
        )
    }
}

/** 审计文件的本地持久化介质。生产实现写应用私有文件，测试实现留在内存。 */
internal interface AuditStorage {
    fun read(): String

    fun write(value: String)
}

internal class InMemoryAuditStorage(private var value: String = "") : AuditStorage {
    var writes: Int = 0
        private set

    override fun read(): String = value

    override fun write(value: String) {
        writes++
        this.value = value
    }
}

/**
 * 应用私有文件存储。先写临时文件再改名，避免写入中断留下半截文件；
 * 改名失败时退回直接覆盖。路径不进入工具结果、不进聊天备份、不上传、不同步。
 */
internal class FileAuditStorage(private val file: File) : AuditStorage {
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

/**
 * 审计日志：追加一条记录后按“30 天或最近 2000 条，先到者生效”滚动淘汰。
 *
 * **永不阻断工具主路径**：构造、读取、淘汰与写入全部包在 `runCatching` 里，
 * 任何失败只增加本地计数 [droppedWrites] 并返回 false，不抛给调用方、不改变
 * 工具结果、也不影响白名单或边界判定。
 */
internal class AuditLog(
    private val storage: AuditStorage,
    private val retentionMillis: Long = RETENTION_MILLIS,
    private val maxEntries: Int = MAX_ENTRIES,
) {
    private var loaded = false
    private val entries = mutableListOf<AuditRecord>()

    /** 本地丢弃计数，只用于诊断与测试，不进入工具结果、不发给模型。 */
    @Volatile
    var droppedWrites: Int = 0
        private set

    @Synchronized
    fun entries(): List<AuditRecord> {
        runCatching { ensureLoaded() }
        return entries.toList()
    }

    /**
     * 追加并滚动淘汰。[now] 默认取记录自身时间戳，便于测试跨 30 天边界。
     * 返回是否成功落盘；失败不影响调用方继续执行。
     */
    @Synchronized
    fun record(record: AuditRecord, now: Long = record.occurredAtMillis): Boolean {
        return try {
            ensureLoaded()
            entries += record
            prune(now)
            storage.write(encode())
            true
        } catch (error: Exception) {
            droppedWrites++
            false
        }
    }

    /**
     * 工具主路径使用的安全入口：构建记录、解析签名前缀与落盘全程不外抛。
     * 签名解析由调用方注入且可能抛异常（`PackageManager`），这里一并吞掉并把
     * 该字段记为 null——审计缺项比让工具调用失败更可接受。
     */
    fun recordSafely(
        context: AuditContext,
        resultCode: String?,
        now: Long,
        signingPrefix: (String?) -> String?,
    ): Boolean = try {
        val safePrefix: (String?) -> String? = { packageName ->
            runCatching { signingPrefix(packageName) }.getOrNull()
        }
        record(
            record = AuditRecorder.build(context, resultCode ?: AUDIT_OK, now, safePrefix),
            now = now,
        )
    } catch (error: Exception) {
        droppedWrites++
        false
    }

    private fun prune(now: Long) {
        val cutoff = now - retentionMillis
        // 恰好 30 天的记录仍在保留窗口内（先到者生效意味着超过才淘汰）。
        entries.removeAll { it.occurredAtMillis < cutoff }
        while (entries.size > maxEntries) {
            entries.removeAt(0)
        }
    }

    private fun ensureLoaded() {
        if (loaded) return
        loaded = true
        // 读取失败按“没有历史记录”处理：审计不是权威数据，读不到不能阻断新记录。
        val text = runCatching { storage.read() }.getOrDefault("")
        for (line in text.lineSequence()) {
            val record = decode(line) ?: continue
            entries += record
        }
        // 加载即裁剪：外部写入、旧版本遗留或被手工编辑的超限文件在读入时就收敛到
        // 「30 天 / 最近 2000 条」。以文件中最新一条记录的时间戳为基准，而不是当前
        // 时钟——否则整份历史会在应用长期未运行后一次性被判为过旧。
        val newest = entries.maxOfOrNull { it.occurredAtMillis } ?: return
        prune(newest)
    }

    private fun encode(): String = buildString {
        append(AuditRecord.HEADER)
        append('\n')
        for (record in entries) {
            append(record.occurredAtMillis)
            append('\t')
            append(AuditFields.clean(record.assistantId))
            append('\t')
            append(AuditFields.clean(record.conversationId))
            append('\t')
            append(AuditFields.clean(record.packageName))
            append('\t')
            append(AuditFields.clean(record.signingPrefix))
            append('\t')
            append(AuditFields.clean(record.action))
            append('\t')
            append(AuditFields.clean(record.resultCode))
            append('\n')
        }
    }

    private fun decode(line: String): AuditRecord? {
        if (line.isBlank() || line == AuditRecord.HEADER) return null
        val parts = line.split('\t')
        if (parts.size != AuditRecord.FIELD_NAMES.size) return null
        val occurredAt = parts[0].trim().toLongOrNull() ?: return null
        val action = parts[5].trim()
        val resultCode = parts[6].trim()
        if (action.isEmpty() || resultCode.isEmpty()) return null
        return AuditRecord(
            occurredAtMillis = occurredAt,
            assistantId = parts[1].takeIf { it.isNotBlank() },
            conversationId = parts[2].takeIf { it.isNotBlank() },
            packageName = parts[3].takeIf { it.isNotBlank() },
            signingPrefix = parts[4].takeIf { it.isNotBlank() },
            action = action,
            resultCode = resultCode,
        )
    }

    companion object {
        /** 滚动保留窗口：30 天。 */
        const val RETENTION_MILLIS: Long = 30L * 24 * 60 * 60 * 1000

        /** 滚动保留条数上限：最近 2000 条。 */
        const val MAX_ENTRIES: Int = 2000

        const val FILE_NAME = "phone_agent_audit.tsv"
    }
}
