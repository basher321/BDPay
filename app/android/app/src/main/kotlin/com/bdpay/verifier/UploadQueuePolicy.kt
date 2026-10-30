package com.bdpay.verifier

/**
 * How uploadNow() enqueues, from the jobs already under the unique name "sms-upload". Never two uploads at once:
 * a running upload only ever gets one follow-up appended after it. Pure.
 */
object UploadQueuePolicy {
    enum class State { RUNNING, BLOCKED, ENQUEUED, FINISHED }

    data class Job(val state: State, val runAttemptCount: Int)

    enum class Action { NONE, APPEND, REPLACE, KEEP }

    fun decide(jobs: List<Job>): Action {
        val running = jobs.any { it.state == State.RUNNING }
        val waiting = jobs.filter { it.state == State.ENQUEUED || it.state == State.BLOCKED }
        return when {
            // A follow-up already waits behind the running one (or the waiting one never ran): it picks up new rows.
            running -> if (waiting.isEmpty()) Action.APPEND else Action.NONE
            // Waiting out a retry backoff (can grow to hours): start again now. It is not running, so no overlap.
            waiting.any { it.runAttemptCount > 0 } -> Action.REPLACE
            waiting.isNotEmpty() -> Action.NONE
            else -> Action.KEEP
        }
    }
}
