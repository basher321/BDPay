package com.bdpay.verifier

import java.security.MessageDigest
import java.util.UUID

/** Keep-rule results. The wire name (sent to Dart) is the enum name. */
enum class KeepResult { stored, duplicate, monitoringOff, senderNotTrusted, operatorOff, blocked, notIncoming }

/** What the filter needs from the saved settings. */
interface FilterSettings {
    val monitoring: Boolean
    fun isOperatorEnabled(operator: String): Boolean
}

/** One row to keep. Bodies are kept exactly as received. */
class InboxRow(
    val id: String,
    val sender: String,
    val body: String,
    val receivedAtMs: Long,
    val simSlot: String,
    val dedupeHash: String,
    val operator: String,
    val source: String,
    val createdAtMs: Long,
)

/** The only way the filter writes. Returns false when a row with the same dedupe hash exists. */
interface InboxWriter {
    fun insertIfNew(row: InboxRow): Boolean
}

/**
 * Decides keep or ignore, always in the same order. Nothing is written unless step 6 is reached.
 * Never logs anything. With no rules (missing or broken file) every sender is untrusted, so nothing is kept.
 */
class SmsFilter(
    private val rules: List<ParserRule>,
    private val settings: FilterSettings,
    private val inbox: InboxWriter,
    private val now: () -> Long = { System.currentTimeMillis() },
    private val newId: () -> String = { UUID.randomUUID().toString() },
) {
    fun process(sender: String, body: String, receivedAtMs: Long, simSlot: String, source: String = SOURCE_SMS): KeepResult {
        // 1. Monitoring off.
        if (!settings.monitoring) return KeepResult.monitoringOff
        // 2. Sender not in any rule.
        val rule = ParserRules.ruleForSender(rules, sender) ?: return KeepResult.senderNotTrusted
        // 3. Operator turned off.
        if (!settings.isOperatorEnabled(rule.operator)) return KeepResult.operatorOff
        val text = ParserRules.normalizeBody(body)
        // 4. OTP, PIN, codes, promotions.
        if (rule.ignore.containsMatchIn(text)) return KeepResult.blocked
        // 5. Not a money-received SMS.
        if (!rule.incoming.containsMatchIn(text)) return KeepResult.notIncoming
        // 6. Keep.
        val row = InboxRow(
            id = newId(),
            sender = sender,
            body = body,
            receivedAtMs = receivedAtMs,
            simSlot = simSlot,
            dedupeHash = dedupeHash(sender, body),
            operator = rule.operator,
            source = source,
            createdAtMs = now(),
        )
        return if (inbox.insertIfNew(row)) KeepResult.stored else KeepResult.duplicate
    }

    companion object {
        const val SOURCE_SMS = "sms"
        const val SOURCE_SIMULATED = "simulated"

        /** SHA-256 of the trimmed, lower-case sender + "|" + the body as received. */
        fun dedupeHash(sender: String, body: String): String {
            val bytes = MessageDigest.getInstance("SHA-256")
                .digest("${ParserRules.normalizeSender(sender)}|$body".toByteArray(Charsets.UTF_8))
            return bytes.joinToString("") { "%02x".format(it) }
        }
    }
}

/** Joins the parts of one broadcast into one body per sender, keeping the order of the parts. */
fun joinParts(parts: List<Pair<String, String>>): LinkedHashMap<String, String> {
    val out = LinkedHashMap<String, StringBuilder>()
    for ((sender, text) in parts) out.getOrPut(sender) { StringBuilder() }.append(text)
    return LinkedHashMap(out.mapValues { it.value.toString() })
}
