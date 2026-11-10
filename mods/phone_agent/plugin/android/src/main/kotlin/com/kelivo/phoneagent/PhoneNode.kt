package com.kelivo.phoneagent

import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.view.accessibility.AccessibilityNodeInfo

/** 与 Android 无关的屏幕矩形，便于纯 JVM 测试。 */
internal data class Bounds(
    val left: Int,
    val top: Int,
    val right: Int,
    val bottom: Int,
) {
    fun intersects(width: Int, height: Int): Boolean =
        right > 0 && bottom > 0 && left < width && top < height
}

internal enum class NodeAction {
    CLICK,
    LONG_CLICK,
    SET_TEXT,
    SCROLL_FORWARD,
    SCROLL_BACKWARD,
    SCROLL_UP,
    SCROLL_DOWN,
    SCROLL_LEFT,
    SCROLL_RIGHT,
    ;

    companion object {
        fun fromScrollDirection(direction: String): NodeAction = when (direction) {
            "forward" -> SCROLL_FORWARD
            "backward" -> SCROLL_BACKWARD
            "up" -> SCROLL_UP
            "down" -> SCROLL_DOWN
            "left" -> SCROLL_LEFT
            "right" -> SCROLL_RIGHT
            else -> throw PhoneAgentError(
                "invalid_argument",
                "direction must be one of forward, backward, up, down, left or right.",
            )
        }
    }
}

internal enum class GestureAction(val wireName: String) {
    TAP("tap"),
    LONG_PRESS("long_press"),
    SWIPE("swipe"),
}

internal enum class SystemAction(val wireName: String) {
    BACK("back"),
    HOME("home"),
    RECENTS("recents"),
    ;

    companion object {
        fun fromWire(value: String): SystemAction = when (value) {
            "back" -> BACK
            "home" -> HOME
            "recents" -> RECENTS
            else -> throw PhoneAgentError("invalid_argument", "Unknown system action: $value")
        }
    }
}

/**
 * 无障碍节点的最小抽象。生产实现包装 [AccessibilityNodeInfo]，
 * 测试实现不依赖 Android 运行时。
 */
internal interface PhoneNode {
    val windowId: Int
    val packageName: String?
    val className: String?
    val viewId: String?
    val text: String?
    val contentDescription: String?
    val hintText: String?
    val stateDescription: String?
    val isPassword: Boolean
    val isVisibleToUser: Boolean
    val isEnabled: Boolean
    val isFocused: Boolean
    val isSelected: Boolean
    val isClickable: Boolean
    val isLongClickable: Boolean
    val isEditable: Boolean
    val isScrollable: Boolean
    val isCheckable: Boolean
    val isChecked: Boolean
    val bounds: Bounds
    val actions: Set<NodeAction>
    val childCount: Int

    fun child(index: Int): PhoneNode?
    fun duplicate(): PhoneNode
    fun refresh(): Boolean
    fun perform(action: NodeAction, text: String? = null): Boolean
    fun recycle()
}

