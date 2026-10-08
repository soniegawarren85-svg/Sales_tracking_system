package com.example.sales_tracking

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothSocket
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

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.sales_tracking/thermal_printer"
    private val serviceUuid = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile private var printerSocket: BluetoothSocket? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler(::handlePrinterCall)
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
                candidate = createSocket()
                candidate.connect()
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
