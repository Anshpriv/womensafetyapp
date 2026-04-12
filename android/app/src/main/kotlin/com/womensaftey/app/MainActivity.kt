package com.womensaftey.app

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.telephony.SmsManager
import android.telephony.TelephonyManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val smsChannel = "sms_channel"
    private val dualCameraChannel = "dual_camera_channel"
    private val deviceStatsChannel = "device_stats_channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, smsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sendSms" -> {
                        val phone = call.argument<String>("phone")
                        val message = call.argument<String>("message")

                        if (phone.isNullOrEmpty() || message.isNullOrEmpty()) {
                            result.error("INVALID", "Phone or message missing", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val smsManager = SmsManager.getDefault()
                            val parts = smsManager.divideMessage(message)
                            smsManager.sendMultipartTextMessage(phone, null, parts, null, null)

                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SMS_FAILED", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, dualCameraChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isDualRecordingSupported" -> {
                        result.success(DualCameraRecordingActivity.isConcurrentCameraSupported(this))
                    }

                    "startDualRecording" -> {
                        val outputPath = call.argument<String>("outputPath")
                        if (outputPath.isNullOrBlank()) {
                            result.error("INVALID", "Output path missing", null)
                            return@setMethodCallHandler
                        }

                        try {
                            val intent = DualCameraRecordingActivity.createIntent(this, outputPath)
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("DUAL_CAMERA_FAILED", e.message, null)
                        }
                    }

                    "stopDualRecording" -> {
                        DualCameraRecordingActivity.stopActiveRecording()
                        result.success(true)
                    }

                    "isDualRecordingActive" -> {
                        result.success(DualCameraRecordingActivity.isRecordingActive())
                    }

                    "consumeLastRecordingPath" -> {
                        result.success(DualCameraRecordingActivity.consumeLastRecordingPath(this))
                    }

                    "consumeLastRecordingError" -> {
                        result.success(DualCameraRecordingActivity.consumeLastRecordingError(this))
                    }

                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceStatsChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDeviceStats" -> {
                        try {
                            result.success(getDeviceStats())
                        } catch (e: Exception) {
                            result.error("DEVICE_STATS_FAILED", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    private fun getDeviceStats(): Map<String, Any?> {
        val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val batteryLevel = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)

        val connectivityManager =
            getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network = connectivityManager.activeNetwork
        val capabilities = connectivityManager.getNetworkCapabilities(network)

        val connectionType = when {
            capabilities == null -> "Offline"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "Wi-Fi"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "Mobile"
            capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "Ethernet"
            else -> "Connected"
        }

        val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        val hasPhonePermission = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.READ_PHONE_STATE
        ) == PackageManager.PERMISSION_GRANTED

        val signalLevel = if (hasPhonePermission) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                telephonyManager.signalStrength?.level
            } else {
                null
            }
        } else {
            null
        }

        val signalLabel = when (signalLevel) {
            4 -> "Excellent"
            3 -> "Good"
            2 -> "Fair"
            1 -> "Weak"
            0 -> "No signal"
            else -> if (connectionType == "Wi-Fi") "Wi-Fi connected" else "Unavailable"
        }

        val batteryStatus = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val isCharging = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1)?.let {
            it == BatteryManager.BATTERY_STATUS_CHARGING || it == BatteryManager.BATTERY_STATUS_FULL
        } ?: false

        return mapOf(
            "batteryLevel" to batteryLevel,
            "isCharging" to isCharging,
            "connectionType" to connectionType,
            "signalLevel" to signalLevel,
            "signalLabel" to signalLabel,
        )
    }
}
