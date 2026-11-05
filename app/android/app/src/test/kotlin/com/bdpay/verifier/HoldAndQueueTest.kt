package com.bdpay.verifier

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MerchantHoldTest {
    @Test
    fun anotherMerchantRegistering_holdsTheOwnersUnsentRows() {
        val held = MerchantHold.onRegister("A", "B", emptyMap(), setOf("r1", "r2"))
        assertEquals(mapOf("A" to setOf("r1", "r2")), held)
        assertEquals(setOf("r1", "r2"), MerchantHold.blocked("B", held))
        assertEquals(emptySet<String>(), MerchantHold.blocked("A", held))
    }

    @Test
    fun theSameMerchantOrAFirstRegistrationHoldsNothing() {
        assertEquals(emptyMap<String, Set<String>>(), MerchantHold.onRegister("A", "A", emptyMap(), setOf("r1")))
        assertEquals(emptyMap<String, Set<String>>(), MerchantHold.onRegister(null, "A", emptyMap(), setOf("r1")))
    }

    @Test
    fun theOwnerComingBackReleasesItsRows_andSentRowsDropOut() {
        val held = mapOf("A" to setOf("r1", "r2"))
        assertEquals(emptyMap<String, Set<String>>(), MerchantHold.onRegister("B", "A", held, setOf("r1", "r2")))
        // r2 was sent meanwhile (not pending any more): only r1 stays held for A when C registers after B.
        val next = MerchantHold.onRegister("B", "C", held, setOf("r1", "b1"))
        assertEquals(mapOf("A" to setOf("r1"), "B" to setOf("b1")), next)
        assertEquals(setOf("r1", "b1"), MerchantHold.blocked("C", next))
    }

    @Test
    fun encodeDecodeRoundTrip_andGarbageIsEmpty() {
        val held = mapOf("A" to setOf("r2", "r1"), "B" to setOf("b1"))
        assertEquals(held, MerchantHold.decode(MerchantHold.encode(held)))
        assertEquals(emptyMap<String, Set<String>>(), MerchantHold.decode("{oops"))
        assertEquals(emptyMap<String, Set<String>>(), MerchantHold.decode(null))
    }

    @Test
    fun uploadRunSkipsHeldRows() {
        val rows = FakeRows(listOf(row("a", 1), row("held", 2)))
        val config = object : PipelineConfig {
            override val deviceId: String? = "d"
            override var revoked = false
            override var lastServerContactMs: Long? = null
            override val heldRowIds = setOf("held")
        }
        val server = FakeServer { _, b, _ -> ingestReply(b) }
        UploadRun(rows, server, config, HashSet()) { 0 }.run()
        assertEquals("sent", rows.status("a"))
        assertEquals("queued", rows.status("held"))
        assertTrue(server.calls.none { it.second.contains("\"held\"") })
    }
}

class UploadQueuePolicyTest {
    private fun job(s: UploadQueuePolicy.State, attempts: Int = 0) = UploadQueuePolicy.Job(s, attempts)

    @Test
    fun nothingThere_enqueues() {
        assertEquals(UploadQueuePolicy.Action.KEEP, UploadQueuePolicy.decide(emptyList()))
        assertEquals(UploadQueuePolicy.Action.KEEP, UploadQueuePolicy.decide(listOf(job(UploadQueuePolicy.State.FINISHED))))
    }

    @Test
    fun runningGetsOneFollowUpOnly() {
        val running = job(UploadQueuePolicy.State.RUNNING)
        assertEquals(UploadQueuePolicy.Action.APPEND, UploadQueuePolicy.decide(listOf(running)))
        // The second quick call: a follow-up is already blocked behind it.
        assertEquals(UploadQueuePolicy.Action.NONE, UploadQueuePolicy.decide(listOf(running, job(UploadQueuePolicy.State.BLOCKED))))
    }

    @Test
    fun waitingFresh_nothing_waitingInBackoff_replaced() {
        assertEquals(UploadQueuePolicy.Action.NONE, UploadQueuePolicy.decide(listOf(job(UploadQueuePolicy.State.ENQUEUED))))
        assertEquals(UploadQueuePolicy.Action.REPLACE, UploadQueuePolicy.decide(listOf(job(UploadQueuePolicy.State.ENQUEUED, 3))))
    }
}
