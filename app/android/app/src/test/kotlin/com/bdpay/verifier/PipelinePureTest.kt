package com.bdpay.verifier

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class SignedTextTest {
    @Test
    fun signedTextIsNameNewlineTimestampNewlineHexSha256OfTheBody() {
        // Expected hash computed outside Kotlin: printf '%s' '{"items":[]}' | sha256sum
        assertEquals(
            "sms-ingest\n1761800000000\neef46741adfc3a9f76294d3b78f37a45f113092ac9d44ee77c7a038a88ff09a1",
            SignedText.of("sms-ingest", 1_761_800_000_000L, """{"items":[]}""".toByteArray(Charsets.UTF_8)),
        )
    }

    @Test
    fun theHashIsOverTheExactBytes() {
        val a = SignedText.of("x", 1, "আ".toByteArray(Charsets.UTF_8))
        val b = SignedText.of("x", 1, "আ ".toByteArray(Charsets.UTF_8))
        assertFalse(a == b)
        assertEquals(64, a.substringAfterLast('\n').length)
    }
}

class JsonWriterTest {
    @Test
    fun writesAndEscapes() {
        assertEquals(
            """{"a":"x\"y\\z\n","b":12,"c":true,"d":null,"e":[1,"২"]}""",
            JsonWriter.write(linkedMapOf("a" to "x\"y\\z\n", "b" to 12L, "c" to true, "d" to null, "e" to listOf(1, "২"))),
        )
        assertEquals("\"\\u0001\"", JsonWriter.write("\u0001"))
    }

    @Test
    fun roundTripsThroughMiniJson() {
        val v = linkedMapOf("items" to listOf(linkedMapOf("body" to "<img src=x> \"৳ ১,২৫০\"")))
        assertEquals(v, MiniJson.parse(JsonWriter.write(v)))
    }
}

class UploadBatchTest {
    @Test
    fun queuedAndFailedOnlyOldestFirstAtMost50() {
        val rows = (1..70).map { row("r$it", receivedAtMs = 10_000L - it) } +
            row("sent", sync = "sent", receivedAtMs = 1) + row("old-failed", sync = "failed", receivedAtMs = 2)
        val batch = UploadBatch.select(rows)
        assertEquals(50, batch.size)
        assertEquals("old-failed", batch.first().id)
        assertTrue(batch.none { it.id == "sent" })
        assertEquals(batch.sortedBy { it.receivedAtMs }, batch)
    }

    @Test
    fun excludedIdsAreSkipped() {
        assertEquals(listOf("b"), UploadBatch.select(listOf(row("a"), row("b")), exclude = setOf("a")).map { it.id })
    }

    @Test
    fun bodyHasTheSpec08ItemFields() {
        @Suppress("UNCHECKED_CAST")
        val item = ((MiniJson.parse(UploadBatch.body(listOf(row("a", receivedAtMs = 0))).toString(Charsets.UTF_8))
            as Map<String, Any?>)["items"] as List<Map<String, Any?>>).single()
        assertEquals(setOf("localId", "sender", "body", "receivedAt", "simSlot", "dedupeHash"), item.keys)
        assertEquals("1970-01-01T00:00:00Z", item["receivedAt"])
    }
}

class UploadOutcomeTest {
    private val batch = listOf(row("a", retry = 1), row("b"), row("c"), row("d"), row("e"))

    @Test
    fun everyResult() {
        val results = listOf(
            accepted("a"),
            mapOf("localId" to "b", "smsId" to "s-b", "result" to "duplicate", "verifyStatus" to "verified", "serverMessage" to "ok"),
            mapOf("localId" to "c", "smsId" to "s-c", "result" to "rejected", "reason" to "blocked", "verifyStatus" to "rejected", "serverMessage" to "OTP"),
            mapOf("localId" to "d", "smsId" to null, "result" to "rejected", "reason" to "hashMismatch", "verifyStatus" to "rejected"),
        )
        val u = UploadOutcome.applyResults(batch, results).associateBy { it.id }
        assertEquals(RowUpdate("a", "sent", 1, "pending", 200, null, "s-a"), u["a"])
        assertEquals(RowUpdate("b", "sent", 0, "verified", 200, "ok", "s-b"), u["b"])
        assertEquals(RowUpdate("c", "sent", 0, "rejected", 200, "OTP", "s-c"), u["c"])
        assertEquals(RowUpdate("d", "failed", 1), u["d"])
        assertEquals(RowUpdate("e", "failed", 1), u["e"]) // no result for e
    }

