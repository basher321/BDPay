package com.bdpay.verifier

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.provider.Telephony
import android.telephony.SubscriptionManager

/**
 * Manifest-registered receiver for SMS_RECEIVED. Works while the app is closed (once it has been opened after
 * install, and unless it was force-stopped). The work runs on a background thread via goAsync. Logs nothing.
 */
class SmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val pending = goAsync()
        val appContext = context.applicationContext
        SmsPipeline.executor.execute {
            try {
                val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent) ?: emptyArray()
                if (messages.isNotEmpty()) {
                    // The SMS time from the message (milliseconds since epoch, UTC); per sender, the first part's time.
                    val times = LinkedHashMap<String, Long>()
                    val parts = messages.map { m ->
                        val sender = m.displayOriginatingAddress ?: ""
                        times.putIfAbsent(sender, m.timestampMillis)
                        sender to (m.displayMessageBody ?: "")
                    }
                    val sim = simSlot(appContext, intent)
                    for ((sender, body) in joinParts(parts)) {
                        SmsPipeline.process(appContext, sender, body, times[sender] ?: System.currentTimeMillis(), sim, SmsFilter.SOURCE_SMS)
                    }
                }
            } catch (_: Throwable) {
                // Nothing is logged: the SMS content must never reach logcat.
            } finally {
                pending.finish()
            }
        }
    }

    /** sim1 / sim2 from the broadcast's subscription; unknown when READ_PHONE_STATE is denied or it is not found. */
    private fun simSlot(context: Context, intent: Intent): String {
        val subId = intent.getIntExtra(EXTRA_SUBSCRIPTION_INDEX, intent.getIntExtra(EXTRA_SUBSCRIPTION_OLD, -1))
        if (subId < 0) return "unknown"
        if (context.checkSelfPermission(Manifest.permission.READ_PHONE_STATE) != PackageManager.PERMISSION_GRANTED) {
            return "unknown"
        }
        return try {
            val manager = context.getSystemService(SubscriptionManager::class.java) ?: return "unknown"
            when (manager.getActiveSubscriptionInfo(subId)?.simSlotIndex) {
                0 -> "sim1"
                1 -> "sim2"
                else -> "unknown"
            }
        } catch (_: Exception) {
            "unknown"
        }
    }

    private companion object {
        const val EXTRA_SUBSCRIPTION_INDEX = "android.telephony.extra.SUBSCRIPTION_INDEX"
        const val EXTRA_SUBSCRIPTION_OLD = "subscription"
    }
}
