package com.bdpay.verifier

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UploadRunTest {
    private fun run(rows: FakeRows, server: FakeServer, config: FakeConfig = FakeConfig(), sending: MutableSet<String> = HashSet()) =
        UploadRun(rows, server, config, sending) { 42L }

    @Test
    fun noDeviceIdOrRevokedDoesNothing() {
        val rows = FakeRows(listOf(row("a")))
        val server = FakeServer { _, b, _ -> ingestReply(b) }
        assertEquals(UploadRun.Verdict.NOTHING, run(rows, server, FakeConfig(deviceId = null)).run())
        assertEquals(UploadRun.Verdict.NOTHING, run(rows, server, FakeConfig(revoked = true)).run())
        assertEquals(0, server.calls.size)
        assertEquals("queued", rows.status("a"))
    }

    @Test
    fun thirtyRowsOneBatch_seventyRowsTwoBatches() {
        val thirty = FakeRows((1..30).map { row("r$it", receivedAtMs = it.toLong()) })
        val s30 = FakeServer { _, b, _ -> ingestReply(b) }
        assertEquals(UploadRun.Verdict.DONE, run(thirty, s30).run())
        assertEquals(1, s30.calls.size)
        assertTrue(thirty.rows.values.all { it.syncStatus == "sent" && it.serverSmsId == "s-${it.id}" })

        val seventy = FakeRows((1..70).map { row("r$it", receivedAtMs = it.toLong()) })
        val s70 = FakeServer { _, b, _ -> ingestReply(b) }
        val config = FakeConfig()
        assertEquals(UploadRun.Verdict.DONE, run(seventy, s70, config).run())
        assertEquals(2, s70.calls.size)
        assertTrue(seventy.rows.values.all { it.syncStatus == "sent" })
        assertEquals(42L, config.lastServerContactMs)
    }

    @Test
    fun aFailedRequestStopsTheLoopAndMarksTheBatchFailed() {
        val rows = FakeRows((1..70).map { row("r$it", receivedAtMs = it.toLong()) })
        val server = FakeServer { _, b, n -> if (n == 1) ingestReply(b) else ServerReply(503, null) }
        assertEquals(UploadRun.Verdict.RETRY, run(rows, server).run())
        assertEquals(2, server.calls.size)
        assertEquals(50, rows.rows.values.count { it.syncStatus == "sent" })
        assertTrue(rows.rows.values.filter { it.syncStatus == "failed" }.all { it.retryCount == 1 })
    }

    @Test
    fun networkError429AndTimeoutRetryLater() {
        for (reply in listOf(ServerReply(null, null), ServerReply(429, mapOf("error" to "rateLimited")))) {
            val rows = FakeRows(listOf(row("a")))
            assertEquals(UploadRun.Verdict.RETRY, run(rows, FakeServer { _, _, _ -> reply }).run())
            assertEquals("failed", rows.status("a"))
            assertEquals(1, rows.rows.getValue("a").retryCount)
        }
    }

    @Test
    fun hashMismatchIsNotRetriedInTheSameRun() {
        val rows = FakeRows(listOf(row("a"), row("b")))
        val server = FakeServer { _, b, _ ->
            ingestReply(b) { id -> if (id == "a") mapOf("localId" to "a", "result" to "rejected", "reason" to "hashMismatch") else accepted(id) }
        }
        assertEquals(UploadRun.Verdict.DONE, run(rows, server).run())
        assertEquals(1, server.calls.size)
        assertEquals("failed", rows.status("a"))
        assertEquals("sent", rows.status("b"))
    }

    @Test
    fun staleTimestampRetriesOnceAtOnce() {
        val rows = FakeRows(listOf(row("a")))
        val stale = ServerReply(401, mapOf("error" to "staleTimestamp"))
        val server = FakeServer { _, b, n -> if (n == 1) stale else ingestReply(b) }
        assertEquals(UploadRun.Verdict.DONE, run(rows, server).run())
        assertEquals(2, server.calls.size)
        assertEquals("sent", rows.status("a"))

        val rows2 = FakeRows(listOf(row("a")))
        val twice = FakeServer { _, _, _ -> stale }
        assertEquals(UploadRun.Verdict.RETRY, run(rows2, twice).run())
        assertEquals(2, twice.calls.size)
        assertEquals("failed", rows2.status("a"))
    }

    @Test
    fun revokedOrUnknownDeviceBackToQueuedAndStop() {
        for (reply in listOf(ServerReply(403, mapOf("error" to "deviceRevoked")), ServerReply(401, mapOf("error" to "unknownDevice")))) {
            val rows = FakeRows(listOf(row("a", sync = "failed", retry = 2)))
            val config = FakeConfig()
            assertEquals(UploadRun.Verdict.STOPPED, run(rows, FakeServer { _, _, _ -> reply }, config).run())
            assertEquals("queued", rows.status("a"))
            assertEquals(2, rows.rows.getValue("a").retryCount)
            assertTrue(config.revoked)
        }
    }

    @Test
    fun responseLostThenDuplicateWithTheSameServerId() {
        val rows = FakeRows(listOf(row("a")))
        assertEquals(UploadRun.Verdict.RETRY, run(rows, FakeServer { _, _, _ -> ServerReply(null, null) }).run())
        assertEquals("failed", rows.status("a"))
        val dup = FakeServer { _, b, _ ->
            ingestReply(b) { mapOf("localId" to it, "smsId" to "s-first", "result" to "duplicate", "verifyStatus" to "pending") }
        }
        assertEquals(UploadRun.Verdict.DONE, run(rows, dup).run())
        assertEquals("sent", rows.status("a"))
        assertEquals("s-first", rows.rows.getValue("a").serverSmsId)
    }

    @Test
    fun rowsAreInTheSendingSetOnlyWhileTheRequestRuns() {
        val sending = HashSet<String>()
        var seen: Set<String> = emptySet()
        val rows = FakeRows(listOf(row("a")))
        val server = FakeServer { _, b, _ -> seen = HashSet(sending); ingestReply(b) }
        run(rows, server, sending = sending).run()
        assertEquals(setOf("a"), seen)
        assertTrue(sending.isEmpty())
    }
}

