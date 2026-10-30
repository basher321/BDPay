package com.bdpay.verifier

/** The rows the upload loop reads and writes (SmsStore in the app, a fake in tests). */
interface UploadRows {
    fun selectUploadable(): List<QueueRow>

    /** Guarded: only rows still queued or failed are changed. */
    fun applyUpload(updates: List<RowUpdate>)
}

/**
 * Spec 13a SmsUploadWorker as plain Kotlin: batches of 50, oldest first, repeat until no rows are left or a request
 * fails. Rows already tried in this run are not picked again (a hashMismatch row cannot loop). Never logs.
 */
class UploadRun(
    private val rows: UploadRows,
    private val server: SignedPoster,
    private val config: PipelineConfig,
    private val sending: MutableSet<String>,
    private val now: () -> Long,
) {
    enum class Verdict { NOTHING, DONE, RETRY, STOPPED }

    /** True when at least one batch reached the server in this run (the worker then refreshes statuses). */
    var anyUploaded = false
        private set

    fun run(): Verdict {
        if (config.deviceId == null || config.revoked) return Verdict.NOTHING
        val tried = HashSet<String>()
        val held = config.heldRowIds
        while (true) {
            val batch = UploadBatch.select(rows.selectUploadable(), tried + held)
            if (batch.isEmpty()) return if (tried.isEmpty()) Verdict.NOTHING else Verdict.DONE
            val ids = batch.map { it.id }
            tried += ids
            synchronized(sending) { sending += ids }
            try {
                val body = UploadBatch.body(batch)
                var reply = server.post(FUNCTION, body)
                if (UploadOutcome.httpVerdict(reply.status, reply.errorCode) == HttpVerdict.CLOCK_FIX_RETRY_NOW) {
                    // The poster already moved the clock offset from this answer; try once more at once.
                    reply = server.post(FUNCTION, body)
                }
                if (reply.status == 200) {
                    val results = reply.json?.get("results") as? List<*> ?: emptyList<Any?>()
                    rows.applyUpload(UploadOutcome.applyResults(batch, results))
                    config.lastServerContactMs = now()
                    anyUploaded = true
                    continue
                }
                var verdict = UploadOutcome.httpVerdict(reply.status, reply.errorCode)
                if (verdict == HttpVerdict.CLOCK_FIX_RETRY_NOW) verdict = HttpVerdict.RETRY_LATER // stale twice
                rows.applyUpload(UploadOutcome.failedBatch(batch, verdict, reply.status))
                if (verdict == HttpVerdict.STOP_REVOKED) {
                    config.revoked = true
                    return Verdict.STOPPED
                }
                return Verdict.RETRY
            } finally {
                synchronized(sending) { sending -= ids.toSet() }
            }
        }
    }

    companion object {
        const val FUNCTION = "sms-ingest"
    }
}
