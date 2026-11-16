package com.kelivo.phoneagent

/**
 * 首次启用隐私确认的本地状态（plan 7.5.14，方案 B：用户拍板）。
 *
 * **只在首次启用 Phone Agent 时提示一次**：截图与界面文字会作为工具结果发送给用户
 * 自己配置的 provider。这是**告知**，不是技术控制——它不阻止用户随后批准任何应用，
 * 也不改变 `PackagePolicy` 的任何判定。
 *
 * 与白名单一致地落在应用私有目录（不进聊天备份、不上传）：换设备或用备份恢复后
 * 需要重新确认一次。provider 更换是否重新提示**本轮不定论**（plan 7.5.14 未定稿），
 * 因此这里只记一个布尔值，不记 provider。
 */
internal interface PrivacyNoticeStorage {
    fun read(): String

    fun write(value: String)
}

internal class InMemoryPrivacyNoticeStorage(private var value: String = "") :
    PrivacyNoticeStorage {
    override fun read(): String = value

    override fun write(value: String) {
        this.value = value
    }
}

/**
 * 文件存储。写入内容固定为 `acknowledged-v1`，读不到或格式不符一律视为**未确认**
 * （fail closed：宁可多提示一次，也不静默跳过告知）。
 */
internal class FilePrivacyNoticeStorage(private val file: java.io.File) :
    PrivacyNoticeStorage {
    override fun read(): String =
        runCatching { if (file.isFile) file.readText() else "" }.getOrDefault("")

    override fun write(value: String) {
        runCatching { file.parentFile?.mkdirs() }
        runCatching { file.writeText(value) }
    }
}

internal class PrivacyNoticeStore(private val storage: PrivacyNoticeStorage) {
    @Synchronized
    fun acknowledged(): Boolean = storage.read().trim() == ACKNOWLEDGED_VALUE

    @Synchronized
    fun acknowledge() {
        storage.write(ACKNOWLEDGED_VALUE)
    }

    /** 撤销确认（仅供测试与显式重置；产品 UI 不提供该入口）。 */
    @Synchronized
    fun reset() {
        storage.write("")
    }

    companion object {
        const val ACKNOWLEDGED_VALUE = "acknowledged-v1"
    }
}