class HeartbeatRunTest {
    private val env = object : HeartbeatEnv {
        override val appVersion = "1.0.0"
        override val smsPermission = true
        override val batteryOptimizationOff = false
        override val monitoring = true
        override val queueCount = 3
    }
    private val bundled = java.io.File("src/main/res/raw/parser_rules.json").readText(Charsets.UTF_8)

    private class Sink(override var currentVersion: Int = 1) : RulesSink {
        var saved: Pair<String, Int>? = null
        override fun save(json: String, version: Int) {
            saved = json to version
            currentVersion = version
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun rulesV(v: Int) = (MiniJson.parse(bundled.replace("\"version\": 1", "\"version\": $v")) as List<Any?>)

    @Test
    fun bodyHasTheSpec08Fields() {
        val run = HeartbeatRun(FakeServer { _, _, _ -> ServerReply(200, null) }, FakeConfig(), env, Sink()) { 0 }
        assertEquals(
            """{"appVersion":"1.0.0","smsPermission":true,"batteryOptimizationOff":false,"monitoring":true,"queueCount":3}""",
            run.body().toString(Charsets.UTF_8),
        )
    }

    @Test
    fun successSetsLastContact_rulesFetchedOnlyWhenHigher() {
        val config = FakeConfig()
        val sink = Sink()
        val same = FakeServer { _, _, _ -> ServerReply(200, mapOf("ok" to true, "rulesVersion" to 1L)) }
        assertTrue(HeartbeatRun(same, config, env, sink) { 77L }.run())
        assertEquals(77L, config.lastServerContactMs)
        assertEquals(0, same.count("parser-rules"))

        val higher = FakeServer { fn, _, _ ->
            if (fn == "device-heartbeat") ServerReply(200, mapOf("rulesVersion" to 2L))
            else ServerReply(200, mapOf("ok" to true, "version" to 2L, "rules" to rulesV(1))) // row version 2, same rules
        }
        assertTrue(HeartbeatRun(higher, config, env, sink) { 78L }.run())
        assertEquals(1, higher.count("parser-rules"))
        assertEquals(2, sink.saved?.second)
        assertEquals(2, RulesChoice.choose(bundled, sink.saved!!.first).version)
    }

    @Test
    fun brokenRulesKeepTheOldOnes() {
        val sink = Sink()
        val broken = FakeServer { fn, _, _ ->
            if (fn == "device-heartbeat") ServerReply(200, mapOf("rulesVersion" to 2L))
            else ServerReply(200, mapOf("version" to 2L, "rules" to listOf(mapOf("operator" to "paypal"))))
        }
        assertTrue(HeartbeatRun(broken, FakeConfig(), env, sink) { 0 }.run())
        assertEquals(null, sink.saved)
        assertEquals(1, sink.currentVersion)
    }

    @Test
    fun updateNoticeSavedWhenBothPresent_clearedWhenAbsent() {
        val config = FakeConfig()
        val withRelease = FakeServer { _, _, _ ->
            ServerReply(200, mapOf("rulesVersion" to 1L, "latestAppVersion" to "1.2.0", "appDownloadUrl" to "https://pay.example.com/d"))
        }
        assertTrue(HeartbeatRun(withRelease, config, env, Sink()) { 1L }.run())
        assertEquals("1.2.0", config.latestAppVersion)
        assertEquals("https://pay.example.com/d", config.appDownloadUrl)

        // Only one of the two -> neither (no card).
        val half = FakeServer { _, _, _ -> ServerReply(200, mapOf("rulesVersion" to 1L, "latestAppVersion" to "1.3.0")) }
        assertTrue(HeartbeatRun(half, config, env, Sink()) { 2L }.run())
        assertEquals(null, config.latestAppVersion)
        assertEquals(null, config.appDownloadUrl)

        // A server answer without the fields (env removed, or a server before spec 15) works as before.
        config.latestAppVersion = "1.2.0"
        config.appDownloadUrl = "https://pay.example.com/d"
        val old = FakeServer { _, _, _ -> ServerReply(200, mapOf("ok" to true, "rulesVersion" to 1L)) }
        assertTrue(HeartbeatRun(old, config, env, Sink()) { 3L }.run())
        assertEquals(3L, config.lastServerContactMs)
        assertEquals(null, config.latestAppVersion)
        assertEquals(0, old.count("parser-rules"))
    }

    @Test
    fun failureOrRevoked() {
        val config = FakeConfig()
        assertFalse(HeartbeatRun(FakeServer { _, _, _ -> ServerReply(null, null) }, config, env, Sink()) { 0 }.run())
        assertEquals(null, config.lastServerContactMs)
        assertFalse(HeartbeatRun(FakeServer { _, _, _ -> ServerReply(403, mapOf("error" to "deviceRevoked")) }, config, env, Sink()) { 0 }.run())
        assertTrue(config.revoked)
        assertFalse(HeartbeatRun(FakeServer { _, _, _ -> error("not called") }, FakeConfig(deviceId = null), env, Sink()) { 0 }.run())
    }
}

class StatusRunTest {
    @Test
    fun refreshesSelectedRowsInBatchesAndWritesClaims() {
        val now = 10_000_000L
        val rows = FakeRows((1..150).map { row("r$it", receivedAtMs = now - 1000, serverSmsId = "s$it") } + row("x", receivedAtMs = now))
        val server = FakeServer { _, b, _ ->
            @Suppress("UNCHECKED_CAST")
            val ids = (MiniJson.parse(b.toString(Charsets.UTF_8)) as Map<String, Any?>)["smsIds"] as List<String>
            ServerReply(200, mapOf("results" to ids.map {
                mapOf("smsId" to it, "verifyStatus" to "mismatch", "serverMessage" to "m",
                    "claim" to mapOf("claimId" to "c", "orderRef" to "#1", "expectedAmountPoisha" to 100L))
            }))
        }
        val config = FakeConfig()
        assertTrue(StatusRun(rows, server, config) { now }.run())
        assertEquals(2, server.calls.size)
        assertEquals("mismatch", rows.rows.getValue("r1").verifyStatus)
        assertEquals("""{"claimId":"c","orderRef":"#1","expectedAmountPoisha":100}""", rows.claims["r1"])
        assertEquals(now, config.lastServerContactMs)
    }

    @Test
    fun noDeviceOrFailureChangesNothing() {
        val rows = FakeRows(listOf(row("a", serverSmsId = "s1", receivedAtMs = 0)))
        assertFalse(StatusRun(rows, FakeServer { _, _, _ -> error("no") }, FakeConfig(deviceId = null)) { 1 }.run())
        assertFalse(StatusRun(rows, FakeServer { _, _, _ -> ServerReply(500, null) }, FakeConfig()) { 1 }.run())
        assertEquals("pending", rows.rows.getValue("a").verifyStatus)
    }
}
