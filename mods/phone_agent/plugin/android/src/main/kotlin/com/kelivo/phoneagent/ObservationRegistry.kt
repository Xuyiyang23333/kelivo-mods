package com.kelivo.phoneagent

/**
 * 当前前台窗口的稳定标识，用于失效判断。
 *
 * `windowType` 与 `windowId` 同源（同一次 `windowState()` 读取）：类型只能按 id 从
 * `windows` 匹配，解析失败落到 [WindowType.UNKNOWN] 并拒绝输入。
 */
internal data class WindowState(
    val windowId: Int,
    val packageName: String?,
    val width: Int,
    val height: Int,
    val rotation: Int,
    val windowType: WindowType,
)

internal data class ScreenshotObservation(
    val imageWidth: Int,
    val imageHeight: Int,
    val screenWidth: Int,
    val screenHeight: Int,
    val windowId: Int,
    val packageName: String?,
    val rotation: Int,
    val windowType: WindowType,
    val createdAt: Long,
)

internal data class TreePage(
    val records: List<NodeRecord>,
    val offset: Int,
    val nextOffset: Int?,
    val total: Int,
    val truncated: Boolean,
    val textTruncated: Boolean,
    val packageName: String?,
    val screenWidth: Int,
    val screenHeight: Int,
)

internal class SavedHandle(
    val id: String,
    val node: PhoneNode,
    val fingerprint: NodeFingerprint,
    val record: NodeRecord,
)

/**
 * 原生观测状态：树句柄、截图坐标观测、120 秒 TTL 和失效管理。
 *
 * 句柄只在当前观测内有效。动作后不清空树句柄；每次使用前重新
 * `refresh()` 并比较指纹（焦点变化和动作集合变化不失效，动作可用性在动作前按当前节点校验）。
 * `refresh()` 失败时按读树时记录的子索引路径在当前活动窗口重解析一次，
 * 并要求指纹逐字段一致；否则仍返回 `stale_handle`。
 * 窗口、包名、尺寸、旋转或窗口类型变化会让树和截图失效。
 */
