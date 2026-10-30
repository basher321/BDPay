package com.bdpay.verifier

import android.content.Context
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The one path from an SMS to the store, used by SmsReceiver and by simulateIncoming,
 * so the developer lab runs exactly the same filter and store as a real SMS. Never logs.
 * Spec 13a: the rules are the bundled file or the newer downloaded one (RulesChoice); after a stored row the
 * upload starts when autoSend is on.
 */
object SmsPipeline {
    /** One background thread: receiver work never runs on the main thread, and rows are written in order. */
    val executor: ExecutorService = Executors.newSingleThreadExecutor()

    @Volatile private var chosen: RulesChoice.Chosen? = null

    private fun bundledJson(context: Context): String =
        context.resources.openRawResource(R.raw.parser_rules).use { it.readBytes().toString(Charsets.UTF_8) }

    /** Loaded once and again after a download. A broken file gives no rules, so nothing is kept (fails closed). */
    private fun chosen(context: Context): RulesChoice.Chosen =
        chosen ?: RulesChoice.choose(bundledJson(context), RulesStore(context).read()).also {
            chosen = it
            val config = DeviceConfig(context)
            if (config.rulesVersion != it.version) config.rulesVersion = it.version
        }

    /** The rules JSON in use (what Dart's parser reads through getParserRules). */
    fun rulesJson(context: Context): String = chosen(context).json

    fun reloadRules() {
        chosen = null
    }

    /** Call on [executor] only. */
    fun process(context: Context, sender: String, body: String, receivedAtMs: Long, simSlot: String, source: String): KeepResult {
        val prefs = NativePrefs(context)
        val filter = SmsFilter(chosen(context).rules, prefs, SmsStore.get(context))
        val result = filter.process(sender, body, receivedAtMs, simSlot, source)
        if (result == KeepResult.stored) {
            SmsBridge.notifyInbox()
            if (prefs.autoSend) {
                try { Pipeline.uploadNow(context) } catch (_: Exception) { } // the next start or heartbeat retries
            }
        }
        return result
    }
}
