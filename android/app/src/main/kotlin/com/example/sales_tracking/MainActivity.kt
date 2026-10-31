package com.example.sales_tracking

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.IOException
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.sales_tracking/thermal_printer"
    private val serviceUuid = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val updatePermissionRequest = 7412
    private var pendingNotificationResult: MethodChannel.Result? = null
    private val updateChannelId = "shorebird_updates"
    private val updatePromptExtra = "openShorebirdUpdate"
    private var updateMethodChannel: MethodChannel? = null
    private var pendingUpdatePrompt = false
    @Volatile private var printerSocket: BluetoothSocket? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler(::handlePrinterCall)
        pendingUpdatePrompt = consumeUpdatePromptIntent(intent)
        updateMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.sales_tracking/updates"
        )
        updateMethodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "showUpdateAvailable" -> showUpdateNotification(result)
                "showUpdateApplied" -> {
                    showUpdateAppliedNotification()
                    result.success(null)
                }
                "consumeUpdatePrompt" -> {
                    val pending = pendingUpdatePrompt
                    pendingUpdatePrompt = false
                    result.success(pending)
                }
                "clearUpdateNotification" -> {
                    (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                        .cancel(7413)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (consumeUpdatePromptIntent(intent)) {
            pendingUpdatePrompt = true
            updateMethodChannel?.invokeMethod("openUpdatePrompt", null)
        }
    }

    private fun consumeUpdatePromptIntent(intent: Intent?): Boolean {
        val requested = intent?.getBooleanExtra(updatePromptExtra, false) == true
        if (requested) intent?.removeExtra(updatePromptExtra)
        return requested
    }

    private fun showUpdateNotification(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED) {
            pendingNotificationResult = result
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                updatePermissionRequest)
            return
        }
        postUpdateNotification()
        result.success(true)
    }

    private fun postUpdateNotification() {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(
                updateChannelId, "App updates", NotificationManager.IMPORTANCE_DEFAULT
            ).apply { description = "Shorebird app update alerts" })
        }
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = launchIntent?.let {
            it.flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            it.putExtra(updatePromptExtra, true)
            PendingIntent.getActivity(this, 7413, it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, updateChannelId) else Notification.Builder(this)
        builder.setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Update ready")
            .setContentText("Tap to open Angel’z Bites Cupcakes and update the app.")
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
        manager.notify(7413, builder.build())
    }

    private fun showUpdateAppliedNotification() {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(
                updateChannelId, "App updates", NotificationManager.IMPORTANCE_DEFAULT
            ).apply { description = "Shorebird app update alerts" })
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, updateChannelId) else Notification.Builder(this)
        builder.setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle("Update successful")
            .setContentText("You’re now using the latest Angel’z Bites Cupcakes app.")
            .setAutoCancel(true)
        manager.notify(7414, builder.build())
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != updatePermissionRequest) return
        val result = pendingNotificationResult ?: return
        pendingNotificationResult = null
        val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
        if (granted) postUpdateNotification()
        result.success(granted)
    }

    private fun handlePrinterCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "bluetoothEnabled" -> result.success(
                BluetoothAdapter.getDefaultAdapter()?.isEnabled == true
            )
            "pairedPrinters" -> {
                try {
                    val devices = BluetoothAdapter.getDefaultAdapter()
                        ?.bondedDevices
                        ?.map { device ->
                            mapOf(
                                "name" to (device.name ?: ""),
                                "address" to device.address
                            )
                        }
                        ?: emptyList()
                    result.success(devices)
                } catch (error: Exception) {
                    result.error("PRINTER_SCAN_FAILED", error.message, null)
                }
            }
            "connectionStatus" -> result.success(printerSocket?.isConnected == true)
            "connect" -> runInBackground(result, "CONNECT_FAILED") {
                val address = call.argument<String>("address")
                    ?: throw IllegalArgumentException("A printer address is required.")
                connectToPrinter(address)
            }
            "disconnect" -> runInBackground(result, "DISCONNECT_FAILED") {
                printerSocket?.close()
                printerSocket = null
                true
            }
            "writeBytes" -> runInBackground(result, "PRINT_FAILED") {
                val bytes = call.argument<List<Int>>("bytes")
                    ?: throw IllegalArgumentException("Receipt data is missing.")
                val socket = printerSocket
                    ?: throw IOException("The printer is disconnected.")
                if (!socket.isConnected) {
                    printerSocket = null
                    throw IOException("The printer is disconnected.")
                }
                socket.outputStream.write(bytes.map(Int::toByte).toByteArray())
                socket.outputStream.flush()
                true
            }
            else -> result.notImplemented()
        }
    }

    private fun connectToPrinter(address: String): Boolean {
        val adapter = BluetoothAdapter.getDefaultAdapter()
            ?: throw IOException("This device does not support Bluetooth.")
        if (!adapter.isEnabled) {
            throw IOException("Bluetooth is turned off. Enable it and try again.")
        }
        adapter.cancelDiscovery()
        printerSocket?.let {
            try {
                it.close()
            } catch (_: IOException) {
                // Continue with a fresh socket.
            }
        }
        printerSocket = null

        val device = adapter.getRemoteDevice(address)
        val failures = mutableListOf<String>()
        val socketFactories: List<Pair<String, () -> BluetoothSocket>> = listOf(
            "secure SPP" to { device.createRfcommSocketToServiceRecord(serviceUuid) },
            "insecure SPP" to {
                device.createInsecureRfcommSocketToServiceRecord(serviceUuid)
            },
            "Bluetooth channel 1" to {
                val method = device.javaClass.getMethod(
                    "createRfcommSocket",
                    Int::class.javaPrimitiveType
                )
                method.invoke(device, 1) as BluetoothSocket
            }
        )

        for ((mode, createSocket) in socketFactories) {
            var candidate: BluetoothSocket? = null
            try {
                val socket = createSocket()
                candidate = socket
                val finished = AtomicBoolean(false)
                val cancelConnect = Runnable {
                    if (finished.compareAndSet(false, true)) {
                        try { socket.close() } catch (_: IOException) { }
                    }
                }
                mainHandler.postDelayed(cancelConnect, 2000)
                try {
                    socket.connect()
                    if (!finished.compareAndSet(false, true)) {
                        throw IOException("Printer connection timed out.")
                    }
                } finally {
                    finished.set(true)
                    mainHandler.removeCallbacks(cancelConnect)
                }
                if (candidate.isConnected) {
                    printerSocket = candidate
                    return true
                }
                throw IOException("Socket did not report a connected state.")
            } catch (error: Exception) {
                try {
                    candidate?.close()
                } catch (_: IOException) {
                    // Ignore cleanup failures while trying the next connection mode.
                }
                val reason = error.message ?: error.javaClass.simpleName
                failures.add("$mode: $reason")
                Log.w("ThermalPrinter", "$mode connection failed for $address", error)
            }
        }

        throw IOException(
            "Could not connect to this printer. Make sure it is powered on, " +
                "not connected to another device, and supports Bluetooth Classic " +
                "(SPP). ${failures.joinToString("; ")}"
        )
    }

    private fun runInBackground(
        result: MethodChannel.Result,
        errorCode: String,
        action: () -> Any
    ) {
        ioExecutor.execute {
            try {
                val value = action()
                mainHandler.post { result.success(value) }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error(errorCode, error.message ?: error.javaClass.simpleName, null)
                }
            }
        }
    }

    override fun onDestroy() {
        try {
            printerSocket?.close()
        } catch (_: IOException) {
            // The activity is shutting down; the socket is no longer usable.
        }
        printerSocket = null
        ioExecutor.shutdownNow()
        super.onDestroy()
    }
}
