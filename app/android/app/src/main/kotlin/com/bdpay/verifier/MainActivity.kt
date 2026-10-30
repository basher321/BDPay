package com.bdpay.verifier

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var bridge: SmsBridge? = null

    // Spec 06: the SMS channel (decision D14).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = SmsBridge(applicationContext, this).also { it.attach(flutterEngine.dartExecutor.binaryMessenger) }
        // Spec 13a: start (or keep) the heartbeat chain; WorkManager keeps it across reboots.
        val ctx = applicationContext
        SmsPipeline.executor.execute { try { Pipeline.scheduleHeartbeat(ctx, next = false) } catch (_: Exception) { } }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        bridge?.detach()
        bridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        bridge?.onPermissionResult(requestCode, permissions, grantResults)
    }
}
