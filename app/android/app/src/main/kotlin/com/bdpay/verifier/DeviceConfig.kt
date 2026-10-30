package com.bdpay.verifier

import android.content.Context

/**
 * Spec 13a DeviceConfig (SharedPreferences "bdpay_device"): deviceId, functionsUrl, clockOffsetMs, revoked flag,
 * rulesVersion and the last server contact. None of these is a secret. Every change fires the "pipeline" event.
 */
class DeviceConfig(context: Context) : PipelineConfig {
    private val prefs = context.applicationContext.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    override var deviceId: String?
        get() = prefs.getString(KEY_DEVICE_ID, null)
        set(value) = edit { if (value == null) remove(KEY_DEVICE_ID) else putString(KEY_DEVICE_ID, value) }

    var functionsUrl: String?
        get() = prefs.getString(KEY_URL, null)
        set(value) = edit { if (value == null) remove(KEY_URL) else putString(KEY_URL, value) }

    var clockOffsetMs: Long
        get() = prefs.getLong(KEY_OFFSET, 0L)
        set(value) = edit { putLong(KEY_OFFSET, value) }

    override var revoked: Boolean
        get() = prefs.getBoolean(KEY_REVOKED, false)
        set(value) = edit { putBoolean(KEY_REVOKED, value) }

    /** The version of the rules in use; 0 until the first rules load. */
    var rulesVersion: Int
        get() = prefs.getInt(KEY_RULES, 0)
        set(value) = edit { putInt(KEY_RULES, value) }

    override var lastServerContactMs: Long?
        get() = prefs.getLong(KEY_CONTACT, -1L).takeIf { it >= 0 }
        set(value) = edit { if (value == null) remove(KEY_CONTACT) else putLong(KEY_CONTACT, value) }

    /** Plan 13a D171: the merchant of the last registration. Kept at logout: it owns the rows still unsent. */
    var merchantId: String?
        get() = prefs.getString(KEY_MERCHANT, null)
        set(value) = edit { if (value == null) remove(KEY_MERCHANT) else putString(KEY_MERCHANT, value) }

    /** Plan 13a D171: merchantId -> row ids held for that merchant. */
    var held: Map<String, Set<String>>
        get() = MerchantHold.decode(prefs.getString(KEY_HELD, null))
        set(value) = edit { if (value.isEmpty()) remove(KEY_HELD) else putString(KEY_HELD, MerchantHold.encode(value)) }

    override val heldRowIds: Set<String> get() = MerchantHold.blocked(merchantId, held)

    override var latestAppVersion: String?
        get() = prefs.getString(KEY_LATEST, null)
        set(value) = edit { if (value == null) remove(KEY_LATEST) else putString(KEY_LATEST, value) }

    override var appDownloadUrl: String?
        get() = prefs.getString(KEY_DOWNLOAD, null)
        set(value) = edit { if (value == null) remove(KEY_DOWNLOAD) else putString(KEY_DOWNLOAD, value) }

    fun state() = PipelineState(
        deviceId, revoked, clockOffsetMs, rulesVersion, lastServerContactMs, latestAppVersion, appDownloadUrl,
    )

    private inline fun edit(block: android.content.SharedPreferences.Editor.() -> Unit) {
        prefs.edit().apply(block).apply()
        SmsBridge.notifyEvent("pipeline")
    }

    companion object {
        private const val NAME = "bdpay_device"
        private const val KEY_DEVICE_ID = "device_id"
        private const val KEY_URL = "functions_url"
        private const val KEY_OFFSET = "clock_offset_ms"
        private const val KEY_REVOKED = "revoked"
        private const val KEY_RULES = "rules_version"
        private const val KEY_CONTACT = "last_server_contact_ms"
        private const val KEY_MERCHANT = "merchant_id"
        private const val KEY_HELD = "held_rows"
        private const val KEY_LATEST = "latest_app_version"
        private const val KEY_DOWNLOAD = "app_download_url"
    }
}