internal class AndroidPhoneNode(
    private val node: AccessibilityNodeInfo,
) : PhoneNode {
    override val windowId: Int get() = node.windowId
    override val packageName: String? get() = node.packageName?.toString()
    override val className: String? get() = node.className?.toString()
    override val viewId: String? get() = node.viewIdResourceName
    override val text: String? get() = node.text?.toString()
    override val contentDescription: String? get() = node.contentDescription?.toString()
    override val hintText: String?
        get() = if (Build.VERSION.SDK_INT >= 26) node.hintText?.toString() else null
    override val stateDescription: String?
        get() = if (Build.VERSION.SDK_INT >= 30) node.stateDescription?.toString() else null
    override val isPassword: Boolean get() = node.isPassword
    override val isVisibleToUser: Boolean get() = node.isVisibleToUser
    override val isEnabled: Boolean get() = node.isEnabled
    override val isFocused: Boolean get() = node.isFocused
    override val isSelected: Boolean get() = node.isSelected
    override val isClickable: Boolean get() = node.isClickable
    override val isLongClickable: Boolean get() = node.isLongClickable
    override val isEditable: Boolean get() = node.isEditable
    override val isScrollable: Boolean get() = node.isScrollable
    override val isCheckable: Boolean get() = node.isCheckable
    override val isChecked: Boolean get() = node.isChecked
    override val childCount: Int get() = node.childCount

    override val bounds: Bounds
        get() {
            val rect = Rect()
            node.getBoundsInScreen(rect)
            return Bounds(rect.left, rect.top, rect.right, rect.bottom)
        }

    override val actions: Set<NodeAction>
        get() {
            val ids = node.actionList.mapTo(HashSet()) { it.id }
            val result = HashSet<NodeAction>()
            if (AccessibilityNodeInfo.ACTION_CLICK in ids) result += NodeAction.CLICK
            if (AccessibilityNodeInfo.ACTION_LONG_CLICK in ids) {
                result += NodeAction.LONG_CLICK
            }
            if (AccessibilityNodeInfo.ACTION_SET_TEXT in ids) result += NodeAction.SET_TEXT
            if (AccessibilityNodeInfo.ACTION_SCROLL_FORWARD in ids) {
                result += NodeAction.SCROLL_FORWARD
            }
            if (AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD in ids) {
                result += NodeAction.SCROLL_BACKWARD
            }
            if (AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_UP.id in ids) {
                result += NodeAction.SCROLL_UP
            }
            if (AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_DOWN.id in ids) {
                result += NodeAction.SCROLL_DOWN
            }
            if (AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_LEFT.id in ids) {
                result += NodeAction.SCROLL_LEFT
            }
            if (AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_RIGHT.id in ids) {
                result += NodeAction.SCROLL_RIGHT
            }
            return result
        }

    override fun child(index: Int): PhoneNode? =
        node.getChild(index)?.let(::AndroidPhoneNode)

    override fun duplicate(): PhoneNode =
        AndroidPhoneNode(AccessibilityNodeInfo.obtain(node))

    override fun refresh(): Boolean = node.refresh()

    override fun perform(action: NodeAction, text: String?): Boolean {
        val arguments = if (action == NodeAction.SET_TEXT) {
            Bundle().apply {
                putCharSequence(
                    AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                    text ?: "",
                )
            }
        } else {
            null
        }
        val actionId = when (action) {
            NodeAction.CLICK -> AccessibilityNodeInfo.ACTION_CLICK
            NodeAction.LONG_CLICK -> AccessibilityNodeInfo.ACTION_LONG_CLICK
            NodeAction.SET_TEXT -> AccessibilityNodeInfo.ACTION_SET_TEXT
            NodeAction.SCROLL_FORWARD -> AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            NodeAction.SCROLL_BACKWARD -> AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
            NodeAction.SCROLL_UP -> AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_UP.id
            NodeAction.SCROLL_DOWN -> AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_DOWN.id
            NodeAction.SCROLL_LEFT -> AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_LEFT.id
            NodeAction.SCROLL_RIGHT -> AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_RIGHT.id
        }
        return node.performAction(actionId, arguments)
    }

    override fun recycle() {
        node.recycle()
    }
}

/**
 * 目标节点指纹。不包含 bounds、焦点状态和动作集合，允许布局漂移、焦点变化
 * 和聚焦引起的动作增减，但拒绝内容、稳定能力或选中状态变化。
 * 动作可用性由执行层在动作前按当前节点重新校验。
 */
internal data class NodeFingerprint(val fields: List<Pair<String, String>>)

internal fun PhoneNode.fingerprint(): NodeFingerprint = NodeFingerprint(fingerprintFields())

/** 指纹字段；只用于比较和报告变化字段名，不输出内容。 */
internal fun PhoneNode.fingerprintFields(): List<Pair<String, String>> {
    val fields = mutableListOf<Pair<String, String>>()
    fun add(name: String, value: Any?) {
        fields += name to value.toString()
    }
    add("windowId", windowId)
    add("packageName", packageName)
    add("className", className)
    add("viewId", viewId)
    if (!isPassword) {
        add("text", text)
        add("contentDescription", contentDescription)
        add("hintText", hintText)
        add("stateDescription", stateDescription)
    }
    add("isCheckable", isCheckable)
    add("isChecked", isChecked)
    add("isSelected", isSelected)
    add("isEnabled", isEnabled)
    add("isPassword", isPassword)
    add("isEditable", isEditable)
    add("isClickable", isClickable)
    add("isLongClickable", isLongClickable)
    add("isScrollable", isScrollable)
    return fields
}

/**
 * 返回两个结构化指纹中发生变化的字段名，便于诊断。
 * 字段名来自固定定义，值只参与相等比较，不会被反解为字段名。
 */
internal fun fingerprintDiff(expected: NodeFingerprint, actual: NodeFingerprint): List<String> {
    val left = expected.fields.toMap()
    val right = actual.fields.toMap()
    return (left.keys + right.keys).filter { left[it] != right[it] }.sorted()
}
