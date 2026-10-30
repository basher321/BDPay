package com.bdpay.verifier

/** A server status for one uploaded row. claimJson = {claimId, orderRef, expectedAmountPoisha} or null. */
data class StatusUpdate(
    val serverSmsId: String,
    val verifyStatus: String,
    val serverMessage: String?,
    val claimJson: String?,
    val checkedAtMs: Long,
)

/** Spec 13a StatusRefreshWorker rules. Pure. */
object StatusRefresh {
    const val WINDOW_MS = 48L * 60 * 60 * 1000
    const val BATCH = 100

    /** Uploaded rows (server id) still pending or mismatch, received in the last 48 hours. */
    fun select(rows: List<QueueRow>, nowMs: Long): List<QueueRow> = rows.filter {
        it.serverSmsId != null && (it.verifyStatus == "pending" || it.verifyStatus == "mismatch") &&
            nowMs - it.receivedAtMs <= WINDOW_MS
    }

    fun batches(rows: List<QueueRow>): List<List<String>> = rows.mapNotNull { it.serverSmsId }.chunked(BATCH)

    fun body(serverIds: List<String>): ByteArray =
        JsonWriter.write(mapOf("smsIds" to serverIds)).toByteArray(Charsets.UTF_8)

    fun apply(results: List<*>, nowMs: Long): List<StatusUpdate> =
        results.filterIsInstance<Map<*, *>>().mapNotNull { r ->
            val id = r["smsId"] as? String ?: return@mapNotNull null
            val verify = (r["verifyStatus"] as? String)?.takeIf { it in VERIFY_STATUSES } ?: return@mapNotNull null
            val claim = r["claim"] as? Map<*, *>
            val claimJson = claim?.let {
                val claimId = it["claimId"] as? String
                val orderRef = it["orderRef"] as? String
                val amount = (it["expectedAmountPoisha"] as? Number)?.toLong()
                if (claimId == null || orderRef == null || amount == null) {
                    null
                } else {
                    JsonWriter.write(linkedMapOf("claimId" to claimId, "orderRef" to orderRef, "expectedAmountPoisha" to amount))
                }
            }
            StatusUpdate(id, verify, r["serverMessage"] as? String, claimJson, nowMs)
        }
}
