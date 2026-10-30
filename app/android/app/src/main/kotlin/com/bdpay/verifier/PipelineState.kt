package com.bdpay.verifier

/** What getPipelineState() returns (spec 13a). Pure. */
data class PipelineState(
    val deviceId: String?,
    val revoked: Boolean,
    val clockOffsetMs: Long,
    val rulesVersion: Int,
    val lastServerContactMs: Long?,
    val latestAppVersion: String? = null,
    val appDownloadUrl: String? = null,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "deviceId" to deviceId,
        "revoked" to revoked,
        "clockOffsetMs" to clockOffsetMs,
        "rulesVersion" to rulesVersion,
        "lastServerContactMs" to lastServerContactMs,
        "latestAppVersion" to latestAppVersion,
        "appDownloadUrl" to appDownloadUrl,
    )
}
