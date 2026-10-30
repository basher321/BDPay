package com.bdpay.verifier

import java.time.Instant

/** Spec 13a batch rules: queued or failed rows only, oldest first, at most 50; the sms-ingest body. Pure. */
object UploadBatch {
    const val MAX = 50

    fun select(rows: List<QueueRow>, exclude: Set<String> = emptySet(), max: Int = MAX): List<QueueRow> =
        rows.asSequence()
            .filter { (it.syncStatus == "queued" || it.syncStatus == "failed") && it.id !in exclude }
            .sortedWith(compareBy<QueueRow>({ it.receivedAtMs }, { it.createdAtMs }, { it.id }))
            .take(max)
            .toList()

    /** {items: [{localId, sender, body, receivedAt (ISO UTC), simSlot, dedupeHash}]} as UTF-8 bytes. */
    fun body(rows: List<QueueRow>): ByteArray = JsonWriter.write(
        mapOf(
            "items" to rows.map {
                linkedMapOf(
                    "localId" to it.id,
                    "sender" to it.sender,
                    "body" to it.body,
                    "receivedAt" to Instant.ofEpochMilli(it.receivedAtMs).toString(),
                    "simSlot" to it.simSlot,
                    "dedupeHash" to it.dedupeHash,
                )
            },
        ),
    ).toByteArray(Charsets.UTF_8)
}
