package com.kelivo.phoneagent

/** 原生结构化错误。错误码在 Dart 侧原样映射为 [PhoneAgentException.code]。 */
internal class PhoneAgentError(
    val code: String,
    override val message: String,
) : Exception(message)

internal object PhoneAgentArgs {
    fun string(args: Map<String, Any?>?, name: String): String {
        val value = args?.get(name)
        if (value !is String || value.isBlank()) {
            throw PhoneAgentError(
                "invalid_argument",
                "$name is required and must be a non-empty string.",
            )
        }
        return value
    }

    fun optionalString(args: Map<String, Any?>?, name: String): String? {
        if (args == null || !args.containsKey(name)) return null
        val value = args[name]
        if (value !is String || value.isBlank()) {
            throw PhoneAgentError(
                "invalid_argument",
                "$name must be a non-empty string when provided.",
            )
        }
        return value
    }

    fun text(args: Map<String, Any?>?, name: String): String {
        val value = args?.get(name)
        if (value !is String) {
            throw PhoneAgentError("invalid_argument", "$name must be a string.")
        }
        if (value.length > MAX_TEXT_LENGTH) {
            throw PhoneAgentError(
                "invalid_argument",
                "$name must be at most $MAX_TEXT_LENGTH characters.",
            )
        }
        return value
    }

    fun int(
        args: Map<String, Any?>?,
        name: String,
        default: Int,
        min: Int,
        max: Int,
    ): Int {
        if (args == null || !args.containsKey(name)) return default
        val number = args[name] as? Number
            ?: throw PhoneAgentError("invalid_argument", "$name must be an integer.")
        val value = number.toInt()
        if (number.toDouble() != value.toDouble() || value < min || value > max) {
            throw PhoneAgentError(
                "invalid_argument",
                "$name must be an integer between $min and $max.",
            )
        }
        return value
    }

    fun optionalLong(
        args: Map<String, Any?>?,
        name: String,
        min: Long,
        max: Long,
    ): Long? {
        if (args == null || !args.containsKey(name)) return null
        val number = args[name] as? Number
            ?: throw PhoneAgentError("invalid_argument", "$name must be a number.")
        val value = number.toLong()
        if (number.toDouble() != value.toDouble() || value < min || value > max) {
            throw PhoneAgentError(
                "invalid_argument",
                "$name must be between $min and $max.",
            )
        }
        return value
    }

    fun bool(args: Map<String, Any?>?, name: String, default: Boolean): Boolean {
        if (args == null || !args.containsKey(name)) return default
        return args[name] as? Boolean
            ?: throw PhoneAgentError("invalid_argument", "$name must be a boolean.")
    }

    fun normalized(args: Map<String, Any?>?, name: String): Double {
        val number = args?.get(name) as? Number
            ?: throw PhoneAgentError(
                "invalid_argument",
                "$name is required and must be a normalized coordinate between 0 and 1.",
            )
        return validateNormalized(number.toDouble(), name)
    }

    fun optionalNormalized(args: Map<String, Any?>?, name: String): Double? {
        if (args == null || !args.containsKey(name)) return null
        val number = args[name] as? Number
            ?: throw PhoneAgentError(
                "invalid_argument",
                "$name must be a normalized coordinate between 0 and 1.",
            )
        return validateNormalized(number.toDouble(), name)
    }

    private fun validateNormalized(value: Double, name: String): Double {
        if (!value.isFinite() || value < 0.0 || value > 1.0) {
            throw PhoneAgentError(
                "invalid_argument",
                "$name must be a normalized coordinate between 0 and 1.",
            )
        }
        return value
    }

    private const val MAX_TEXT_LENGTH = 10_000
}

internal object PhoneAgentResult {
    fun treePage(page: TreePage): Map<String, Any?> {
        val result = LinkedHashMap<String, Any?>()
        result["offset"] = page.offset
        result["next_offset"] = page.nextOffset
        result["total"] = page.total
        result["truncated"] = page.truncated
        result["text_truncated"] = page.textTruncated
        result["package_name"] = page.packageName
        result["width"] = page.screenWidth
        result["height"] = page.screenHeight
        result["nodes"] = page.records.map(::node)
        return result
    }

    fun node(record: NodeRecord): Map<String, Any?> {
        val item = LinkedHashMap<String, Any?>()
        item["node_id"] = record.id
        item["bounds"] = listOf(
            record.bounds.left,
            record.bounds.top,
            record.bounds.right,
            record.bounds.bottom,
        )
        item["class"] = record.className
        record.parentId?.let { item["parent_id"] = it }
        if (record.password) {
            item["password"] = true
        } else {
            record.text?.let { item["text"] = it }
            record.description?.let { item["description"] = it }
            record.hint?.let { item["hint"] = it }
            record.stateDescription?.let { item["state_description"] = it }
        }
        record.viewId?.let { item["resource_id"] = it }
        item["enabled"] = record.enabled
        if (record.clickable) item["clickable"] = true
        if (record.longClickable) item["long_clickable"] = true
        if (record.editable) {
            item["editable"] = true
            item["supports_set_text"] = record.supportsSetText
        }
        if (record.scrollable) item["scrollable"] = true
        if (record.checkable) {
            item["checkable"] = true
            item["checked"] = record.checked
        }
        if (record.focused) item["focused"] = true
        if (record.selected) item["selected"] = true
        return item
    }

    fun inputSuccess(action: String, message: String): Map<String, Any?> =
        linkedMapOf(
            "success" to true,
            "action" to action,
            "message" to message,
        )

    fun appsList(apps: List<Map<String, String>>): Map<String, Any?> =
        linkedMapOf("apps" to apps)

    fun openAppSuccess(packageName: String): Map<String, Any?> =
        linkedMapOf(
            "success" to true,
            "action" to "open_app",
            "package_name" to packageName,
            "message" to "Launched $packageName.",
        )

    fun waitSuccess(durationMs: Long): Map<String, Any?> =
        linkedMapOf(
            "success" to true,
            "action" to "wait",
            "duration_ms" to durationMs,
            "message" to "Waited ${durationMs}ms.",
        )

    fun screenshot(screenshot: CapturedScreenshot): Map<String, Any?> {
        val result = linkedMapOf<String, Any?>(
            "bytes" to screenshot.bytes,
            "imageWidth" to screenshot.imageWidth,
            "imageHeight" to screenshot.imageHeight,
            "screenWidth" to screenshot.screenWidth,
            "screenHeight" to screenshot.screenHeight,
            "packageName" to screenshot.packageName,
        )
        if (screenshot.recentTaps.isNotEmpty()) {
            result["recentTaps"] = screenshot.recentTaps.map { tap ->
                linkedMapOf(
                    "index" to tap.index,
                    "action" to tap.action,
                    "x" to tap.x,
                    "y" to tap.y,
                )
            }
        }
        return result
    }
}
