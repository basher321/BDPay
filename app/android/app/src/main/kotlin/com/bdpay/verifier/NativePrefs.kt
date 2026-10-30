package com.bdpay.verifier

import android.content.Context

/**
 * Settings the receiver must obey while the app is closed: monitoring and the enabled operators.
 * Also keeps the merchant's "করেছি" confirmation for the auto-start row (decision D12).
 */
class NativePrefs(context: Context) : FilterSettings {
    private val prefs = context.applicationContext.getSharedPreferences(NAME, Context.MODE_PRIVATE)

    override var monitoring: Boolean
        get() = prefs.getBoolean(KEY_MONITORING, true)
        set(value) = prefs.edit().putBoolean(KEY_MONITORING, value).apply()

    var enabledOperators: Set<String>
        get() = prefs.getStringSet(KEY_OPERATORS, null)?.toSet() ?: ALL_OPERATORS
        set(value) = prefs.edit().putStringSet(KEY_OPERATORS, value.filter { it in ALL_OPERATORS }.toSet()).apply()

    var autoStartConfirmed: Boolean
        get() = prefs.getBoolean(KEY_AUTO_START, false)
        set(value) = prefs.edit().putBoolean(KEY_AUTO_START, value).apply()

    /** Spec 05 "সাথে সাথে পাঠান"; the receiver obeys it while the app is closed (plan 13a D151). */
    var autoSend: Boolean
        get() = prefs.getBoolean(KEY_AUTO_SEND, true)
        set(value) = prefs.edit().putBoolean(KEY_AUTO_SEND, value).apply()

    /** Plan 13a D171: monitoring was switched off by a logout; the next registration switches it back on. */
    val monitoringPausedByLogout: Boolean get() = prefs.getBoolean(KEY_PAUSED_BY_LOGOUT, false)

    /** Logout: while nobody is signed in no SMS is caught (it would later go to whoever signs in next). */
    fun pauseForLogout() {
        if (monitoring) prefs.edit().putBoolean(KEY_MONITORING, false).putBoolean(KEY_PAUSED_BY_LOGOUT, true).commit()
    }

    /** Undoes [pauseForLogout] only; monitoring the merchant switched off stays off. */
    fun resumeAfterLogin() {
        if (monitoringPausedByLogout) prefs.edit().putBoolean(KEY_MONITORING, true).putBoolean(KEY_PAUSED_BY_LOGOUT, false).commit()
    }

    override fun isOperatorEnabled(operator: String) = operator in enabledOperators

    companion object {
        private const val NAME = "bdpay_native"
        private const val KEY_MONITORING = "monitoring"
        private const val KEY_OPERATORS = "enabled_operators"
        private const val KEY_AUTO_START = "auto_start_confirmed"
        private const val KEY_AUTO_SEND = "auto_send"
        private const val KEY_PAUSED_BY_LOGOUT = "monitoring_paused_by_logout"
        val ALL_OPERATORS = setOf("bkash", "nagad", "rocket", "upay")
    }
}
