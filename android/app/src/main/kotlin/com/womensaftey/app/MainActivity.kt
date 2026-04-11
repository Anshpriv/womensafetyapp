package com.womensaftey.app

import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val smsChannel = "sms_channel"
    private val dualCameraChannel = "dual_camera_channel"

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
    }
}
