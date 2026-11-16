package com.kelivo.phoneagent

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ApprovalRequestsTest {
    private val hashA = "a".repeat(64)
    private val hashB = "b".repeat(64)

    private var now = 1_000L
    private var seq = 0

    private fun requests(ttlMillis: Long = ApprovalRequests.DEFAULT_TTL_MILLIS) =
        ApprovalRequests(
            nowMillis = { now },
            idFactory = { "r${++seq}" },
            ttlMillis = ttlMillis,
        )

    private fun approveAlways(record: ApprovalRequestRecord) =
        ApproveResult(true, null, WhitelistEntry(
            packageName = record.packageName,
            signingSha256Values = record.signingSha256Values,
            approvedAtMillis = now,
            lastApprovedAtMillis = now,
            sourceAssistantId = record.assistantId,
        ))

    @Test
    fun `a new request is pending and carries the full identity`() {
        val store = requests()
        val record = store.create("com.example.app", listOf(hashA), "Example", "t1", "c1", "a1")

        assertEquals(ApprovalRequestState.PENDING, record.state)
        assertEquals("com.example.app", record.packageName)
        assertEquals(listOf(hashA), record.signingSha256Values)
        assertEquals("aaaaaaaa", record.signingPrefix)
        assertEquals("Example", record.displayName)
        assertEquals("t1", record.toolCallId)
        assertEquals(1, store.pending().size)
    }

    @Test
    fun `an unresolvable identity is recorded as signing unavailable`() {
        val record = requests().create("com.example.app", emptyList(), null, null, null, null)

        assertTrue(record.signingUnavailable)
        assertEquals("", record.signingPrefix)
    }

    @Test
    fun `approving writes through and reaches a terminal state`() {
        val store = requests()
        val record = store.create("com.example.app", listOf(hashA), null, null, null, null)

        val resolution = store.resolve(record.id, approve = true, onApprove = ::approveAlways)

        assertEquals(ApprovalRequestState.APPROVED, resolution?.state)
        assertTrue(resolution?.approveResult?.approved == true)
        assertTrue(store.pending().isEmpty())
    }

    @Test
    fun `denying never calls the approve callback`() {
        val store = requests()
        val record = store.create("com.example.app", listOf(hashA), null, null, null, null)
        var called = 0

        val resolution = store.resolve(record.id, approve = false) {
            called++
            approveAlways(it)
        }

        assertEquals(0, called)
        assertEquals(ApprovalRequestState.DENIED, resolution?.state)
        assertNull(resolution?.approveResult)
    }

    @Test
    fun `a terminal request ignores later resolves without writing again`() {
        val store = requests()
        val record = store.create("com.example.app", listOf(hashA), null, null, null, null)
        store.resolve(record.id, approve = false) { approveAlways(it) }
        var writes = 0

        val late = store.resolve(record.id, approve = true) {
            writes++
            approveAlways(it)
        }

        assertEquals(0, writes)
        assertEquals(ApprovalRequestState.DENIED, late?.state)
    }

    @Test
    fun `a rejected approval records the failure reason and does not write`() {
        val store = requests()
        val record = store.create("com.example.app", listOf(hashA), null, null, null, null)

        val resolution = store.resolve(record.id, approve = true) {
            ApproveResult(false, ApproveResult.REASON_SIGNING_MISMATCH, null)
        }

        assertEquals(ApprovalRequestState.FAILED, resolution?.state)
        assertEquals(
            ApproveResult.REASON_SIGNING_MISMATCH,
            resolution?.request?.failureReason,
        )
    }

    @Test
    fun `a request expires after its ttl and never writes`() {
        val store = requests(ttlMillis = 100L)
        val record = store.create("com.example.app", listOf(hashA), null, null, null, null)
        now += 100L
        var writes = 0

        assertTrue(store.pending().isEmpty())
        val resolution = store.resolve(record.id, approve = true) {
            writes++
            approveAlways(it)
        }

        assertEquals(0, writes)
        assertEquals(ApprovalRequestState.EXPIRED, resolution?.state)
    }

    @Test
    fun `a newer request for the same target supersedes the pending one`() {
        val store = requests()
        val first = store.create("com.example.app", listOf(hashA), null, null, null, null)
        val second = store.create("com.example.app", listOf(hashA), null, null, null, null)

        assertEquals(ApprovalRequestState.SUPERSEDED, store.find(first.id)?.state)
        assertEquals(ApprovalRequestState.PENDING, store.find(second.id)?.state)
        assertEquals(1, store.pending().size)
    }

    @Test
    fun `a signing change does not supersede a request for the old signature`() {
        val store = requests()
        val first = store.create("com.example.app", listOf(hashA), null, null, null, null)
        store.create("com.example.app", listOf(hashB), null, null, null, null)

        assertEquals(ApprovalRequestState.PENDING, store.find(first.id)?.state)
    }

    @Test
    fun `dismissal is local cleanup, not a user denial`() {
        val store = requests()
        val record = store.create("com.example.app", listOf(hashA), null, null, "c1", null)

        assertEquals(listOf(record.id), store.dismissForConversation("c1"))
        assertEquals(ApprovalRequestState.DISMISSED, store.find(record.id)?.state)
        assertTrue(store.pending().isEmpty())
    }

    @Test
    fun `dismissing another conversation leaves this one pending`() {
        val store = requests()
        val record = store.create("com.example.app", listOf(hashA), null, null, "c1", null)

        assertTrue(store.dismissForConversation("c2").isEmpty())
        assertEquals(ApprovalRequestState.PENDING, store.find(record.id)?.state)
    }

    @Test
    fun `an unknown request id resolves to null`() {
        assertNull(requests().resolve("missing", approve = true) { approveAlways(it) })
    }

    @Test
    fun `terminal records are trimmed but pending ones are kept`() {
        val store = requests()
        val pending = store.create("com.example.pending", listOf(hashA), null, null, null, null)
        repeat(80) { index ->
            val record = store.create("com.example.$index", listOf(hashA), null, null, null, null)
            store.resolve(record.id, approve = false) { approveAlways(it) }
        }

        assertEquals(ApprovalRequestState.PENDING, store.find(pending.id)?.state)
        assertTrue(store.all().size <= ApprovalRequests.MAX_RETAINED + 1)
    }

    @Test
    fun `a pre-approved target is reported as such and writes nothing`() {
        val storage = InMemoryWhitelistStorage()
        val approvals = AppApprovals(
            resolver = SigningResolver { packageName ->
                SigningIdentity(packageName, listOf(hashA), null)
            },
            store = WhitelistStore(storage),
            preApprovedPackages = setOf(TEST_PACKAGE),
        )
        val store = requests()
        val record = store.create(TEST_PACKAGE, listOf(hashA), null, null, null, null)

        val resolution = store.resolve(record.id, approve = true) { entry ->
            approvals.approve(entry.packageName, now, entry.assistantId)
        }

        assertEquals(ApprovalRequestState.FAILED, resolution?.state)
        assertEquals(ApproveResult.REASON_PRE_APPROVED, resolution?.request?.failureReason)
        assertTrue(approvals.approvedApps().isEmpty())
    }

    @Test
    fun `pre-approved targets cannot be revoked into the user whitelist`() {
        val approvals = AppApprovals(
            resolver = SigningResolver { packageName ->
                SigningIdentity(packageName, listOf(hashA), null)
            },
            store = WhitelistStore(InMemoryWhitelistStorage()),
            preApprovedPackages = setOf(TEST_PACKAGE, SECURE_FIXTURE_PACKAGE),
        )

        assertFalse(approvals.revoke(TEST_PACKAGE))
        assertFalse(approvals.revoke(SECURE_FIXTURE_PACKAGE))
    }

    @Test
    fun `a pre-approved failure does not block later approvals of other apps`() {
        val storage = InMemoryWhitelistStorage()
        val approvals = AppApprovals(
            resolver = SigningResolver { packageName ->
                SigningIdentity(packageName, listOf(hashA), null)
            },
            store = WhitelistStore(storage),
            preApprovedPackages = setOf(TEST_PACKAGE),
        )

        assertFalse(approvals.approve(TEST_PACKAGE, now, null).approved)
        assertTrue(approvals.approve("com.example.app", now, null).approved)
        assertEquals(1, approvals.approvedApps().size)
    }
}
