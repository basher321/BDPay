package com.bdpay.verifier

/** One sms_inbox row as the pipeline sees it. Pure. */
data class QueueRow(
    val id: String,
    val sender: String,
    val body: String,
    val receivedAtMs: Long,
    val simSlot: String,
    val dedupeHash: String,
    val syncStatus: String,
    val verifyStatus: String,
    val retryCount: Int,
    val serverSmsId: String?,
    val createdAtMs: Long,
)

/** A signed request's answer. status null = no answer (network error or timeout). Never logged. */
data class ServerReply(val status: Int?, val json: Map<String, Any?>?, val dateHeader: String? = null) {
    val errorCode: String? get() = json?.get("error") as? String
}

/** Sends one signed POST. The real one is ServerClient; tests use a fake. */
fun interface SignedPoster {
    fun post(functionName: String, body: ByteArray): ServerReply
}

/** What the pipeline reads and writes in DeviceConfig. */
interface PipelineConfig {
    val deviceId: String?
    var revoked: Boolean
    var lastServerContactMs: Long?

    /** Rows held for another merchant (plan 13a D171): never uploaded under this registration. */
    val heldRowIds: Set<String> get() = emptySet()

    /** Spec 15: the newest app version and its download page from the last heartbeat (both or neither). */
    var latestAppVersion: String?
        get() = null
        set(@Suppress("UNUSED_PARAMETER") value) {}
    var appDownloadUrl: String?
        get() = null
        set(@Suppress("UNUSED_PARAMETER") value) {}
}

internal val VERIFY_STATUSES = setOf("pending", "verified", "mismatch", "rejected")
