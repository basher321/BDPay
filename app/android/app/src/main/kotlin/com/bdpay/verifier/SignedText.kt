package com.bdpay.verifier

import java.security.MessageDigest

/** Spec 08 signed text: functionName + "\n" + timestamp + "\n" + hex SHA-256 of the exact body bytes. Pure. */
object SignedText {
    fun sha256Hex(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    fun of(functionName: String, timestampMs: Long, body: ByteArray): String =
        "$functionName\n$timestampMs\n${sha256Hex(body)}"
}