    @Test
    fun httpVerdicts() {
        assertEquals(HttpVerdict.RETRY_LATER, UploadOutcome.httpVerdict(null, null))
        assertEquals(HttpVerdict.RETRY_LATER, UploadOutcome.httpVerdict(500, "internalError"))
        assertEquals(HttpVerdict.RETRY_LATER, UploadOutcome.httpVerdict(503, null))
        assertEquals(HttpVerdict.RETRY_LATER, UploadOutcome.httpVerdict(429, "rateLimited"))
        assertEquals(HttpVerdict.CLOCK_FIX_RETRY_NOW, UploadOutcome.httpVerdict(401, "staleTimestamp"))
        assertEquals(HttpVerdict.STOP_REVOKED, UploadOutcome.httpVerdict(401, "unknownDevice"))
        assertEquals(HttpVerdict.STOP_REVOKED, UploadOutcome.httpVerdict(403, "deviceRevoked"))
        assertEquals(HttpVerdict.RETRY_LATER, UploadOutcome.httpVerdict(401, "badSignature"))
    }

    @Test
    fun failedBatchFailedOrBackToQueued() {
        assertEquals(listOf(RowUpdate("a", "failed", 2, serverCode = 503)),
            UploadOutcome.failedBatch(listOf(row("a", retry = 1)), HttpVerdict.RETRY_LATER, 503))
        assertEquals(listOf(RowUpdate("a", "queued", 1, serverCode = 403)),
            UploadOutcome.failedBatch(listOf(row("a", retry = 1)), HttpVerdict.STOP_REVOKED, 403))
    }
}

class ClockOffsetTest {
    @Test
    fun fromServerTimePhone10MinutesFast() {
        val server = 1_761_800_000_000L
        assertEquals(-600_000L, ClockOffset.fromServerTime(java.time.Instant.ofEpochMilli(server).toString(), server + 600_000))
    }

    @Test
    fun fromDateHeader() {
        val serverMs = java.time.ZonedDateTime.parse("Fri, 30 Oct 2026 06:00:00 GMT", java.time.format.DateTimeFormatter.RFC_1123_DATE_TIME)
            .toInstant().toEpochMilli()
        assertEquals(-600_000L, ClockOffset.fromDateHeader("Fri, 30 Oct 2026 06:00:00 GMT", serverMs + 600_000))
        assertEquals(-600_000L, ClockOffset.from(null, "Fri, 30 Oct 2026 06:00:00 GMT", serverMs + 600_000))
    }

    @Test
    fun badInputsGiveNullAndServerTimeWins() {
        assertNull(ClockOffset.fromServerTime("soon", 0))
        assertNull(ClockOffset.fromDateHeader("yesterday", 0))
        assertNull(ClockOffset.from(null, null, 0))
        assertEquals(1000L, ClockOffset.from("1970-01-01T00:00:01Z", "Thu, 01 Jan 1970 00:00:09 GMT", 0))
        assertEquals(1_000_500L, ClockOffset.signedTimestamp(1_000_000L, 500L))
    }
}

class StatusRefreshTest {
    private val now = 100L * 60 * 60 * 1000

