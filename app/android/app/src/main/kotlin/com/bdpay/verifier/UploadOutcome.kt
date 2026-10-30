package com.bdpay.verifier

/** A write to one row after an upload. verifyStatus / serverMessage / serverSmsId null = keep the stored value. */
data class RowUpdate(
    val id: String,
    val syncStatus: String,
    val retryCount: Int,
    val verifyStatus: String? = null,
    val serverCode: Int? = null,
    val serverMessage: String? = null,
    val serverSmsId: String? = null,
)

enum class HttpVerdict { RETRY_LATER, CLOCK_FIX_RETRY_NOW, STOP_REVOKED }

/** Spec 13a SmsUploadWorker result rules. Pure. */
object UploadOutcome {
    /** Applies sms-ingest's results (matched by localId) to the batch. A row without a result counts as failed. */
    fun applyResults(batch: List<QueueRow>, results: List<*>): List<RowUpdate> {
        val byId = results.filterIsInstance<Map<*, *>>().associateBy { it["localId"] as? String }
        return batch.map { row ->
            val r = byId[row.id] ?: return@map failed(row)
            val smsId = r["smsId"] as? String
            val message = r["serverMessage"] as? String
            val verify = (r["verifyStatus"] as? String)?.takeIf { it in VERIFY_STATUSES } ?: "pending"
            when (r["result"]) {
                "accepted", "duplicate" -> RowUpdate(row.id, "sent", row.retryCount, verify, 200, message, smsId)
                "rejected" ->
                    if (r["reason"] == "hashMismatch") {
                        failed(row)
                    } else {
                        RowUpdate(row.id, "sent", row.retryCount, "rejected", 200, message, smsId)
                    }
                else -> failed(row)
            }
        }
    }

    fun httpVerdict(status: Int?, errorCode: String?): HttpVerdict = when {
        status == 401 && errorCode == "staleTimestamp" -> HttpVerdict.CLOCK_FIX_RETRY_NOW
        status == 401 && errorCode == "unknownDevice" -> HttpVerdict.STOP_REVOKED
        status == 403 && errorCode == "deviceRevoked" -> HttpVerdict.STOP_REVOKED
        else -> HttpVerdict.RETRY_LATER // no answer, timeout, 5xx, 429 and anything unexpected
    }

    /** The whole batch after a failed request: back to failed (retry + 1), or to queued when the device is revoked. */
    fun failedBatch(batch: List<QueueRow>, verdict: HttpVerdict, status: Int?): List<RowUpdate> = batch.map {
        if (verdict == HttpVerdict.STOP_REVOKED) {
            RowUpdate(it.id, "queued", it.retryCount, serverCode = status)
        } else {
            RowUpdate(it.id, "failed", it.retryCount + 1, serverCode = status)
        }
    }

    private fun failed(row: QueueRow) = RowUpdate(row.id, "failed", row.retryCount + 1)
}
