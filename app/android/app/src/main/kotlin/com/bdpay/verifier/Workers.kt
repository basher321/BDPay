package com.bdpay.verifier

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/*
 * Spec 13a background jobs. Thin: each wires a plain-Kotlin run (UploadRun, StatusRun, HeartbeatRun) to the real
 * store, server client and config. doWork never lets an exception escape - WorkManager would log its message.
 */

class SmsUploadWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            val ctx = applicationContext
            val config = DeviceConfig(ctx)
            val run = UploadRun(SmsStore.get(ctx), ServerClient(config), config, UploadState.sending) { System.currentTimeMillis() }
            val verdict = run.run()
            SmsBridge.notifyInbox()
            Pipeline.scheduleHeartbeat(ctx, next = false) // restarts a broken heartbeat chain (plan D160)
            if (run.anyUploaded) Pipeline.refreshNow(ctx)
            if (verdict == UploadRun.Verdict.RETRY) Result.retry() else Result.success()
        } catch (_: Throwable) {
            Result.retry()
        }
    }
}

class StatusRefreshWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        try {
            val ctx = applicationContext
            val config = DeviceConfig(ctx)
            if (StatusRun(SmsStore.get(ctx), ServerClient(config), config) { System.currentTimeMillis() }.run()) {
                SmsBridge.notifyInbox()
            }
            Result.success()
        } catch (_: Throwable) {
            Result.success() // the next heartbeat or the app's 30-second refresh tries again
        }
    }
}

class HeartbeatWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val ctx = applicationContext
        try {
            if (Heartbeat.runOnce(ctx)) Pipeline.refreshNow(ctx)
        } catch (_: Throwable) {
            // nothing logged; the next heartbeat runs anyway
        } finally {
            try { Pipeline.scheduleHeartbeat(ctx, next = true) } catch (_: Throwable) { }
        }
        Result.success()
    }
}

/** One heartbeat with the real phone state; also used by the bridge's heartbeatNow(). */
object Heartbeat {
    fun runOnce(context: Context): Boolean {
        val ctx = context.applicationContext
        val config = DeviceConfig(ctx)
        val prefs = NativePrefs(ctx)
        val env = object : HeartbeatEnv {
            override val appVersion: String = appVersion(ctx)
            override val smsPermission = DeviceChecks.smsPermission(ctx)
            override val batteryOptimizationOff = DeviceChecks.batteryOptimizationOff(ctx)
            override val monitoring = prefs.monitoring
            override val queueCount = SmsStore.get(ctx).countPending(config.heldRowIds)
        }
        return HeartbeatRun(ServerClient(config), config, env, RulesStore(ctx)) { System.currentTimeMillis() }.run()
    }

    private fun appVersion(ctx: Context): String = try {
        ctx.packageManager.getPackageInfo(ctx.packageName, 0).versionName ?: "0"
    } catch (_: Exception) {
        "0"
    }
}
