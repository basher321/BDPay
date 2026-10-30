package com.bdpay.verifier

/**
 * Plan 13a D148: which rows are being sent right now. Kept in memory only (the sms_inbox CHECK has no "sending",
 * and spec 06 never stores it). After a crash the rows are simply still queued / failed and are sent again; the
 * server answers duplicate, so nothing is counted twice.
 */
object UploadState {
    val sending: MutableSet<String> = HashSet()

    fun snapshot(): Set<String> = synchronized(sending) { HashSet(sending) }
}
