package com.bdpay.verifier

import android.content.Context
import android.os.Build
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkInfo
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/**
 * Spec 13a: how the three background jobs are started. Call off the main thread (uploadNow reads WorkManager's
 * state). Never logs.
 */
object Pipeline {
    const val UPLOAD = "sms-upload"
    const val STATUS = "sms-status"
    const val HEARTBEAT = "heartbeat"
    private const val HEARTBEAT_EVERY_MIN = 5L

    private val network = Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

    /**
     * At most one running and one waiting upload (UploadQueuePolicy). The state check and the enqueue happen under
     * one lock, so the receiver, the bridge and the network callback cannot decide at the same time.
     */
    @Synchronized
    fun uploadNow(context: Context) {
        val wm = WorkManager.getInstance(context)
        val jobs = try {
            wm.getWorkInfosForUniqueWork(UPLOAD).get().map { UploadQueuePolicy.Job(state(it.state), it.runAttemptCount) }
        } catch (_: Exception) {
            emptyList()
        }
        val policy = when (UploadQueuePolicy.decide(jobs)) {
            UploadQueuePolicy.Action.NONE -> return
            UploadQueuePolicy.Action.APPEND -> ExistingWorkPolicy.APPEND_OR_REPLACE
            UploadQueuePolicy.Action.REPLACE -> ExistingWorkPolicy.REPLACE
            UploadQueuePolicy.Action.KEEP -> ExistingWorkPolicy.KEEP
        }
        wm.enqueueUniqueWork(UPLOAD, policy, uploadRequest())
    }

    private fun state(s: WorkInfo.State) = when (s) {
        WorkInfo.State.RUNNING -> UploadQueuePolicy.State.RUNNING
        WorkInfo.State.BLOCKED -> UploadQueuePolicy.State.BLOCKED
        WorkInfo.State.ENQUEUED -> UploadQueuePolicy.State.ENQUEUED
        else -> UploadQueuePolicy.State.FINISHED
    }

    private fun uploadRequest(): OneTimeWorkRequest = OneTimeWorkRequestBuilder<SmsUploadWorker>()
        .setConstraints(network)
        .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
        .apply {
            // Plan 13a D149: expedited only on Android 12+, where it needs no foreground notification.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
        }
        .build()

    fun refreshNow(context: Context) {
        WorkManager.getInstance(context).enqueueUniqueWork(
            STATUS,
            ExistingWorkPolicy.KEEP,
            OneTimeWorkRequestBuilder<StatusRefreshWorker>().setConstraints(network).build(),
        )
    }

    /**
     * [next] true: called by HeartbeatWorker itself - its successor runs 5 minutes after it (APPEND_OR_REPLACE;
     * REPLACE would cancel the running worker). false: app start / after an upload - KEEP restarts a broken chain
     * without doubling a healthy one.
     */
    fun scheduleHeartbeat(context: Context, next: Boolean) {
        val request = OneTimeWorkRequestBuilder<HeartbeatWorker>()
            .setConstraints(network)
            .apply { if (next) setInitialDelay(HEARTBEAT_EVERY_MIN, TimeUnit.MINUTES) }
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            HEARTBEAT,
            if (next) ExistingWorkPolicy.APPEND_OR_REPLACE else ExistingWorkPolicy.KEEP,
            request,
        )
    }
}
