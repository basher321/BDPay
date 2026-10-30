package com.bdpay.verifier

import java.time.Instant
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

/** Server time minus device time, from a response's serverTime (ISO) or its HTTP Date header. Pure. */
object ClockOffset {
    fun fromServerTime(iso: String?, deviceNowMs: Long): Long? =
        try { iso?.let { Instant.parse(it).toEpochMilli() - deviceNowMs } } catch (_: Exception) { null }

    fun fromDateHeader(header: String?, deviceNowMs: Long): Long? =
        try {
            header?.let {
                ZonedDateTime.parse(it, DateTimeFormatter.RFC_1123_DATE_TIME).toInstant().toEpochMilli() - deviceNowMs
            }
        } catch (_: Exception) {
            null
        }

    /** serverTime when present (millisecond accurate), else the Date header (second accurate). */
    fun from(serverTimeIso: String?, dateHeader: String?, deviceNowMs: Long): Long? =
        fromServerTime(serverTimeIso, deviceNowMs) ?: fromDateHeader(dateHeader, deviceNowMs)

    fun signedTimestamp(deviceNowMs: Long, offsetMs: Long): Long = deviceNowMs + offsetMs
}
