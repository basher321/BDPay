package com.bdpay.verifier

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper

/**
 * The phone's SMS queue (table sms_inbox). Rows are never deleted by the app.
 * Every query uses ContentValues or bound "?" arguments: the SMS body is untrusted text.
 * Version 2 (spec 13a) only adds columns; see [SmsStoreSchema].
 */
class SmsStore private constructor(context: Context) :
    SQLiteOpenHelper(context, DB_NAME, null, SmsStoreSchema.VERSION), InboxWriter, UploadRows, StatusRows {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(SmsStoreSchema.CREATE_V1)
        for ((column, type) in SmsStoreSchema.V2_COLUMNS) db.execSQL(SmsStoreSchema.addColumn(column, type))
    }

    /** Runs inside SQLiteOpenHelper's transaction. Adds columns only; never drops or rebuilds the table. */
    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            val existing = columns(db)
            for ((column, type) in SmsStoreSchema.V2_COLUMNS) {
                if (column !in existing) db.execSQL(SmsStoreSchema.addColumn(column, type))
            }
        }
    }

    private fun columns(db: SQLiteDatabase): Set<String> {
        val out = HashSet<String>()
        db.rawQuery("PRAGMA table_info($TABLE)", null).use { c ->
            val i = c.getColumnIndexOrThrow("name")
            while (c.moveToNext()) out.add(c.getString(i))
        }
        return out
    }

    override fun insertIfNew(row: InboxRow): Boolean {
        val values = ContentValues().apply {
            put("id", row.id)
            put("sender", row.sender)
            put("body", row.body)
            put("received_at_ms", row.receivedAtMs)
            put("sim_slot", row.simSlot)
            put("dedupe_hash", row.dedupeHash)
            put("created_at_ms", row.createdAtMs)
            put("operator", row.operator)
            put("source", row.source)
        }
        return writableDatabase.insertWithOnConflict(TABLE, null, values, SQLiteDatabase.CONFLICT_IGNORE) != -1L
    }

    /**
     * All rows, newest first, as channel-ready maps. Rows being sent right now report sync_status "sending".
     * [hidden] = rows held for another merchant (plan 13a D171); they are not listed.
     */
    fun listInbox(hidden: Set<String> = emptySet()): List<Map<String, Any?>> {
        val sending = UploadState.snapshot()
        val out = ArrayList<Map<String, Any?>>()
        readableDatabase.query(TABLE, null, null, null, null, null, "received_at_ms DESC, created_at_ms DESC").use { c ->
            while (c.moveToNext()) {
                val id = c.str("id")!!
                if (id in hidden) continue
                out.add(
                    mapOf(
                        "id" to id,
                        "sender" to c.str("sender"),
                        "body" to c.str("body"),
                        "received_at_ms" to c.long("received_at_ms"),
                        "sim_slot" to c.str("sim_slot"),
                        "sync_status" to if (id in sending) "sending" else c.str("sync_status"),
                        "verify_status" to c.str("verify_status"),
                        "retry_count" to c.long("retry_count")!!.toInt(),
                        "server_code" to c.long("server_code")?.toInt(),
                        "server_message" to c.str("server_message"),
                        "created_at_ms" to c.long("created_at_ms"),
                        "operator" to c.str("operator"),
                        "source" to c.str("source"),
                        "server_sms_id" to c.str("server_sms_id"),
                        "claim_json" to c.str("claim_json"),
                    ),
                )
            }
        }
        return out
    }

    /** Writes a send result from Dart (tests / mock path only). "sending" is never stored. */
    fun updateSync(
        id: String,
        syncStatus: String,
        verifyStatus: String,
        retryCount: Int,
        serverCode: Int?,
        serverMessage: String?,
    ): Boolean {
        require(syncStatus in SYNC_STATUSES) { "bad syncStatus" }
        require(verifyStatus in VERIFY_STATUSES) { "bad verifyStatus" }
        val values = ContentValues().apply {
            put("sync_status", syncStatus)
            put("verify_status", verifyStatus)
            put("retry_count", retryCount)
            if (serverCode == null) putNull("server_code") else put("server_code", serverCode)
            if (serverMessage == null) putNull("server_message") else put("server_message", serverMessage)
        }
        return writableDatabase.update(TABLE, values, "id = ?", arrayOf(id)) > 0
    }

    private fun queueRows(selection: String, args: Array<String>, limit: String? = null): List<QueueRow> {
        val out = ArrayList<QueueRow>()
        readableDatabase.query(TABLE, null, selection, args, null, null, "received_at_ms ASC, created_at_ms ASC", limit).use { c ->
            while (c.moveToNext()) {
                out.add(
                    QueueRow(
                        id = c.str("id")!!,
                        sender = c.str("sender")!!,
                        body = c.str("body")!!,
                        receivedAtMs = c.long("received_at_ms")!!,
                        simSlot = c.str("sim_slot")!!,
                        dedupeHash = c.str("dedupe_hash")!!,
                        syncStatus = c.str("sync_status")!!,
                        verifyStatus = c.str("verify_status")!!,
                        retryCount = c.long("retry_count")!!.toInt(),
                        serverSmsId = c.str("server_sms_id"),
                        createdAtMs = c.long("created_at_ms")!!,
                    ),
                )
            }
        }
        return out
    }

    override fun selectUploadable(): List<QueueRow> =
        queueRows("sync_status IN ('queued', 'failed')", emptyArray(), UPLOAD_SCAN_LIMIT)

    /** Guarded: a row that is no longer queued or failed is left alone. One transaction. */
    override fun applyUpload(updates: List<RowUpdate>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            for (u in updates) {
                require(u.syncStatus in SYNC_STATUSES) { "bad syncStatus" }
                val values = ContentValues().apply {
                    put("sync_status", u.syncStatus)
                    put("retry_count", u.retryCount)
                    if (u.serverCode != null) put("server_code", u.serverCode)
                    if (u.syncStatus == "sent") {
                        put("verify_status", u.verifyStatus?.takeIf { it in VERIFY_STATUSES } ?: "pending")
                        if (u.serverMessage == null) putNull("server_message") else put("server_message", u.serverMessage)
                        if (u.serverSmsId != null) put("server_sms_id", u.serverSmsId)
                    }
                }
                db.update(TABLE, values, "id = ? AND sync_status IN ('queued', 'failed')", arrayOf(u.id))
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    override fun selectForRefresh(nowMs: Long): List<QueueRow> = queueRows(
        "server_sms_id IS NOT NULL AND verify_status IN ('pending', 'mismatch') AND received_at_ms >= ?",
        arrayOf((nowMs - StatusRefresh.WINDOW_MS).toString()),
    )

    /** Writes only the server's verdict fields. One transaction. */
    override fun applyStatus(updates: List<StatusUpdate>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            for (u in updates) {
                val values = ContentValues().apply {
                    put("verify_status", u.verifyStatus)
                    if (u.serverMessage == null) putNull("server_message") else put("server_message", u.serverMessage)
                    if (u.claimJson == null) putNull("claim_json") else put("claim_json", u.claimJson)
                    put("last_status_check_ms", u.checkedAtMs)
                }
                db.update(TABLE, values, "server_sms_id = ?", arrayOf(u.serverSmsId))
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    /** Ids of the unsent rows (queued or failed; rows being sent are still one of those in the table). */
    fun pendingIds(): Set<String> {
        val out = HashSet<String>()
        readableDatabase.rawQuery("SELECT id FROM $TABLE WHERE sync_status IN ('queued', 'failed')", null).use { c ->
            while (c.moveToNext()) out.add(c.getString(0))
        }
        return out
    }

    /** The heartbeat's queueCount: queued + sending + failed, without rows held for another merchant. */
    fun countPending(hidden: Set<String> = emptySet()): Int = (pendingIds() - hidden).size

    private fun Cursor.str(col: String): String? = getColumnIndexOrThrow(col).let { if (isNull(it)) null else getString(it) }

    private fun Cursor.long(col: String): Long? = getColumnIndexOrThrow(col).let { if (isNull(it)) null else getLong(it) }

    companion object {
        private const val DB_NAME = "bdpay_sms.db"
        private const val TABLE = "sms_inbox"
        private const val UPLOAD_SCAN_LIMIT = "1000"
        private val SYNC_STATUSES = setOf("queued", "sent", "failed")

        @Volatile private var instance: SmsStore? = null

        fun get(context: Context): SmsStore =
            instance ?: synchronized(this) {
                instance ?: SmsStore(context.applicationContext).also { instance = it }
            }
    }
}

/** The sms_inbox schema as plain text, so the JVM test can check the upgrade adds columns only (plan 13a D152). */
object SmsStoreSchema {
    const val VERSION = 2

    val CREATE_V1 = """
        CREATE TABLE sms_inbox (
          id TEXT PRIMARY KEY,
          sender TEXT NOT NULL,
          body TEXT NOT NULL,
          received_at_ms INTEGER NOT NULL,
          sim_slot TEXT NOT NULL CHECK (sim_slot IN ('sim1', 'sim2', 'unknown')),
          dedupe_hash TEXT NOT NULL UNIQUE,
          sync_status TEXT NOT NULL DEFAULT 'queued' CHECK (sync_status IN ('queued', 'sent', 'failed')),
          verify_status TEXT NOT NULL DEFAULT 'pending'
            CHECK (verify_status IN ('pending', 'verified', 'mismatch', 'rejected')),
          retry_count INTEGER NOT NULL DEFAULT 0,
          server_code INTEGER NULL,
          server_message TEXT NULL,
          created_at_ms INTEGER NOT NULL,
          operator TEXT NOT NULL CHECK (operator IN ('bkash', 'nagad', 'rocket', 'upay')),
          source TEXT NOT NULL DEFAULT 'sms' CHECK (source IN ('sms', 'simulated'))
        )
    """.trimIndent()

    /** Spec 13a: the only schema change of version 2. */
    val V2_COLUMNS = listOf(
        "server_sms_id" to "TEXT NULL",
        "claim_json" to "TEXT NULL",
        "last_status_check_ms" to "INTEGER NULL",
    )

    fun addColumn(column: String, type: String) = "ALTER TABLE sms_inbox ADD COLUMN $column $type"
}
