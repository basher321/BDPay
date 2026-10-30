package com.bdpay.verifier

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.Network
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel "bdpay/sms" and EventChannel "bdpay/sms/events". Errors use fixed codes and never carry SMS text.
 * Events: "inbox", "online", "offline", and (spec 13a) "pipeline" and "rules".
 */
class SmsBridge(private val context: Context, private val activity: Activity) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private var methods: MethodChannel? = null
    private var events: EventChannel? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
    private var pendingPermission: MethodChannel.Result? = null
    private val prefs = NativePrefs(context)

    fun attach(messenger: BinaryMessenger) {
        methods = MethodChannel(messenger, METHODS).also { it.setMethodCallHandler(this) }
        events = EventChannel(messenger, EVENTS).also { it.setStreamHandler(this) }
    }

    fun detach() {
        methods?.setMethodCallHandler(null)
        events?.setStreamHandler(null)
        onCancel(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getParserRules" -> result.success(SmsPipeline.rulesJson(context))
                "listInbox" -> background(result) { SmsStore.get(context).listInbox(DeviceConfig(context).heldRowIds) }
                "updateSync" -> {
                    val id = call.argument<String>("id") ?: return badArgs(result)
                    val sync = call.argument<String>("syncStatus") ?: return badArgs(result)
                    val verify = call.argument<String>("verifyStatus") ?: return badArgs(result)
                    val retry = call.argument<Int>("retryCount") ?: return badArgs(result)
                    val code = call.argument<Int>("serverCode")
                    val message = call.argument<String>("serverMessage")
                    background(result) {
                        SmsStore.get(context).updateSync(id, sync, verify, retry, code, message)
                        notifyInbox()
                        null
                    }
                }
                "simulateIncoming" -> {
                    val sender = call.argument<String>("sender") ?: return badArgs(result)
                    val body = call.argument<String>("body") ?: return badArgs(result)
                    val sim = call.argument<String>("simSlot")?.takeIf { it in SIM_SLOTS } ?: return badArgs(result)
                    background(result) {
                        SmsPipeline.process(context, sender, body, System.currentTimeMillis(), sim, SmsFilter.SOURCE_SIMULATED).name
                    }
                }
                "setMonitoring" -> {
                    prefs.monitoring = call.arguments as? Boolean ?: return badArgs(result)
                    result.success(null)
                }
                "setEnabledOperators" -> {
                    val list = (call.arguments as? List<*>)?.filterIsInstance<String>() ?: return badArgs(result)
                    prefs.enabledOperators = list.toSet()
                    result.success(null)
                }
                "setAutoStartConfirmed" -> {
                    prefs.autoStartConfirmed = call.arguments as? Boolean ?: return badArgs(result)
                    result.success(null)
                }
                "getHealth" -> result.success(
                    mapOf(
                        "smsPermission" to DeviceChecks.smsPermission(context),
                        "batteryOptimizationOff" to DeviceChecks.batteryOptimizationOff(context),
                        "internetOnline" to DeviceChecks.internetOnline(context),
                        "maker" to DeviceChecks.maker(),
                        // Spec 13a: sent with device-register.
                        "androidVersion" to android.os.Build.VERSION.RELEASE,
                        "monitoring" to prefs.monitoring,
                        "enabledOperators" to prefs.enabledOperators.toList(),
                        "autoStartConfirmed" to prefs.autoStartConfirmed,
                    ),
                )
                "requestSmsPermission" -> requestSmsPermission(result)
                "requestBatteryExemption" -> {
                    activity.startActivity(DeviceChecks.batteryExemptionIntent(context))
                    result.success(null)
                }
                "openAppSettings" -> {
                    activity.startActivity(DeviceChecks.appSettingsIntent(context))
                    result.success(null)
                }
                // Spec 13a additions. Key material never crosses the channel: only the public key.
                "getInstallId" -> result.success(DeviceKeys.installId(context))
                "getDevicePublicKey" -> background(result) { DeviceKeys.publicKeySpki() }
                "setDeviceConfig" -> {
                    val deviceId = call.argument<String>("deviceId") ?: return badArgs(result)
                    val url = call.argument<String>("functionsUrl") ?: return badArgs(result)
                    val serverTime = call.argument<String>("serverTime")
                    val merchantId = call.argument<String>("merchantId") ?: return badArgs(result)
                    background(result) {
                        val config = DeviceConfig(context)
                        // Plan 13a D171: hold the previous merchant's unsent rows before this device can upload.
                        config.held = MerchantHold.onRegister(config.merchantId, merchantId, config.held, SmsStore.get(context).pendingIds())
                        config.merchantId = merchantId
                        prefs.resumeAfterLogin()
                        config.deviceId = deviceId
                        config.functionsUrl = url.trimEnd('/')
                        config.revoked = false
                        ClockOffset.fromServerTime(serverTime, System.currentTimeMillis())?.let { config.clockOffsetMs = it }
                        Pipeline.scheduleHeartbeat(context, next = false)
                        null
                    }
                }
                "clearDeviceConfig" -> background(result) {
                    prefs.pauseForLogout() // plan 13a D171 (also covers the banner logout, which skips deactivate)
                    val config = DeviceConfig(context)
                    config.deviceId = null
                    config.revoked = false
                    null
                }
                "uploadNow" -> background(result) { Pipeline.uploadNow(context); null }
                "refreshNow" -> background(result) { Pipeline.refreshNow(context); null }
                "heartbeatNow" -> background(result) { Heartbeat.runOnce(context) }
                "deactivateDevice" -> background(result) {
                    // Plan 13a D171: stop catching SMS first. This runs on the SMS thread, so an SMS being stored
                    // right now finishes before; none is stored after. Undone when the server cannot be reached.
                    prefs.pauseForLogout()
                    val config = DeviceConfig(context)
                    val ok = ServerClient(config).post("device-deactivate", "{}".toByteArray(Charsets.UTF_8)).status == 200
                    if (!ok) prefs.resumeAfterLogin()
                    ok
                }
                "getPipelineState" -> background(result) { DeviceConfig(context).state().toMap() }
                "setAutoSend" -> {
                    prefs.autoSend = call.arguments as? Boolean ?: return badArgs(result)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (_: Exception) {
            result.error("failed", null, null)
        }
    }

    private fun badArgs(result: MethodChannel.Result) = result.error("bad_args", null, null)

    /** Runs [work] on the SMS thread and answers on the main thread. */
    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        SmsPipeline.executor.execute {
            val outcome = try { Result.success(work()) } catch (e: Exception) { Result.failure(e) }
            main.post {
                outcome.fold({ result.success(it) }, { result.error("failed", null, null) })
            }
        }
    }

    private fun requestSmsPermission(result: MethodChannel.Result) {
        if (DeviceChecks.smsPermission(context)) {
            result.success(true)
            return
        }
        pendingPermission?.success(false)
        pendingPermission = result
        // READ_PHONE_STATE is optional (SIM slot only); denying it is fine.
        activity.requestPermissions(
            arrayOf(Manifest.permission.RECEIVE_SMS, Manifest.permission.READ_PHONE_STATE),
            PERMISSION_REQUEST,
        )
    }

    /** Called by MainActivity. */
    fun onPermissionResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode != PERMISSION_REQUEST) return
        val i = permissions.indexOf(Manifest.permission.RECEIVE_SMS)
        val granted = i >= 0 && grantResults.getOrNull(i) == PackageManager.PERMISSION_GRANTED
        pendingPermission?.success(granted)
        pendingPermission = null
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        eventSink = sink
        val cm = context.getSystemService(ConnectivityManager::class.java) ?: return
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = sendNetwork()
            override fun onLost(network: Network) = sendNetwork()
        }
        try {
            cm.registerDefaultNetworkCallback(callback)
            networkCallback = callback
        } catch (_: Exception) {
            // Without the callback the app still reads the state on start and resume.
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        val cm = context.getSystemService(ConnectivityManager::class.java)
        networkCallback?.let { cb -> try { cm?.unregisterNetworkCallback(cb) } catch (_: Exception) { } }
        networkCallback = null
    }

    private fun sendNetwork() {
        val online = DeviceChecks.internetOnline(context)
        main.post { eventSink?.success(if (online) "online" else "offline") }
        // Spec 13a: the internet came back -> send what is waiting (autoSend on).
        if (online && prefs.autoSend) SmsPipeline.executor.execute { try { Pipeline.uploadNow(context) } catch (_: Exception) { } }
    }

    companion object {
        private const val METHODS = "bdpay/sms"
        private const val EVENTS = "bdpay/sms/events"
        private const val PERMISSION_REQUEST = 6001
        private val SIM_SLOTS = setOf("sim1", "sim2", "unknown")
        private val main = Handler(Looper.getMainLooper())

        @Volatile private var eventSink: EventChannel.EventSink? = null

        /** A row was added or changed. Safe from any thread; does nothing when the app UI is not running. */
        fun notifyInbox() = notifyEvent("inbox")

        /** "inbox", "pipeline" or "rules". Safe from any thread. */
        fun notifyEvent(name: String) {
            main.post { eventSink?.success(name) }
        }
    }
}
