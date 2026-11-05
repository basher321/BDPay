package com.bdpay.verifier

import org.junit.Assert.assertEquals
import org.junit.Test

class SmsPartsTest {
    @Test
    fun joiningThreePartsGivesTheFullBody() {
        val parts = listOf(
            "16216" to "Tk1,500.00 received from 017123456789 ",
            "16216" to "for A/C: 019876543211. Fee Tk0.00, ",
            "16216" to "Balance Tk5,600.00. TxnId: 24010200123",
        )
        val joined = joinParts(parts)
        assertEquals(1, joined.size)
        assertEquals(
            "Tk1,500.00 received from 017123456789 for A/C: 019876543211. Fee Tk0.00, Balance Tk5,600.00. TxnId: 24010200123",
            joined["16216"],
        )
    }

    @Test
    fun twoSendersStaySeparateAndInOrder() {
        val joined = joinParts(listOf("a" to "1", "b" to "x", "a" to "2", "b" to "y"))
        assertEquals(listOf("a", "b"), joined.keys.toList())
        assertEquals("12", joined["a"])
        assertEquals("xy", joined["b"])
    }
}
