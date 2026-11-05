package com.bdpay.verifier

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class ParserRulesTest {
    private val text = File("src/main/res/raw/parser_rules.json").readText(Charsets.UTF_8)

    @Test
    fun theFileLoadsWithTheFourOperators() {
        val rules = ParserRules.parse(text)
        assertEquals(listOf("bkash", "nagad", "rocket", "upay"), rules.map { it.operator })
        assertTrue(rules.all { it.version >= 1 })
    }

    @Test
    fun noPatternHasInlineFlags() {
        val inlineFlag = Regex("""\(\?[imsuxdU-]+[:)]""")
        assertFalse(inlineFlag.containsMatchIn(text))
    }

    @Test
    fun everyRuleIsMarkedSample() {
        val list = MiniJson.parse(text) as List<*>
        assertTrue(list.all { (it as Map<*, *>)["note"].toString().startsWith("SAMPLE - verify with real SMS") })
    }

    @Test
    fun sendersCompareTrimmedAndCaseInsensitive() {
        val rules = ParserRules.parse(text)
        assertEquals("bkash", ParserRules.ruleForSender(rules, " BKASH ")?.operator)
        assertEquals("rocket", ParserRules.ruleForSender(rules, "16216")?.operator)
        assertNull(ParserRules.ruleForSender(rules, "01799999999"))
    }

    @Test
    fun banglaDigitsAndUnicodeSpacesAreNormalised() {
        assertEquals("৳ 1,250.00", ParserRules.normalizeBody("৳ ১,২৫০.০০"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun aBrokenFileThrows() {
        ParserRules.parse("[{\"operator\": \"bkash\"")
    }
}
