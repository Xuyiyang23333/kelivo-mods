package com.kelivo.phoneagent

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PrivacyNoticeTest {
    @Test
    fun `a fresh store reports the notice as not acknowledged`() {
        val store = PrivacyNoticeStore(InMemoryPrivacyNoticeStorage())

        assertFalse(store.acknowledged())
    }

    @Test
    fun `acknowledging is sticky across a reload of the same storage`() {
        val storage = InMemoryPrivacyNoticeStorage()
        PrivacyNoticeStore(storage).acknowledge()

        assertTrue(PrivacyNoticeStore(storage).acknowledged())
    }

    @Test
    fun `unreadable or corrupted storage stays unacknowledged`() {
        assertFalse(PrivacyNoticeStore(InMemoryPrivacyNoticeStorage("garbage")).acknowledged())
        assertFalse(PrivacyNoticeStore(InMemoryPrivacyNoticeStorage("acknowledged-v0")).acknowledged())
        assertFalse(PrivacyNoticeStore(InMemoryPrivacyNoticeStorage("")).acknowledged())
    }

    @Test
    fun `reset makes the notice appear again`() {
        val store = PrivacyNoticeStore(InMemoryPrivacyNoticeStorage())
        store.acknowledge()
        store.reset()

        assertFalse(store.acknowledged())
    }
}