internal class ObservationRegistry(
    private val ttlMillis: Long = DEFAULT_TTL_MILLIS,
    private val now: () -> Long,
    private val rootProvider: () -> PhoneNode? = { null },
) {
    private var tree: TreeObservation? = null
    private var screenshot: ScreenshotObservation? = null

    @Synchronized
    fun beginTree(observation: TreeObservation) {
        clearTreeLocked()
        tree = observation
    }

    @Synchronized
    fun page(offset: Int, maxNodes: Int, current: WindowState): TreePage {
        val observation = tree ?: throw PhoneAgentError(
            "stale_observation",
            "No current tree observation. Call phone_agent_tree with offset 0.",
        )
        requireTreeValid(observation, current)
        val start = offset.coerceIn(0, observation.records.size)
        val end = minOf(observation.records.size, start + maxNodes)
        return TreePage(
            records = observation.records.subList(start, end),
            offset = start,
            nextOffset = if (end < observation.records.size) end else null,
            total = observation.records.size,
            truncated = observation.truncated,
            textTruncated = observation.textTruncated,
            packageName = observation.packageName,
            screenWidth = observation.screenWidth,
            screenHeight = observation.screenHeight,
        )
    }

    @Synchronized
    fun handle(nodeId: String, current: WindowState): SavedHandle {
        val observation = tree ?: throw PhoneAgentError(
            "stale_handle",
            "No current tree observation. Call phone_agent_tree with offset 0.",
        )
        if (isExpired(observation.createdAt) || !sameWindow(observation, current)) {
            clearTreeLocked()
            throw PhoneAgentError(
                "stale_handle",
                "The tree observation is no longer valid. Call phone_agent_tree with offset 0.",
            )
        }
        val index = observation.records.indexOfFirst { it.id == nodeId }
        if (index < 0) {
            throw PhoneAgentError(
                "stale_handle",
                "Unknown node handle $nodeId. Call phone_agent_tree with offset 0.",
            )
        }
        val node = observation.handleAt(index)
        if (!node.refresh()) {
            val resolved = resolveByPath(observation, index) ?: throw targetChanged("refresh_failed")
            runCatching { node.recycle() }
            observation.replaceHandle(index, resolved)
        }
        val target = observation.handleAt(index)
        if (!target.isVisibleToUser) {
            throw targetChanged("not_visible")
        }
        if (!target.isEnabled) {
            throw targetChanged("not_enabled")
        }
        val current = target.fingerprint()
        if (current != observation.fingerprints[index]) {
            val changed = fingerprintDiff(observation.fingerprints[index], current)
            throw targetChanged(changed.joinToString(", "))
        }
        return SavedHandle(
            id = nodeId,
            node = target,
            fingerprint = observation.fingerprints[index],
            record = observation.records[index],
        )
    }

    /**
     * `refresh()` 失败后的受控重解析：按读树时记录的从根到目标的子索引路径
     * 在当前活动窗口重新取节点，并要求指纹逐字段一致。路径不存在、节点缺失
     * 或指纹不同都返回 null，由调用方维持 `stale_handle`。
     */
    private fun resolveByPath(observation: TreeObservation, index: Int): PhoneNode? {
        val path = observation.paths.getOrNull(index) ?: return null
        var current: PhoneNode = rootProvider() ?: return null
        for (step in path) {
            val child = runCatching { current.child(step) }.getOrNull()
            // 契约：PhoneNode.child() 每次返回可独立回收的引用，因此无条件回收上一层。
            runCatching { current.recycle() }
            if (child == null) return null
            current = child
        }
        val fingerprint = runCatching { current.fingerprint() }.getOrNull()
        if (fingerprint == null || fingerprint != observation.fingerprints[index]) {
            runCatching { current.recycle() }
            return null
        }
        return current
    }

    @Synchronized
    fun recordScreenshot(observation: ScreenshotObservation) {
        screenshot = observation
    }

    @Synchronized
    fun requireScreenshot(current: WindowState): ScreenshotObservation {
        val observation = screenshot ?: throw PhoneAgentError(
            "screenshot_required",
            "Take a screenshot with phone_agent_screenshot before using coordinates.",
        )
        if (isExpired(observation.createdAt)) {
            screenshot = null
            throw PhoneAgentError(
                "stale_observation",
                "The screenshot expired after ${ttlMillis / 1000} seconds. Take a new screenshot.",
            )
        }
        if (observation.windowId != current.windowId ||
            observation.packageName != current.packageName ||
            observation.screenWidth != current.width ||
            observation.screenHeight != current.height ||
            observation.rotation != current.rotation
        ) {
            screenshot = null
            throw PhoneAgentError(
                "stale_observation",
                "The screen changed since the screenshot. Take a new screenshot.",
            )
        }
        return observation
    }

    @Synchronized
    fun clearScreenshot() {
        screenshot = null
    }

    @Synchronized
    fun clearTree() {
        clearTreeLocked()
    }

    @Synchronized
    fun invalidateAll() {
        clearTreeLocked()
        screenshot = null
    }

    private fun requireTreeValid(observation: TreeObservation, current: WindowState) {
        if (isExpired(observation.createdAt)) {
            clearTreeLocked()
            throw PhoneAgentError(
                "stale_observation",
                "The tree observation expired after ${ttlMillis / 1000} seconds. Call phone_agent_tree with offset 0.",
            )
        }
        if (!sameWindow(observation, current)) {
            clearTreeLocked()
            throw PhoneAgentError(
                "stale_observation",
                "The active window changed. Call phone_agent_tree with offset 0.",
            )
        }
    }

    private fun sameWindow(observation: TreeObservation, current: WindowState): Boolean =
        observation.windowId == current.windowId &&
            observation.packageName == current.packageName &&
            observation.screenWidth == current.width &&
            observation.screenHeight == current.height &&
            observation.rotation == current.rotation

    private fun isExpired(createdAt: Long): Boolean = now() - createdAt > ttlMillis

    private fun targetChanged(detail: String): PhoneAgentError = PhoneAgentError(
        "stale_handle",
        "The target node changed ($detail). Call phone_agent_tree with offset 0.",
    )

    private fun clearTreeLocked() {
        val observation = tree ?: return
        for (index in 0 until observation.handleCount) {
            runCatching { observation.handleAt(index).recycle() }
        }
        tree = null
    }

    companion object {
        const val DEFAULT_TTL_MILLIS = 120_000L
    }
}
