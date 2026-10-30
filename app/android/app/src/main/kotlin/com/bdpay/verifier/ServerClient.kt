package com.bdpay.verifier

import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL

/**
 * Spec 13a: signed POSTs to the Edge Functions (spec 08 headers and signed text) with HttpURLConnection, 15 s
 * timeouts. Every answer's serverTime (or Date header) moves the clock offset. Any failure becomes
 * ServerReply(null, ...) - no exception, URL, body, header or signature is ever logged or rethrown.
 */
class ServerClient(
    private val config: DeviceConfig,
    private val now: () -> Long = { System.currentTimeMillis() },
) : SignedPoster {
    override fun post(functionName: String, body: ByteArray): ServerReply {
        val base = config.functionsUrl ?: return ServerReply(null, null)
        val deviceId = config.deviceId ?: return ServerReply(null, null)
        val timestamp = ClockOffset.signedTimestamp(now(), config.clockOffsetMs)
        var connection: HttpURLConnection? = null
        return try {
            val signature = DeviceKeys.sign(SignedText.of(functionName, timestamp, body))
            val c = (URL("$base/$functionName").openConnection() as HttpURLConnection).also { connection = it }
            c.requestMethod = "POST"
            c.instanceFollowRedirects = false // a redirect never re-sends the signed headers and body elsewhere
            c.connectTimeout = TIMEOUT_MS
            c.readTimeout = TIMEOUT_MS
            c.doOutput = true
            c.useCaches = false
            c.setRequestProperty("Content-Type", "application/json")
            c.setRequestProperty("X-Device-Id", deviceId)
            c.setRequestProperty("X-Timestamp", timestamp.toString())
            c.setRequestProperty("X-Signature", signature)
            c.setFixedLengthStreamingMode(body.size)
            c.outputStream.use { it.write(body) }
            val status = c.responseCode
            val text = (if (status >= 400) c.errorStream else c.inputStream)?.let { readCapped(it) }
            @Suppress("UNCHECKED_CAST")
            val json = try { text?.let { MiniJson.parse(it) } as? Map<String, Any?> } catch (_: Exception) { null }
            val date = c.getHeaderField("Date")
            ClockOffset.from(json?.get("serverTime") as? String, date, now())?.let { config.clockOffsetMs = it }
            ServerReply(status, json, date)
        } catch (_: Exception) {
            ServerReply(null, null)
        } finally {
            connection?.disconnect()
        }
    }

    private fun readCapped(input: InputStream): String = input.use {
        val bytes = it.readNBytesCompat(MAX_RESPONSE_BYTES)
        bytes.toString(Charsets.UTF_8)
    }

    private fun InputStream.readNBytesCompat(max: Int): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        val buf = ByteArray(8192)
        while (out.size() < max) {
            val n = read(buf, 0, minOf(buf.size, max - out.size()))
            if (n < 0) break
            out.write(buf, 0, n)
        }
        return out.toByteArray()
    }

    companion object {
        private const val TIMEOUT_MS = 15_000
        private const val MAX_RESPONSE_BYTES = 1 shl 20
    }
}
