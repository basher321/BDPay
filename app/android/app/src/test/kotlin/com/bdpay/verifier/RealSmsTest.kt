package com.bdpay.verifier

import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

/**
 * Spec 14: every real SMS sample in tests/real_sms/ (repo root) is kept or dropped by SmsFilter as expected, with
 * the expected operator. SmsFilter does not read TrxID or amount, so those are checked in Dart and Deno (plan 14
 * D189). Failure messages name the file only, never the SMS text or values.
 */
class RealSmsTest {
    private val rules = ParserRules.parse(File("src/main/res/raw/parser_rules.json").readText(Charsets.UTF_8))

    private fun samplesDir(): File? {
        var dir: File? = File(".").absoluteFile
        while (dir != null && !File(dir, "supabase/functions").isDirectory) dir = dir.parentFile
        return dir?.let { File(it, "tests/real_sms") }?.takeIf { it.isDirectory }
    }

    private val settings = object : FilterSettings {
        override val monitoring = true
        override fun isOperatorEnabled(operator: String) = true
    }

    @Test
    fun everyRealSampleIsKeptOrDroppedAsExpected() {
        val files = samplesDir()?.listFiles()?.filter { it.isFile }?.sortedBy { it.name } ?: emptyList()
        val names = files.map { it.name }.toSet()
        for (n in names) {
            val ok = when {
                n.endsWith(".sms") -> "${n.removeSuffix(".sms")}.expected.json" in names
                n.endsWith(".expected.json") -> "${n.removeSuffix(".expected.json")}.sms" in names
                else -> false
            }
            assertTrue("$n: unpaired or unknown file", ok)
        }
        val failures = ArrayList<String>()
        for (f in files.filter { it.name.endsWith(".sms") }) {
            val id = f.name.removeSuffix(".sms")
            val exp = MiniJson.parse(File(f.parentFile, "$id.expected.json").readText(Charsets.UTF_8)) as? Map<*, *>
            if (exp == null) {
                failures += "$id: bad expected file"
                continue
            }
            val text = f.readText(Charsets.UTF_8).replace("\r\n", "\n").let { if (it.endsWith("\n")) it.dropLast(1) else it }
            val nl = text.indexOf('\n')
            if (nl < 0) {
                failures += "$id: no body line"
                continue
            }
            var stored: InboxRow? = null
            val inbox = object : InboxWriter {
                override fun insertIfNew(row: InboxRow): Boolean {
                    stored = row
                    return true
                }
            }
            val result = SmsFilter(rules, settings, inbox).process(text.substring(0, nl), text.substring(nl + 1), 0L, "sim1")
            if (exp["keep"] == true) {
                if (result != KeepResult.stored) failures += "$id: not kept"
                else if (stored?.operator != exp["operator"]) failures += "$id: operator differs"
            } else if (result == KeepResult.stored) {
                failures += "$id: kept but expected drop"
            }
        }
        if (failures.isNotEmpty()) fail(failures.joinToString("; "))
    }
}
