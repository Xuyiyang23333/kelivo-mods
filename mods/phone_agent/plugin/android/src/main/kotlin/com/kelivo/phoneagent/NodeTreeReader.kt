package com.kelivo.phoneagent

/** 一个被发出的节点快照。密码节点的文本字段始终为空。 */
internal data class NodeRecord(
    val id: String,
    val parentId: String?,
    val bounds: Bounds,
    val className: String,
    val text: String?,
    val description: String?,
    val hint: String?,
    val stateDescription: String?,
    val viewId: String?,
    val enabled: Boolean,
    val clickable: Boolean,
    val longClickable: Boolean,
    val editable: Boolean,
    val supportsSetText: Boolean,
    val scrollable: Boolean,
    val checkable: Boolean,
    val checked: Boolean,
    val focused: Boolean,
    val selected: Boolean,
    val password: Boolean,
)

/** 一次完整读树的原生结果。分页只切片，不重新遍历。 */
internal data class TreeObservation(
    val records: List<NodeRecord>,
    val handles: List<PhoneNode>,
    val fingerprints: List<String>,
    val truncated: Boolean,
    val textTruncated: Boolean,
    val windowId: Int,
    val packageName: String?,
    val screenWidth: Int,
    val screenHeight: Int,
    val rotation: Int,
    val createdAt: Long,
)

/**
 * 有界 DFS。节点总数、访问数、深度和文本长度都有上限；
 * 密码节点不输出文本，也不遍历其子树。
 */
internal class NodeTreeReader(
    private val maxVisited: Int = 2500,
    private val maxNodes: Int = 1000,
    private val maxDepth: Int = 40,
    private val textBudget: Int = 32000,
    private val maxLabelLength: Int = 1000,
) {
    fun read(
        root: PhoneNode,
        windowId: Int,
        packageName: String?,
        screenWidth: Int,
        screenHeight: Int,
        rotation: Int,
        createdAt: Long,
        interactiveOnly: Boolean,
    ): TreeObservation {
        val records = mutableListOf<NodeRecord>()
        val handles = mutableListOf<PhoneNode>()
        val fingerprints = mutableListOf<String>()
        var visited = 0
        var remainingText = textBudget
        var truncated = false
        var textTruncated = false

        fun label(value: String?): String? {
            if (value.isNullOrEmpty()) return null
            val limit = minOf(maxLabelLength, remainingText)
            if (limit <= 0) {
                textTruncated = true
                return null
            }
            val result = value.take(limit)
            remainingText -= result.length
            if (result.length < value.length) textTruncated = true
            return result
        }

        fun visit(node: PhoneNode, depth: Int, parentId: String?) {
            try {
                if (visited >= maxVisited || records.size >= maxNodes || depth > maxDepth) {
                    truncated = true
                    return
                }
                visited++
                val bounds = node.bounds
                val visible = node.isVisibleToUser &&
                    bounds.intersects(screenWidth, screenHeight)
                var nextParent = parentId
                if (visible && shouldEmit(node, depth, interactiveOnly)) {
                    val id = "n${records.size}"
                    val password = node.isPassword
                    records += NodeRecord(
                        id = id,
                        parentId = parentId,
                        bounds = bounds,
                        className = node.className.orEmpty(),
                        text = if (password) null else label(node.text),
                        description = if (password) null else label(node.contentDescription),
                        hint = if (password) null else label(node.hintText),
                        stateDescription = if (password) null else label(node.stateDescription),
                        viewId = node.viewId,
                        enabled = node.isEnabled,
                        clickable = node.isClickable,
                        longClickable = node.isLongClickable,
                        editable = node.isEditable,
                        supportsSetText = node.actions.contains(NodeAction.SET_TEXT),
                        scrollable = node.isScrollable,
                        checkable = node.isCheckable,
                        checked = node.isChecked,
                        focused = node.isFocused,
                        selected = node.isSelected,
                        password = password,
                    )
                    handles += node.duplicate()
                    fingerprints += node.fingerprint()
                    nextParent = id
                }
                if (!node.isPassword) {
                    for (index in 0 until node.childCount) {
                        if (visited >= maxVisited || records.size >= maxNodes) {
                            truncated = true
                            break
                        }
                        val child = node.child(index) ?: continue
                        visit(child, depth + 1, nextParent)
                    }
                }
            } finally {
                node.recycle()
            }
        }

        visit(root, 0, null)
        return TreeObservation(
            records = records,
            handles = handles,
            fingerprints = fingerprints,
            truncated = truncated,
            textTruncated = textTruncated,
            windowId = windowId,
            packageName = packageName,
            screenWidth = screenWidth,
            screenHeight = screenHeight,
            rotation = rotation,
            createdAt = createdAt,
        )
    }

    private fun shouldEmit(
        node: PhoneNode,
        depth: Int,
        interactiveOnly: Boolean,
    ): Boolean {
        if (depth == 0) return true
        val actionable = node.isClickable || node.isLongClickable ||
            node.isEditable || node.isScrollable || node.isCheckable
        if (interactiveOnly) return actionable
        return actionable || !node.text.isNullOrEmpty() ||
            !node.contentDescription.isNullOrEmpty()
    }
}
