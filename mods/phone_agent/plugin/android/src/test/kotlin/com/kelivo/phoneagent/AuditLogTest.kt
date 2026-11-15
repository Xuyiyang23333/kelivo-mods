package com.kelivo.phoneagent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AuditLogTest {
    private val day = 24L * 60 * 60 * 1000

    private fun record(
        at: Long,
        packageName: String? = "com.example.app",
        action: String = "readTree",
        resultCode: String = AUDIT_OK,
    ) = AuditRecord(
        occurredAtMillis = at,
        assistantId = "assistant-a",
        conversationId = "conversation-1",
        packageName = packageName,
        signingPrefix = "aaaaaaaa",
        action = action,
        resultCode = resultCode,
    )

    /**
     * 字段集合必须精确正好是契约里的七项：多一项就是扩大外发与推断面，
     * 少一项就无法审计。禁用字段逐个断言不存在。
     */
    @Test
    fun `the record keeps exactly the seven contract fields`() {
        assertEquals(
            setOf(
                "occurredAtMillis",
                "assistantId",
                "conversationId",
                "packageName",
                "signingPrefix",
                "action",
                "resultCode",
            ),
            AuditRecord.FIELD_NAMES.toSet(),
        )
        assertEquals(7, AuditRecord.FIELD_NAMES.size)

        val properties = AuditRecord::class.java.declaredFields
            .filterNot { it.isSynthetic || java.lang.reflect.Modifier.isStatic(it.modifiers) }
            .map { it.name }
            .toSet()
        assertEquals(AuditRecord.FIELD_NAMES.toSet(), properties)

        val forbidden = listOf(
            "text",
            "inputText",
            "password",
            "screenshot",
            "imageBytes",
            "summary",
            "screenSummary",
            "x",
            "y",
            "endX",
            "endY",
            "coordinates",
            "windowTitle",
        )
        for (name in forbidden) {
            assertFalse("$name must not be an audit field", name in properties)
        }
    }

    @Test
    fun `the persisted header declares exactly seven columns`() {
        val storage = InMemoryAuditStorage()
        val log = AuditLog(storage)

        log.record(record(1_000L))

        val lines = storage.read().trim().lines()
        assertEquals(AuditRecord.HEADER, lines.first())
        assertEquals(7, lines[1].split('\t').size)
    }

    @Test
    fun `a record round trips through storage without extra columns`() {
        val storage = InMemoryAuditStorage()
        val log = AuditLog(storage)
        val original = record(5_000L, action = "input.set_text", resultCode = "permission_required")

        log.record(original)

        val reloaded = AuditLog(storage)
        assertEquals(listOf(original), reloaded.entries())
    }

    @Test
    fun `a missing identity is persisted as an empty column and read back as null`() {
        val storage = InMemoryAuditStorage()
        val log = AuditLog(storage)

        log.record(
            AuditRecord(
                occurredAtMillis = 1_000L,
                assistantId = null,
                conversationId = null,
                packageName = null,
                signingPrefix = null,
                action = "screenshot",
                resultCode = "no_window",
            ),
        )

        val entries = AuditLog(storage).entries()
        assertEquals(1, entries.size)
        assertNull(entries.first().assistantId)
        assertNull(entries.first().conversationId)
        assertNull(entries.first().packageName)
        assertNull(entries.first().signingPrefix)
    }

    @Test
    fun `records older than thirty days are dropped first`() {
        val now = 100 * day
        val log = AuditLog(InMemoryAuditStorage())

        log.record(record(now - 31 * day), now = now)
        log.record(record(now - 29 * day), now = now)

        val entries = log.entries()
        assertEquals(1, entries.size)
        assertEquals(now - 29 * day, entries.first().occurredAtMillis)
    }

    @Test
    fun `a record exactly thirty days old is still retained`() {
        val now = 100 * day
        val log = AuditLog(InMemoryAuditStorage())

        log.record(record(now - 30 * day), now = now)

        assertEquals(1, log.entries().size)
    }

    @Test
    fun `at most the most recent two thousand records are kept`() {
        val storage = InMemoryAuditStorage()
        val log = AuditLog(storage)
        val base = 10 * day

        for (index in 0 until 2_005) {
            log.record(record(base + index), now = base + index)
        }

        val entries = log.entries()
        assertEquals(AuditLog.MAX_ENTRIES, entries.size)
        assertEquals(base + 5, entries.first().occurredAtMillis)
        assertEquals(base + 2_004, entries.last().occurredAtMillis)
    }

    @Test
    fun `the retention window wins when both limits apply`() {
        val now = 400 * day
        val log = AuditLog(InMemoryAuditStorage())

        log.record(record(now - 40 * day), now = now)
        log.record(record(now - 20 * day), now = now)
        log.record(record(now - 1 * day), now = now)

        assertEquals(
            listOf(now - 20 * day, now - 1 * day),
            log.entries().map { it.occurredAtMillis },
        )
    }

    @Test
    fun `an oversized file is trimmed to the newest records on load`() {
        val storage = InMemoryAuditStorage()
        val seed = buildString {
            append(AuditRecord.HEADER)
            append('\n')
            for (index in 0 until 2_003) {
                append(1_000L + index)
                append("\ta\tc\tcom.example.app\taaaaaaaa\treadTree\tok\n")
            }
        }
        storage.write(seed)

        val log = AuditLog(storage)
        log.record(record(9_000L), now = 9_000L)

        val entries = log.entries()
        assertEquals(AuditLog.MAX_ENTRIES, entries.size)
        assertEquals(9_000L, entries.last().occurredAtMillis)
    }

    @Test
    fun `a write failure is reported locally and never thrown`() {
        val log = AuditLog(
            object : AuditStorage {
                override fun read(): String = ""

                override fun write(value: String) {
                    throw IllegalStateException("disk full")
                }
            },
        )

        assertFalse(log.record(record(1_000L)))
        assertEquals(1, log.droppedWrites)
    }

    @Test
    fun `a read failure starts from an empty log and a later write still succeeds`() {
        val writes = mutableListOf<String>()
        val log = AuditLog(
            object : AuditStorage {
                override fun read(): String = throw IllegalStateException("unreadable")

                override fun write(value: String) {
                    writes += value
                }
            },
        )

        assertTrue(log.record(record(1_000L)))
        assertEquals(0, log.droppedWrites)
        assertEquals(1, writes.size)
    }

    @Test
    fun `corrupted lines are dropped instead of trusted`() {
        val storage = InMemoryAuditStorage(
            buildString {
                append(AuditRecord.HEADER)
                append('\n')
                append("not-a-number\ta\tc\tp\tp\treadTree\tok\n")
                append("1000\ta\tc\tp\tp\treadTree\n")
                append("1000\ta\tc\tp\tp\t\tok\n")
                append("2000\ta\tc\tp\tp\treadTree\tok\n")
            },
        )

        val entries = AuditLog(storage).entries()

        assertEquals(1, entries.size)
        assertEquals(2_000L, entries.first().occurredAtMillis)
    }

    @Test
    fun `tabs and newlines inside a field cannot break the column count`() {
        val storage = InMemoryAuditStorage()
        val log = AuditLog(storage)

        log.record(
            record(1_000L).copy(
                assistantId = "a\tb",
                conversationId = "c\nd",
                packageName = "com.example\r\n.app",
            ),
        )

        val dataLine = storage.read().trim().lines()[1]
        assertEquals(7, dataLine.split('\t').size)
        assertEquals("ab", AuditLog(storage).entries().first().assistantId)
    }

    @Test
    fun `a field is truncated to the fixed field budget`() {
        val storage = InMemoryAuditStorage()
        val log = AuditLog(storage)

        log.record(record(1_000L).copy(packageName = "p".repeat(500)))

        val value = AuditLog(storage).entries().first().packageName
        assertEquals(AuditFields.MAX_FIELD_LENGTH, value?.length)
    }
}
