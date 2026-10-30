package com.bdpay.verifier

import java.util.Locale

/** One operator's rules from res/raw/parser_rules.json (the only copy; Dart reads it through the channel). */
class ParserRule(
    val operator: String,
    val senders: List<String>,
    val incoming: Regex,
    val ignore: Regex,
    val trx: Regex,
    val amount: Regex,
    val payer: Regex,
    val balance: Regex,
    val reference: Regex,
    val payment: Regex,
    val version: Int,
)

object ParserRules {
    private val operators = setOf("bkash", "nagad", "rocket", "upay")

    /** Parses the rules file. Throws IllegalArgumentException (fixed message) on a bad file. */
    fun parse(json: String): List<ParserRule> {
        val list = MiniJson.parse(json) as? List<*> ?: throw IllegalArgumentException("rules: not an array")
        return list.map { item ->
            val o = item as? Map<*, *> ?: throw IllegalArgumentException("rules: not an object")
            val operator = o.str("operator")
            require(operator in operators) { "rules: unknown operator" }
            ParserRule(
                operator = operator,
                senders = (o["senders"] as? List<*>)?.map { it as String } ?: throw IllegalArgumentException("rules: senders"),
                incoming = o.regex("incoming"),
                ignore = o.regex("ignore"),
                trx = o.regex("trx"),
                amount = o.regex("amount"),
                payer = o.regex("payer"),
                balance = o.regex("balance"),
                reference = o.regex("reference"),
                payment = o.regex("payment"),
                version = (o["version"] as? Long)?.toInt() ?: throw IllegalArgumentException("rules: version"),
            )
        }
    }

    private fun Map<*, *>.str(key: String): String =
        this[key] as? String ?: throw IllegalArgumentException("rules: missing $key")

    // ASCII-only case folding, like the patterns are written; Bangla has no case.
    private fun Map<*, *>.regex(key: String): Regex = Regex(str(key), RegexOption.IGNORE_CASE)

    /** The rule whose senders contain [sender], compared after trim, case-insensitive. */
    fun ruleForSender(rules: List<ParserRule>, sender: String): ParserRule? {
        val s = normalizeSender(sender)
        return rules.firstOrNull { r -> r.senders.any { normalizeSender(it) == s } }
    }

    fun normalizeSender(sender: String): String = sender.trim().lowercase(Locale.ROOT)

    // The Unicode spaces Dart's \s knows and Java's \s does not; they become ' ' on both sides.
    private val unicodeSpaces = setOf(
        ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
        ' ', ' ', ' ', ' ', ' ', ' ', ' ', '　', '﻿',
    )

    /** Bangla digits -> English digits, Unicode spaces -> ' '. Same as normalizeSmsBody in Dart. */
    fun normalizeBody(body: String): String {
        val sb = StringBuilder(body.length)
        for (c in body) {
            sb.append(
                when {
                    c in '০'..'৯' -> '0' + (c - '০')
                    c in unicodeSpaces -> ' '
                    else -> c
                },
            )
        }
        return sb.toString()
    }
}

/** A small JSON reader for the rules file (objects, arrays, strings, integers, booleans, null). */
object MiniJson {
    fun parse(text: String): Any? {
        val p = Parser(text)
        val v = p.value()
        p.ws()
        if (p.i != text.length) throw IllegalArgumentException("json: trailing text")
        return v
    }

    private class Parser(val s: String) {
        var i = 0

        fun ws() {
            while (i < s.length && (s[i] == ' ' || s[i] == '\t' || s[i] == '\r' || s[i] == '\n' || s[i] == '﻿')) i++
        }

        private fun expect(c: Char) {
            ws()
            if (i >= s.length || s[i] != c) throw IllegalArgumentException("json: expected $c")
            i++
        }

        fun value(): Any? {
            ws()
            if (i >= s.length) throw IllegalArgumentException("json: unexpected end")
            return when (s[i]) {
                '{' -> obj()
                '[' -> arr()
                '"' -> str()
                't' -> lit("true", true)
                'f' -> lit("false", false)
                'n' -> lit("null", null)
                else -> num()
            }
        }

        private fun obj(): Map<String, Any?> {
            expect('{')
            val map = LinkedHashMap<String, Any?>()
            ws()
            if (i < s.length && s[i] == '}') { i++; return map }
            while (true) {
                ws()
                val key = str()
                expect(':')
                map[key] = value()
                ws()
                if (i < s.length && s[i] == ',') { i++; continue }
                expect('}')
                return map
            }
        }

        private fun arr(): List<Any?> {
            expect('[')
            val list = ArrayList<Any?>()
            ws()
            if (i < s.length && s[i] == ']') { i++; return list }
            while (true) {
                list.add(value())
                ws()
                if (i < s.length && s[i] == ',') { i++; continue }
                expect(']')
                return list
            }
        }

        private fun str(): String {
            if (i >= s.length || s[i] != '"') throw IllegalArgumentException("json: expected string")
            i++
            val sb = StringBuilder()
            while (true) {
                if (i >= s.length) throw IllegalArgumentException("json: open string")
                val c = s[i++]
                when (c) {
                    '"' -> return sb.toString()
                    '\\' -> {
                        if (i >= s.length) throw IllegalArgumentException("json: bad escape")
                        when (val e = s[i++]) {
                            '"', '\\', '/' -> sb.append(e)
                            'b' -> sb.append('\b')
                            'f' -> sb.append('\u000C')
                            'n' -> sb.append('\n')
                            'r' -> sb.append('\r')
                            't' -> sb.append('\t')
                            'u' -> {
                                if (i + 4 > s.length) throw IllegalArgumentException("json: bad escape")
                                sb.append(s.substring(i, i + 4).toInt(16).toChar())
                                i += 4
                            }
                            else -> throw IllegalArgumentException("json: bad escape")
                        }
                    }
                    else -> sb.append(c)
                }
            }
        }

        private fun lit(word: String, v: Any?): Any? {
            if (!s.startsWith(word, i)) throw IllegalArgumentException("json: bad literal")
            i += word.length
            return v
        }

        private fun num(): Long {
            val start = i
            while (i < s.length && (s[i] == '-' || s[i].isDigit())) i++
            return s.substring(start, i).toLongOrNull() ?: throw IllegalArgumentException("json: bad number")
        }
    }
}
