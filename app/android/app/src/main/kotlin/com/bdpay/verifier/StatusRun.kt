package com.bdpay.verifier

/** The rows the status refresh reads and writes. */
interface StatusRows {
    fun selectForRefresh(nowMs: Long): List<QueueRow>

    /** Writes verify_status, server_message, claim_json and last_status_check_ms only. */
    fun applyStatus(updates: List<StatusUpdate>)
}

/** Spec 13a StatusRefreshWorker as plain Kotlin: sms-status in batches of 100. Returns true when anything changed. */
class StatusRun(
    private val rows: StatusRows,
    private val server: SignedPoster,
    private val config: PipelineConfig,
    private val now: () -> Long,
) {
    fun run(): Boolean {
        if (config.deviceId == null || config.revoked) return false
        val nowMs = now()
        var changed = false
        for (ids in StatusRefresh.batches(StatusRefresh.select(rows.selectForRefresh(nowMs), nowMs))) {
            val reply = server.post(FUNCTION, StatusRefresh.body(ids))
            if (reply.status != 200) {
                if (UploadOutcome.httpVerdict(reply.status, reply.errorCode) == HttpVerdict.STOP_REVOKED) {
                    config.revoked = true
                }
                return changed
            }
            config.lastServerContactMs = nowMs
            val updates = StatusRefresh.apply(reply.json?.get("results") as? List<*> ?: emptyList<Any?>(), nowMs)
            if (updates.isNotEmpty()) {
                rows.applyStatus(updates)
                changed = true
            }
        }
        return changed
    }

    companion object {
        const val FUNCTION = "sms-status"
    }
}
