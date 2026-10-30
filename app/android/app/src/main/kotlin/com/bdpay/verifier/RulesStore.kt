package com.bdpay.verifier

import android.content.Context
import java.io.File

/**
 * Spec 13a: the rules file downloaded from the server, in the app's private files. SmsPipeline uses it only when
 * RulesChoice says it is valid and newer than the bundled parser_rules.json.
 */
class RulesStore(context: Context) : RulesSink {
    private val appContext = context.applicationContext
    private val file = File(appContext.filesDir, FILE)
    private val config = DeviceConfig(appContext)

    override val currentVersion: Int get() = config.rulesVersion

    fun read(): String? = try { if (file.isFile) file.readText(Charsets.UTF_8) else null } catch (_: Exception) { null }

    /** Written to a temp file, then renamed, so a crash never leaves half a rules file. */
    override fun save(json: String, version: Int) {
        val tmp = File(appContext.filesDir, "$FILE.tmp")
        tmp.writeText(json, Charsets.UTF_8)
        if (!tmp.renameTo(file)) {
            file.delete()
            tmp.renameTo(file)
        }
        config.rulesVersion = version
        SmsPipeline.reloadRules()
        SmsBridge.notifyEvent("rules")
    }

    companion object {
        private const val FILE = "parser_rules_server.json"
    }
}
