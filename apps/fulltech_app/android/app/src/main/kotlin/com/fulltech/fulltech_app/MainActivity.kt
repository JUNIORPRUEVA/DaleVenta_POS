package com.daleventa.pos

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothSocket
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    private val channelName = "com.daleventa.pos/native_bluetooth_printer"
    private val logTag = "FullPOSBT"
    private val sppUuid: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
    private val mainHandler = Handler(Looper.getMainLooper())
    private var socket: BluetoothSocket? = null
    private var connectedAddress: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> {
                        val address = call.argument<String>("address").orEmpty()
                        val timeoutMs = call.argument<Int>("timeoutMs") ?: 5000
                        connect(address, timeoutMs, result)
                    }
                    "write" -> {
                        val address = call.argument<String>("address").orEmpty()
                        val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                        val timeoutMs = call.argument<Int>("timeoutMs") ?: 5000
                        val forceReconnect = call.argument<Boolean>("forceReconnect") ?: false
                        write(address, bytes, timeoutMs, forceReconnect, result)
                    }
                    "disconnect" -> {
                        closeSocket()
                        result.success(true)
                    }
                    "isConnected" -> result.success(socket?.isConnected == true)
                    "pairedDevices" -> result.success(pairedDevices())
                    else -> result.notImplemented()
                }
            }
    }

    private fun pairedDevices(): List<Map<String, String>> {
        return runCatching {
            val adapter = BluetoothAdapter.getDefaultAdapter() ?: return@runCatching emptyList()
            if (!adapter.isEnabled) return@runCatching emptyList()
            val devices = adapter.bondedDevices.map { device ->
                mapOf(
                    "name" to (device.name ?: ""),
                    "address" to device.address,
                )
            }
            Log.i(logTag, "pairedDevices count=${devices.size}")
            devices
        }.onFailure {
            Log.e(logTag, "pairedDevices exception", it)
        }.getOrDefault(emptyList())
    }

    private fun connect(address: String, timeoutMs: Int, result: MethodChannel.Result) {
        if (address.isBlank()) {
            result.success(false)
            return
        }
        thread(name = "FullPOS-BluetoothConnect") {
            val ok = runCatching {
                if (socket?.isConnected == true && connectedAddress == address) return@runCatching true
                closeSocket()
                val adapter = BluetoothAdapter.getDefaultAdapter() ?: return@runCatching false
                if (!adapter.isEnabled) return@runCatching false
                adapter.cancelDiscovery()
                val device = adapter.getRemoteDevice(address)
                Log.i(logTag, "connect start $address")
                val nextSocket = openSocket(device, timeoutMs)
                if (nextSocket == null) {
                    Log.w(logTag, "connect failed $address")
                    return@runCatching false
                }
                socket = nextSocket
                connectedAddress = address
                Log.i(logTag, "connect ok $address")
                true
            }.onFailure { Log.e(logTag, "connect exception $address", it) }.getOrDefault(false)
            mainHandler.post { result.success(ok) }
        }
    }

    private fun write(
        address: String,
        bytes: ByteArray,
        timeoutMs: Int,
        forceReconnect: Boolean,
        result: MethodChannel.Result,
    ) {
        if (bytes.isEmpty()) {
            result.success(false)
            return
        }
        thread(name = "FullPOS-BluetoothWrite") {
            val ok = runCatching {
                if (forceReconnect) {
                    closeSocket()
                }
                if (socket?.isConnected != true || connectedAddress != address) {
                    val adapter = BluetoothAdapter.getDefaultAdapter() ?: return@runCatching false
                    if (!adapter.isEnabled) return@runCatching false
                    adapter.cancelDiscovery()
                    closeSocket()
                    val device = adapter.getRemoteDevice(address)
                    Log.i(logTag, "write connect start $address")
                    val nextSocket = openSocket(device, timeoutMs)
                    if (nextSocket == null) {
                        Log.w(logTag, "write connect failed $address")
                        return@runCatching false
                    }
                    socket = nextSocket
                    connectedAddress = address
                }
                val output = socket?.outputStream ?: return@runCatching false
                Log.i(logTag, "write start $address bytes=${bytes.size}")
                output.write(bytes)
                output.flush()
                if (forceReconnect) {
                    Thread.sleep(250L)
                    closeSocket()
                }
                Log.i(logTag, "write ok $address bytes=${bytes.size}")
                true
            }.onFailure { Log.e(logTag, "write exception $address", it) }.getOrDefault(false)
            mainHandler.post { result.success(ok) }
        }
    }

    private fun openSocket(device: BluetoothDevice, timeoutMs: Int): BluetoothSocket? {
        val timeout = timeoutMs.toLong().coerceAtLeast(1500L)
        val attempts = listOfNotNull(
            runCatching { device.createRfcommSocketToServiceRecord(sppUuid) }.getOrNull(),
            runCatching { device.createInsecureRfcommSocketToServiceRecord(sppUuid) }.getOrNull(),
            runCatching {
                device.javaClass.getMethod("createRfcommSocket", Int::class.javaPrimitiveType)
                    .invoke(device, 1) as BluetoothSocket
            }.getOrNull(),
        )

        for ((index, candidate) in attempts.withIndex()) {
            val connectThread = thread(name = "FullPOS-RfcommConnect-$index") {
                runCatching { candidate.connect() }
                    .onFailure { Log.w(logTag, "socket attempt $index failed", it) }
            }
            connectThread.join(timeout)
            if (candidate.isConnected) return candidate
            runCatching { candidate.close() }
        }
        return null
    }

    private fun closeSocket() {
        runCatching { socket?.close() }
        socket = null
        connectedAddress = null
    }
}
