package com.bdpay.verifier

/** Shared fakes for the pipeline JVM tests. */

fun row(
    id: String,
    receivedAtMs: Long = 1_000L,
    sync: String = "queued",
    verify: String = "pending",
    retry: Int = 0,
    serverSmsId: String? = null,
    createdAtMs: Long = receivedAtMs,
) = QueueRow(
    id = id,
    sender = "16216",
    body = "Tk1,500.00 received from 017123456789. TxnId: 24010200$id",
    receivedAtMs = receivedAtMs,
    simSlot = "sim1",
    dedupeHash = "hash-$id",
    syncStatus = sync,
    verifyStatus = verify,
    retryCount = retry,
    serverSmsId = serverSmsId,
    createdAtMs = createdAtMs,
)

class FakeConfig(
    override var deviceId: String? = "device-1",
    override var revoked: Boolean = false,
    override var lastServerContactMs: Long? = null,
    override var latestAppVersion: String? = null,
    override var appDownloadUrl: String? = null,
) : PipelineConfig

/** In-memory rows with the same guards as SmsStore. */
class FakeRows(initial: List<QueueRow>) : UploadRows, StatusRows {
    val rows = LinkedHashMap<String, QueueRow>().apply { initial.forEach { put(it.id, it) } }
    val claims = HashMap<String, String?>()

    override fun selectUploadable() = rows.values.filter { it.syncStatus == "queued" || it.syncStatus == "failed" }

    override fun applyUpload(updates: List<RowUpdate>) {
        for (u in updates) {
            val r = rows[u.id] ?: continue
            if (r.syncStatus != "queued" && r.syncStatus != "failed") continue
            rows[u.id] = r.copy(
                syncStatus = u.syncStatus,
                retryCount = u.retryCount,
                verifyStatus = u.verifyStatus ?: r.verifyStatus,
                serverSmsId = u.serverSmsId ?: r.serverSmsId,
            )
        }
    }

    override fun selectForRefresh(nowMs: Long) = rows.values.toList()

    override fun applyStatus(updates: List<StatusUpdate>) {
        for (u in updates) {
            val e = rows.entries.firstOrNull { it.value.serverSmsId == u.serverSmsId } ?: continue
            rows[e.key] = e.value.copy(verifyStatus = u.verifyStatus)
            claims[e.key] = u.claimJson
        }
    }

    fun status(id: String) = rows.getValue(id).syncStatus
}

/** Answers each post with the next scripted reply (or a lambda). Records every call. */
class FakeServer(private val answer: (String, ByteArray, Int) -> ServerReply) : SignedPoster {
    val calls = ArrayList<Pair<String, String>>()

    override fun post(functionName: String, body: ByteArray): ServerReply {
        calls += functionName to body.toString(Charsets.UTF_8)
        return answer(functionName, body, calls.size)
    }

    fun count(fn: String) = calls.count { it.first == fn }
}

/** sms-ingest's answer for every item in [body]: [result] for all, with smsId "s-<localId>". */
@Suppress("UNCHECKED_CAST")
fun ingestReply(body: ByteArray, result: (String) -> Map<String, Any?> = { accepted(it) }): ServerReply {
    val items = (MiniJson.parse(body.toString(Charsets.UTF_8)) as Map<String, Any?>)["items"] as List<Map<String, Any?>>
    return ServerReply(200, mapOf("ok" to true, "results" to items.map { result(it["localId"] as String) }))
}

fun accepted(id: String) = mapOf(
    "localId" to id, "smsId" to "s-$id", "result" to "accepted", "reason" to null,
    "verifyStatus" to "pending", "serverMessage" to null,
)