    @Test
    fun selectsServerIdPendingOrMismatchWithin48h() {
        val rows = listOf(
            row("ok", receivedAtMs = now - 1000, serverSmsId = "s1"),
            row("mm", receivedAtMs = now - 1000, verify = "mismatch", serverSmsId = "s2"),
            row("edge", receivedAtMs = now - StatusRefresh.WINDOW_MS, serverSmsId = "s3"),
            row("old", receivedAtMs = now - StatusRefresh.WINDOW_MS - 1, serverSmsId = "s4"),
            row("noId", receivedAtMs = now - 1000),
            row("done", receivedAtMs = now - 1000, verify = "verified", serverSmsId = "s5"),
            row("rej", receivedAtMs = now - 1000, verify = "rejected", serverSmsId = "s6"),
        )
        assertEquals(listOf("ok", "mm", "edge"), StatusRefresh.select(rows, now).map { it.id })
    }

    @Test
    fun batchesOf100() {
        val rows = (1..250).map { row("r$it", serverSmsId = "s$it") }
        assertEquals(listOf(100, 100, 50), StatusRefresh.batches(rows).map { it.size })
    }

    @Test
    fun applyWritesClaimJsonOrNull() {
        val updates = StatusRefresh.apply(
            listOf(
                mapOf("smsId" to "s1", "verifyStatus" to "mismatch", "serverMessage" to "অর্ডারের টাকার সাথে মেলেনি",
                    "claim" to mapOf("claimId" to "c1", "orderRef" to "#1045", "expectedAmountPoisha" to 160000L)),
                mapOf("smsId" to "s2", "verifyStatus" to "verified", "serverMessage" to null, "claim" to null),
                mapOf("smsId" to "s3", "verifyStatus" to "weird"),
            ),
            now,
        )
        assertEquals(2, updates.size)
        assertEquals("""{"claimId":"c1","orderRef":"#1045","expectedAmountPoisha":160000}""", updates[0].claimJson)
        assertNull(updates[1].claimJson)
        assertEquals(now, updates[0].checkedAtMs)
    }
}

class RulesChoiceTest {
    private val bundled = File("src/main/res/raw/parser_rules.json").readText(Charsets.UTF_8)
    private fun saved(v: Int, rules: String = bundled) = """{"version":$v,"rules":$rules}"""

    @Suppress("UNCHECKED_CAST")
    private val bundledList = MiniJson.parse(bundled) as List<Any?>

    @Test
    fun higherDownloadedWins_evenWithTheSameRulesInside() {
        // Manual check 9: parser_rules row version 2 with the same rules JSON (inner rule versions stay 1).
        val c = RulesChoice.choose(bundled, saved(2))
        assertTrue(c.downloaded)
        assertEquals(2, c.version)
        assertEquals(RulesChoice.choose(bundled, null).rules.size, c.rules.size)
    }

    @Test
    fun lowerEqualBrokenOrMissingKeepBundled() {
        val broken = """[{"operator":"paypal"}]"""
        for (d in listOf(saved(1), saved(0), saved(2, "[]"), saved(2, broken), "{oops", bundled, "[]", null)) {
            val c = RulesChoice.choose(bundled, d)
            assertFalse(c.downloaded)
            assertEquals(1, c.version)
        }
    }

    @Test
    fun acceptDownloadOnlyWhenNewerAndValid() {
        val file = RulesChoice.acceptDownload(2, bundledList, 1)
        assertEquals(2, RulesChoice.choose(bundled, file).version)
        assertNull(RulesChoice.acceptDownload(1, bundledList, 1))
        assertNull(RulesChoice.acceptDownload(null, bundledList, 1))
        assertNull(RulesChoice.acceptDownload(2, null, 1))
        assertNull(RulesChoice.acceptDownload(2, listOf(mapOf("operator" to "paypal")), 1))
    }
}

class PipelineStateTest {
    @Test
    fun mapHasTheContractKeys() {
        assertEquals(
            setOf(
                "deviceId", "revoked", "clockOffsetMs", "rulesVersion", "lastServerContactMs",
                "latestAppVersion", "appDownloadUrl",
            ),
            PipelineState("d", false, 0, 1, null).toMap().keys,
        )
    }
}
