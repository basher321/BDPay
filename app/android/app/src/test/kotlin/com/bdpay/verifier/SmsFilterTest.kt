package com.bdpay.verifier

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/** Shared helpers: the real rules file, settings and an in-memory inbox. */
object TestRules {
    val rules: List<ParserRule> by lazy { ParserRules.parse(File("src/main/res/raw/parser_rules.json").readText(Charsets.UTF_8)) }
}

class FakeSettings(
    override var monitoring: Boolean = true,
    val enabled: MutableSet<String> = mutableSetOf("bkash", "nagad", "rocket", "upay"),
) : FilterSettings {
    override fun isOperatorEnabled(operator: String) = operator in enabled
}

class FakeInbox : InboxWriter {
    val rows = mutableListOf<InboxRow>()
    override fun insertIfNew(row: InboxRow): Boolean {
        if (rows.any { it.dedupeHash == row.dedupeHash }) return false
        rows.add(row)
        return true
    }
}

class SmsFilterTest {
    private val bkash =
        "You have received payment Tk 1,250.00 from 01712345678. Ref: ORD-101. Fee Tk 0.00. Balance Tk 15,340.50. TrxID 9K48X7Z2 at 02/10/2026 18:25"
    private val nagad =
        "Money Received Amount: Tk 2,500.00 Sender: 01812345678 TxnID: 71B99AA2 Balance: Tk 15,000.00 Time: 02/10/2026 14:15"
    private val rocket =
        "Tk1,500.00 received from 017123456789 for A/C: 019876543211. Fee Tk0.00, Balance Tk5,600.00. TxnId: 24010200123"
    private val upay =
        "You have received Tk 800.00 from 01711223344. Txn ID: 4UP82910. Current balance Tk 3,400.00. Fee Tk 0.00."
    private val banglaBkash = "আপনি 01712345678 থেকে Tk 1,250.00 পেয়েছেন। Ref: ORDER-99। ব্যালেন্স Tk 15,340.50। TrxID 9K48X7B5"

    private val settings = FakeSettings()
    private val inbox = FakeInbox()
    private val filter = SmsFilter(TestRules.rules, settings, inbox, now = { 1000L }, newId = { "id-${inbox.rows.size}" })

    private fun run(sender: String, body: String) = filter.process(sender, body, 500L, "sim1")

    @Test
    fun stored() {
        assertEquals(KeepResult.stored, run("bKash", bkash))
        assertEquals(1, inbox.rows.size)
        val row = inbox.rows[0]
        assertEquals("bkash", row.operator)
        assertEquals(bkash, row.body)
        assertEquals("bKash", row.sender)
        assertEquals(500L, row.receivedAtMs)
        assertEquals("sim1", row.simSlot)
        assertEquals("sms", row.source)
    }

    @Test
    fun duplicate() {
        assertEquals(KeepResult.stored, run("bKash", bkash))
        assertEquals(KeepResult.duplicate, run("bKash", bkash))
        assertEquals(1, inbox.rows.size)
    }

    @Test
    fun duplicateIgnoresSenderCaseAndSpaces() {
        assertEquals(KeepResult.stored, run("bKash", bkash))
        assertEquals(KeepResult.duplicate, run(" BKASH ", bkash))
    }

    @Test
    fun monitoringOff() {
        settings.monitoring = false
        assertEquals(KeepResult.monitoringOff, run("bKash", bkash))
        assertTrue(inbox.rows.isEmpty())
    }

    @Test
    fun monitoringOffComesBeforeTheSenderCheck() {
        settings.monitoring = false
        assertEquals(KeepResult.monitoringOff, run("01799999999", bkash))
    }

    @Test
    fun senderNotTrusted() {
        assertEquals(KeepResult.senderNotTrusted, run("01799999999", bkash))
        assertTrue(inbox.rows.isEmpty())
    }

    @Test
    fun operatorOff() {
        settings.enabled.remove("bkash")
        assertEquals(KeepResult.operatorOff, run("bKash", bkash))
        assertTrue(inbox.rows.isEmpty())
    }

    @Test
    fun blockedOtp() {
        assertEquals(KeepResult.blocked, run("bKash", "Your bKash OTP is 123456. Do not share it with anyone."))
        assertEquals(KeepResult.blocked, run("16216", "Your OTP is 123456"))
        assertTrue(inbox.rows.isEmpty())
    }

    @Test
    fun blockedEvenWhenItAlsoLooksIncoming() {
        assertEquals(KeepResult.blocked, run("bKash", "You have received Tk 50.00 cashback offer. TrxID ABC12345"))
        assertEquals(KeepResult.blocked, run("bKash", "আপনার ওটিপি 123456। আপনি Tk 10 পেয়েছেন"))
        assertTrue(inbox.rows.isEmpty())
    }

    @Test
    fun notIncomingSendMoney() {
        assertEquals(KeepResult.notIncoming, run("bKash", "Send Money Tk 500.00 to 01711000000 successful. TrxID ABC12345"))
        assertTrue(inbox.rows.isEmpty())
    }

    @Test
    fun spacedUpperCaseSenderIsTrusted() {
        assertEquals(KeepResult.stored, run(" BKASH ", bkash))
    }

    @Test
    fun allReferenceSamplesAreStoredWithTheirOperator() {
        assertEquals(KeepResult.stored, run("bKash", bkash))
        assertEquals(KeepResult.stored, run("NAGAD", nagad))
        assertEquals(KeepResult.stored, run("16216", rocket))
        assertEquals(KeepResult.stored, run("upay", upay))
        assertEquals(KeepResult.stored, run("bKash", banglaBkash))
        assertEquals(listOf("bkash", "nagad", "rocket", "upay", "bkash"), inbox.rows.map { it.operator })
    }

    @Test
    fun ignoreWordsInsideOtherWordsDoNotBlock() {
        val body = "You have received payment Tk 500.00 from 01712345678. Ref: shopping. TrxID ABC12345"
        assertEquals(KeepResult.stored, run("bKash", body))
    }

    @Test
    fun nonBreakingSpaceIsNormalised() {
        assertEquals(KeepResult.stored, run("bKash", "You have received Tk 100.00 from 01712345678. TrxID ABC12345"))
    }

    @Test
    fun htmlBodyIsStoredAsIs() {
        val body = "You have received Tk 100.00 from 01712345678. <img src=x onerror=alert(1)> TrxID HTML1234"
        assertEquals(KeepResult.stored, run("bKash", body))
        assertEquals(body, inbox.rows[0].body)
    }

    @Test
    fun noRulesMeansNothingIsKept() {
        val empty = SmsFilter(emptyList(), settings, inbox)
        assertEquals(KeepResult.senderNotTrusted, empty.process("bKash", bkash, 0L, "unknown"))
        assertTrue(inbox.rows.isEmpty())
    }

    @Test
    fun simulatedSourceIsKept() {
        filter.process("bKash", bkash, 0L, "unknown", SmsFilter.SOURCE_SIMULATED)
        assertEquals("simulated", inbox.rows[0].source)
    }
}
