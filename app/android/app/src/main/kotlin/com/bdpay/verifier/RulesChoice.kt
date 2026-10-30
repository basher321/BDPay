package com.bdpay.verifier

/**
 * Which SMS rules the phone uses: the downloaded file only when it parses and its version is higher. Pure.
 *
 * Versions: the bundled file's version is its highest rule version (plan 08 D70). A download's version is the
 * server's parser_rules row version (what device-heartbeat and parser-rules report), which can go up while the
 * rules inside keep their own numbers - so it is saved next to the rules: {"version": N, "rules": [...]}.
 */
object RulesChoice {
    data class Chosen(val json: String, val rules: List<ParserRule>, val version: Int, val downloaded: Boolean)

    fun version(rules: List<ParserRule>): Int = rules.maxOfOrNull { it.version } ?: 0

    private fun parseOrNull(json: String?): List<ParserRule>? =
        try { json?.let { ParserRules.parse(it) }?.takeIf { it.isNotEmpty() } } catch (_: Exception) { null }

    /** The saved download as (version, rules array JSON), or null when it is missing or not in the saved shape. */
    private fun savedOrNull(file: String?): Pair<Int, String>? = try {
        val m = file?.let { MiniJson.parse(it) } as? Map<*, *>
        val v = (m?.get("version") as? Long)?.toInt()
        val list = m?.get("rules") as? List<*>
        if (v == null || list == null) null else v to JsonWriter.write(list)
    } catch (_: Exception) {
        null
    }

    fun choose(bundledJson: String, downloadedFile: String?): Chosen {
        val bundled = parseOrNull(bundledJson) ?: emptyList()
        val bundledVersion = version(bundled)
        val saved = savedOrNull(downloadedFile)
        val rules = saved?.let { parseOrNull(it.second) }
        return if (saved != null && rules != null && saved.first > bundledVersion) {
            Chosen(saved.second, rules, saved.first, true)
        } else {
            Chosen(bundledJson, bundled, bundledVersion, false)
        }
    }

    /**
     * The file to save for a parser-rules answer, or null (nothing changes): the version must be higher than
     * [currentVersion] and the rules must parse.
     */
    fun acceptDownload(version: Int?, rules: List<*>?, currentVersion: Int): String? {
        if (version == null || rules == null || version <= currentVersion) return null
        val json = try { JsonWriter.write(rules) } catch (_: Exception) { return null }
        parseOrNull(json) ?: return null
        return JsonWriter.write(linkedMapOf("version" to version, "rules" to rules))
    }
}
