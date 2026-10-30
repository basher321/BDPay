package com.bdpay.verifier

/** Phone health for the heartbeat body (DeviceChecks + NativePrefs + SmsStore in the app). */
interface HeartbeatEnv {
    val appVersion: String
    val smsPermission: Boolean
    val batteryOptimizationOff: Boolean
    val monitoring: Boolean

    /** queued + sending + failed. */
    val queueCount: Int
}

/** Where downloaded rules go (RulesStore in the app). */
interface RulesSink {
    val currentVersion: Int

    fun save(json: String, version: Int)
}

/**
 * Spec 13a HeartbeatWorker as plain Kotlin: one device-heartbeat; on success the last-contact time; when the server
 * has newer rules, parser-rules, saved only if they parse and are newer (a broken file changes nothing).
 */
class HeartbeatRun(
    private val server: SignedPoster,
    private val config: PipelineConfig,
    private val env: HeartbeatEnv,
    private val rules: RulesSink,
    private val now: () -> Long,
) {
    /** True when the server answered 200. */
    fun run(): Boolean {
        if (config.deviceId == null || config.revoked) return false
        val reply = server.post(HEARTBEAT, body())
        if (reply.status != 200) {
            if (UploadOutcome.httpVerdict(reply.status, reply.errorCode) == HttpVerdict.STOP_REVOKED) config.revoked = true
            return false
        }
        config.lastServerContactMs = now()
        // Spec 15: the update notice. Both or neither; an answer without them clears them (older servers too).
        val latest = (reply.json?.get("latestAppVersion") as? String)?.takeIf { it.isNotBlank() }
        val url = (reply.json?.get("appDownloadUrl") as? String)?.takeIf { it.isNotBlank() }
        val pair = if (latest != null && url != null) latest to url else null
        if (config.latestAppVersion != pair?.first) config.latestAppVersion = pair?.first
        if (config.appDownloadUrl != pair?.second) config.appDownloadUrl = pair?.second
        val serverVersion = (reply.json?.get("rulesVersion") as? Number)?.toInt() ?: return true
        if (serverVersion > rules.currentVersion) fetchRules()
        return true
    }

    private fun fetchRules() {
        val reply = server.post(PARSER_RULES, "{}".toByteArray(Charsets.UTF_8))
        if (reply.status != 200) return
        val version = (reply.json?.get("version") as? Number)?.toInt() ?: return
        val file = RulesChoice.acceptDownload(version, reply.json["rules"] as? List<*>, rules.currentVersion) ?: return
        rules.save(file, version)
    }

    fun body(): ByteArray = JsonWriter.write(
        linkedMapOf(
            "appVersion" to env.appVersion,
            "smsPermission" to env.smsPermission,
            "batteryOptimizationOff" to env.batteryOptimizationOff,
            "monitoring" to env.monitoring,
            "queueCount" to env.queueCount,
        ),
    ).toByteArray(Charsets.UTF_8)

    companion object {
        const val HEARTBEAT = "device-heartbeat"
        const val PARSER_RULES = "parser-rules"
    }
}
