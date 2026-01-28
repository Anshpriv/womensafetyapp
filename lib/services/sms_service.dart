import 'package:flutter/services.dart';

class SmsService {
  static const MethodChannel _channel = MethodChannel("sms_channel");

  static String normalizePhone(String phone) {
    var p = phone.trim();
    p = p.replaceAll(RegExp(r'[\s\-\(\)]'), '');

    if (p.startsWith("0")) p = p.substring(1);

    if (RegExp(r'^\d{10}$').hasMatch(p)) {
      p = "+91$p";
    }

    if (RegExp(r'^91\d{10}$').hasMatch(p)) {
      p = "+$p";
    }

    if (!p.startsWith("+") && RegExp(r'^\d{10,15}$').hasMatch(p)) {
      p = "+$p";
    }

    return p;
  }

  static Future<bool> sendSms({
    required String phone,
    required String message,
  }) async {
    try {
      // ✅ FIX: always normalize phone before sending
      final normalized = normalizePhone(phone);

      final ok = await _channel.invokeMethod("sendSms", {
        "phone": normalized,
        "message": message,
      });

      return ok == true;
    } catch (_) {
      return false;
    }
  }

  static Future<int> sendToAll({
    required List<String> phones,
    required String message,
  }) async {
    int sent = 0;

    for (final raw in phones) {
      final phone = normalizePhone(raw);
      final ok = await sendSms(phone: phone, message: message);
      if (ok) sent++;
    }

    return sent;
  }
}
