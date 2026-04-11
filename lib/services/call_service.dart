import 'package:flutter/material.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';
import 'package:permission_handler/permission_handler.dart';

class CallService {
  // ✅ Request phone call permission
  static Future<bool> requestCallPermission() async {
    final status = await Permission.phone.request();
    debugPrint('📞 Phone permission: $status');
    return status.isGranted;
  }

  // ✅ Make direct call
  static Future<bool> makeCall(String phoneNumber) async {
    try {
      debugPrint('📞 Attempting to call: $phoneNumber');
      
      // Request permission first
      final permOk = await requestCallPermission();
      if (!permOk) {
        debugPrint('❌ Phone permission denied');
        return false;
      }

      // Normalize phone number
      final cleanNumber = phoneNumber.trim().replaceAll(RegExp(r'[^\d+]'), '');
      debugPrint('📞 Cleaned number: $cleanNumber');

      if (cleanNumber.isEmpty) {
        debugPrint('❌ Invalid phone number');
        return false;
      }

      // Make call
      await FlutterPhoneDirectCaller.callNumber(cleanNumber);
      debugPrint('✅ Call initiated to: $cleanNumber');
      
      return true;
    } catch (e) {
      debugPrint('❌ Call failed: $e');
      return false;
    }
  }

  // ✅ Show call confirmation dialog
  static Future<bool> confirmCall(BuildContext context, String name, String phone) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Make Emergency Call?'),
        content: Text('Call $name at $phone'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.call),
            label: const Text('Call Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );

    return result ?? false;
  }
}
