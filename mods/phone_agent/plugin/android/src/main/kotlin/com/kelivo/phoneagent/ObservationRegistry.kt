package com.kelivo.phoneagent

/** 当前前台窗口的稳定标识，用于失效判断。 */
internal data class WindowState(
    val windowId: Int,
    val packageName: String?,
    val width: Int,
    val height: Int,
    val rotation: Int,
)

internal data class ScreenshotObservation(
    val imageWidth: Int,
    val imageHeight: Int,
    val screenWidth: Int,
    val screenHeight: Int,
    val windowId: Int,
    val packageName: String?,
    val rotation: Int,
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
 * 窗口、包名、尺寸或旋转变化会让树和截图失效。
 */
internal class ObservationRegistry(
    private val ttlMillis: Long = DEFAULT_TTL_MILLIS,
    private val now: () -> Long,
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
        val node = observation.handles[index]
        if (!node.refresh() || !node.isVisibleToUser || !node.isEnabled) {
            throw PhoneAgentError(
                "stale_handle",
                "The target node changed. Call phone_agent_tree with offset 0.",
            )
        }
        val current = node.fingerprint()
        if (current != observation.fingerprints[index]) {
            val changed = fingerprintDiff(observation.fingerprints[index], current)
            throw PhoneAgentError(
                "stale_handle",
                "The target node changed (${changed.joinToString(", ")}). " +
                    "Call phone_agent_tree with offset 0.",
            )
        }
        return SavedHandle(
            id = nodeId,
            node = node,
            fingerprint = observation.fingerprints[index],
            record = observation.records[index],
        )
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

    private fun clearTreeLocked() {
        tree?.handles?.forEach { handle ->
            runCatching { handle.recycle() }
        }
        tree = null
    }

    companion object {
        const val DEFAULT_TTL_MILLIS = 120_000L
    }
}
