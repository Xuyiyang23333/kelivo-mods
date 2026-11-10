package com.kelivo.phoneagent

internal class FakeNode(
    override var windowId: Int = 1,
    override var packageName: String? = "com.psyche.kelivo",
    override var className: String? = "android.widget.TextView",
    override var viewId: String? = null,
    override var text: String? = null,
    override var contentDescription: String? = null,
    override var hintText: String? = null,
    override var stateDescription: String? = null,
    override var isPassword: Boolean = false,
    override var isVisibleToUser: Boolean = true,
    override var isEnabled: Boolean = true,
    override var isFocused: Boolean = false,
    override var isSelected: Boolean = false,
    override var isClickable: Boolean = false,
    override var isLongClickable: Boolean = false,
    override var isEditable: Boolean = false,
    override var isScrollable: Boolean = false,
    override var isCheckable: Boolean = false,
    override var isChecked: Boolean = false,
    override var bounds: Bounds = Bounds(0, 0, 100, 100),
    override var actions: Set<NodeAction> = emptySet(),
) : PhoneNode {
    val children = mutableListOf<PhoneNode>()
    var refreshResult = true
    var performResult = true
    var recycleCount = 0
    var failOnChildCount = false
    val performed = mutableListOf<NodeAction>()

    override val childCount: Int
        get() {
            if (failOnChildCount) throw IllegalStateException("childCount failed")
            return children.size
        }

    override fun child(index: Int): PhoneNode? = children.getOrNull(index)

    override fun duplicate(): PhoneNode = this

    override fun refresh(): Boolean = refreshResult

    override fun perform(action: NodeAction, text: String?): Boolean {
        performed += action
        return performResult
    }

    override fun recycle() {
        recycleCount++
    }
}
