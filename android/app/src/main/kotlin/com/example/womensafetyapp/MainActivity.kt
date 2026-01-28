package com.example.womensafetyapp

import android.telephony.SmsManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "sms_channel"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
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
    }
}
