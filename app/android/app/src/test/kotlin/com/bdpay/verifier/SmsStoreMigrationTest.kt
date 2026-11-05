package com.bdpay.verifier

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Plan 13a D152: Android's SQLite cannot run in a JVM test, so this checks the upgrade's SQL: columns are only
 * added, and nothing is dropped, rebuilt or changed (no UPDATE in the upgrade; D158 was not approved).
 */
class SmsStoreMigrationTest {
    @Test
    fun versionTwoAddsExactlyTheThreeColumns() {
        assertEquals(2, SmsStoreSchema.VERSION)
        assertEquals(listOf("server_sms_id", "claim_json", "last_status_check_ms"), SmsStoreSchema.V2_COLUMNS.map { it.first })
        for ((c, t) in SmsStoreSchema.V2_COLUMNS) {
            assertEquals("ALTER TABLE sms_inbox ADD COLUMN $c $t", SmsStoreSchema.addColumn(c, t))
            assertTrue(t.endsWith("NULL"))
        }
    }

    @Test
    fun theUpgradeNeverDropsDeletesOrRebuilds() {
        // Code only: comments say "never deleted" / "never drops", which is the point, not a violation.
        val src = File("src/main/kotlin/com/bdpay/verifier/SmsStore.kt").readText()
            .replace(Regex("""/\*[\s\S]*?\*/"""), "")
            .replace(Regex("""//[^\n]*"""), "")
        val forbidden = Regex("""\b(DROP|DELETE|RENAME\s+TO)\b|sms_inbox_new|\.delete\(""", RegexOption.IGNORE_CASE)
        assertFalse(forbidden.containsMatchIn(src))
    }

    @Test
    fun theUpgradeChangesNoRow() {
        val src = File("src/main/kotlin/com/bdpay/verifier/SmsStore.kt").readText()
        val upgrade = src.substringAfter("override fun onUpgrade(").substringBefore("private fun columns(")
        assertFalse(Regex("""\bUPDATE\b|\.update\(""", RegexOption.IGNORE_CASE).containsMatchIn(upgrade))
        assertTrue(upgrade.contains("SmsStoreSchema.addColumn("))
    }

    @Test
    fun theV1TableIsUnchanged() {
        assertTrue(SmsStoreSchema.CREATE_V1.contains("CHECK (sync_status IN ('queued', 'sent', 'failed'))"))
        assertFalse(SmsStoreSchema.CREATE_V1.contains("server_sms_id"))
    }
}
