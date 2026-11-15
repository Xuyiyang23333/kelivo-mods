package com.kelivo.phoneagent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AppWhitelistTest {
    private val hashA = "a".repeat(64)
    private val hashB = "b".repeat(64)
    private val hashC = "c".repeat(64)

    private val resolvable = mutableMapOf<String, List<String>>()
    private val storage = InMemoryWhitelistStorage()
    private val store = WhitelistStore(storage)
    private val approvals = AppApprovals(
        resolver = SigningResolver { packageName ->
            resolvable[packageName]?.let {
                SigningIdentity(packageName, SigningIdentity.normalizeSha256(it), "Display")
            }
        },
        store = store,
    )

    private fun register(packageName: String, vararg hashes: String) {
        resolvable[packageName] = hashes.toList()
    }

    @Test
    fun `an approved app matches both package and signing certificate`() {
        register("com.example.app", hashA)
        val outcome = approvals.approve("com.example.app", now = 10L, sourceAssistantId = "a1")

        assertTrue(outcome.approved)
        assertTrue(approvals.decide("com.example.app") is ApprovalDecision.Approved)
        assertEquals("aaaaaaaa", store.find("com.example.app")?.signingPrefix)
    }

    @Test
    fun `a package that was never approved requires approval`() {
        register("com.example.app", hashA)

        val decision = approvals.decide("com.example.app")

        assertTrue(decision is ApprovalDecision.Required)
        val required = decision as ApprovalDecision.Required
        assertEquals("com.example.app", required.packageName)
        assertEquals(listOf(hashA), required.identity?.sha256Values)
    }

    @Test
    fun `a signing certificate change requires approval again`() {
        register("com.example.app", hashA)
        approvals.approve("com.example.app", now = 10L, sourceAssistantId = null)

        register("com.example.app", hashB)

        val required = approvals.decide("com.example.app") as ApprovalDecision.Required
        assertEquals(listOf(hashB), required.identity?.sha256Values)
        assertEquals("bbbbbbbb", required.identity?.signingPrefix)
    }

    @Test
    fun `an unresolvable signing certificate fails closed`() {
        register("com.example.app", hashA)
        approvals.approve("com.example.app", now = 10L, sourceAssistantId = null)

        resolvable.remove("com.example.app")

        val required = approvals.decide("com.example.app") as ApprovalDecision.Required
        assertNull(required.identity)
    }

    @Test
    fun `approving an unresolvable package writes nothing`() {
        val outcome = approvals.approve("com.example.app", now = 10L, sourceAssistantId = null)

        assertFalse(outcome.approved)
        assertEquals(ApproveResult.REASON_SIGNING_UNAVAILABLE, outcome.reason)
        assertNull(store.find("com.example.app"))
        assertTrue(store.all().isEmpty())
    }

    @Test
    fun `approving is idempotent and keeps the first source`() {
        register("com.example.app", hashA)

        approvals.approve("com.example.app", now = 10L, sourceAssistantId = "first")
        approvals.approve("com.example.app", now = 20L, sourceAssistantId = "second")

        val entries = store.all()
        assertEquals(1, entries.size)
        val entry = entries.single()
        assertEquals(10L, entry.approvedAtMillis)
        assertEquals(20L, entry.lastApprovedAtMillis)
        assertEquals("first", entry.sourceAssistantId)
    }

    @Test
    fun `approving again after a signing change replaces the record`() {
        register("com.example.app", hashA)
        approvals.approve("com.example.app", now = 10L, sourceAssistantId = "first")

        register("com.example.app", hashB)
        assertEquals(
            ApproveResult.REASON_SIGNING_MISMATCH,
            approvals.approve(
                "com.example.app",
                now = 20L,
                sourceAssistantId = "second",
                expectedSha256Values = listOf(hashA),
            ).reason,
        )
        assertEquals(listOf(hashA), store.find("com.example.app")?.signingSha256Values)

        val accepted = approvals.approve(
            "com.example.app",
            now = 30L,
            sourceAssistantId = "second",
            expectedSha256Values = listOf(hashB),
        )
        assertTrue(accepted.approved)
        assertEquals(listOf(hashB), store.find("com.example.app")?.signingSha256Values)
        assertEquals(30L, store.find("com.example.app")?.approvedAtMillis)
        assertEquals(1, store.all().size)
    }

    @Test
    fun `a late approval whose certificate changed writes nothing`() {
        register("com.example.app", hashA)
        register("com.example.app", hashB)

        val outcome = approvals.approve(
            "com.example.app",
            now = 10L,
            sourceAssistantId = null,
            expectedSha256Values = listOf(hashA),
        )

        assertFalse(outcome.approved)
        assertEquals(ApproveResult.REASON_SIGNING_MISMATCH, outcome.reason)
        assertTrue(store.all().isEmpty())
    }

    @Test
    fun `revoking takes effect immediately`() {
        register("com.example.app", hashA)
        approvals.approve("com.example.app", now = 10L, sourceAssistantId = null)
        assertTrue(approvals.decide("com.example.app") is ApprovalDecision.Approved)

        assertTrue(approvals.revoke("com.example.app"))

        assertTrue(approvals.decide("com.example.app") is ApprovalDecision.Required)
        assertFalse(approvals.revoke("com.example.app"))
    }

    @Test
    fun `a multi signer package must match the whole certificate set`() {
        register("com.example.multi", hashA, hashB)
        approvals.approve("com.example.multi", now = 10L, sourceAssistantId = null)
        assertTrue(approvals.decide("com.example.multi") is ApprovalDecision.Approved)

        register("com.example.multi", hashA, hashB, hashC)
        assertTrue(approvals.decide("com.example.multi") is ApprovalDecision.Required)

        register("com.example.multi", hashB, hashA)
        assertTrue(approvals.decide("com.example.multi") is ApprovalDecision.Approved)
    }

    @Test
    fun `signing hashes are normalized before comparison`() {
        assertEquals(listOf(hashA, hashB), SigningIdentity.normalizeSha256(listOf(" $hashB ", hashA, hashA, "")))
        assertTrue(SigningIdentity.normalizeSha256(listOf("not-a-hash", hashA.take(63))).isEmpty())
    }

    @Test
    fun `the whitelist survives a new store instance`() {
        register("com.example.app", hashA)
        approvals.approve("com.example.app", now = 10L, sourceAssistantId = "a1")

        val reloaded = WhitelistStore(storage)

        val entry = reloaded.find("com.example.app")
        assertNotNull(entry)
        assertEquals(listOf(hashA), entry?.signingSha256Values)
        assertEquals("a1", entry?.sourceAssistantId)
    }

    @Test
    fun `a malformed whitelist line is ignored rather than trusted`() {
        val corrupt = InMemoryWhitelistStorage(
            listOf(
                WhitelistStore.HEADER,
                "com.example.app\tnot-a-hash\t1\t1\ta1",
                "com.example.app2\t$hashA\tnot-a-time\t1\ta1",
                "com.example.app3\t$hashA\t5\t5\ta1",
            ).joinToString("\n"),
        )

        val entries = WhitelistStore(corrupt).all()

        assertEquals(listOf("com.example.app3"), entries.map { it.packageName })
    }

    @Test
    fun `the whitelist is global and shared across every reader`() {
        register("com.example.app", hashA)
        approvals.approve("com.example.app", now = 10L, sourceAssistantId = "assistant-a")

        val otherAssistantView = AppApprovals(
            resolver = SigningResolver { packageName ->
                resolvable[packageName]?.let { SigningIdentity(packageName, it, null) }
            },
            store = WhitelistStore(storage),
        )

        assertTrue(otherAssistantView.decide("com.example.app") is ApprovalDecision.Approved)
        assertEquals(
            "assistant-a",
            otherAssistantView.approvedApps().single().sourceAssistantId,
        )
    }

    @Test
    fun `the test package is the only default pre approval`() {
        assertEquals(setOf(TEST_PACKAGE), buildPreApprovedPackages(debuggable = false))
        assertEquals(
            setOf(TEST_PACKAGE, "com.kelivo.phoneagent.securefixture"),
            buildPreApprovedPackages(debuggable = true),
        )
    }

    @Test
    fun `the build deny list starts empty and never borrows the hard baseline`() {
        assertTrue(DENY_PACKAGES.isEmpty())
        HARD_BASELINE_PACKAGES.forEach { packageName ->
            assertFalse(packageName, packageName in DENY_PACKAGES)
        }
    }
}
