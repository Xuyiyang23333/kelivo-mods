package com.kelivo.phoneagent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AuditRecorderTest {
    @Test
    fun `only audited channel methods produce an action`() {
        assertEquals("readTree", AuditAction.forCall("readTree", null))
        assertEquals("screenshot", AuditAction.forCall("screenshot", null))
        assertNull(AuditAction.forCall("clearScreenshot", null))
        assertNull(AuditAction.forCall("status", null))
        assertNull(AuditAction.forCall("approvedApps", null))
        assertNull(AuditAction.forCall("approveApp", mapOf("package_name" to "com.example.app")))
        assertNull(AuditAction.forCall("revokeApp", mapOf("package_name" to "com.example.app")))
    }

    /**
     * 输入动作只保留固定 token：`set_text` 的文本、坐标、节点 id 都在 action 里
     * 无处落脚，这是“不记输入文本/坐标”的结构性保证。
     */
    @Test
    fun `input actions collapse to fixed tokens regardless of arguments`() {
        val arguments = mapOf<String, Any?>(
            "action" to "set_text",
            "node_id" to "n3",
            "text" to "secret password",
            "x" to 0.25,
            "y" to 0.75,
        )

        val action = AuditAction.forCall("input", arguments)

        assertEquals("input.set_text", action)
        assertFalse(action!!.contains("secret"))
        assertFalse(action.contains("n3"))
        assertFalse(action.contains("0.25"))
    }

    @Test
    fun `every documented input action has a token and unknown actions fall back`() {
        for (action in listOf("tap", "long_press", "set_text", "scroll", "swipe", "back", "home", "recents")) {
            assertEquals("input.$action", AuditAction.forCall("input", mapOf("action" to action)))
        }
        assertEquals("input", AuditAction.forCall("input", mapOf("action" to "explode")))
        assertEquals("input", AuditAction.forCall("input", mapOf("action" to 42)))
        assertEquals("input", AuditAction.forCall("input", null))
    }

    @Test
    fun `audit identity never throws on malformed values`() {
        assertEquals("a1" to "c1", AuditIdentity.from(
            mapOf("assistant_id" to " a1 ", "conversation_id" to "c1"),
        ))
        assertEquals(null to null, AuditIdentity.from(null))
        assertEquals(null to null, AuditIdentity.from(mapOf<String, Any?>()))
        assertEquals(null to null, AuditIdentity.from(mapOf("assistant_id" to 42)))
        assertEquals(null to null, AuditIdentity.from(mapOf("assistant_id" to "   ")))
    }

    @Test
    fun `the built record carries only context metadata`() {
        val context = AuditContext("input.tap").apply {
            assistantId = "a1"
            conversationId = "c1"
            packageName = "com.example.app"
        }

        val record = AuditRecorder.build(context, "ok", 1_000L) { "aaaaaaaa" }

        assertEquals(
            AuditRecord(
                occurredAtMillis = 1_000L,
                assistantId = "a1",
                conversationId = "c1",
                packageName = "com.example.app",
                signingPrefix = "aaaaaaaa",
                action = "input.tap",
                resultCode = "ok",
            ),
            record,
        )
    }

    @Test
    fun `a failed call keeps its structured error code`() {
        val context = AuditContext("readTree").apply { packageName = "com.android.systemui" }

        val record = AuditRecorder.build(context, "system_window_denied", 1L) { "aaaaaaaa" }

        assertEquals("system_window_denied", record.resultCode)
    }

    @Test
    fun `a blank result code falls back to ok`() {
        val record = AuditRecorder.build(AuditContext("screenshot"), "  ", 1L) { null }

        assertEquals(AUDIT_OK, record.resultCode)
    }

    @Test
    fun `an unknown package records no signing prefix`() {
        val record = AuditRecorder.build(AuditContext("readTree"), "no_window", 1L) { "aaaaaaaa" }

        assertNull(record.packageName)
        assertNull(record.signingPrefix)
    }

    /**
     * 签名解析抛异常时该字段记 null，记录仍写成功——审计缺项不能升级成工具失败。
     */
    @Test
    fun `a throwing signing resolver degrades to a null prefix without failing the write`() {
        val storage = InMemoryAuditStorage()
        val log = AuditLog(storage)
        val context = AuditContext("screenshot").apply { packageName = "com.example.app" }

        val written = log.recordSafely(context, "ok", 1_000L) {
            throw IllegalStateException("PackageManager unavailable")
        }

        assertTrue(written)
        assertEquals(0, log.droppedWrites)
        val entry = log.entries().single()
        assertNull(entry.signingPrefix)
        assertEquals("com.example.app", entry.packageName)
        assertEquals("ok", entry.resultCode)
    }

    @Test
    fun `a failing audit storage never surfaces to the caller`() {
        val log = AuditLog(
            object : AuditStorage {
                override fun read(): String = ""

                override fun write(value: String) {
                    throw IllegalStateException("read-only storage")
                }
            },
        )

        assertFalse(log.recordSafely(AuditContext("readTree"), "ok", 1_000L) { "aaaaaaaa" })
        assertEquals(1, log.droppedWrites)
    }
}
