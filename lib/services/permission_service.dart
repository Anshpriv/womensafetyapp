import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static Future<bool> requestSmsPermission() async {
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  static Future<bool> requestLocationPermission() async {
    final status = await Permission.locationWhenInUse.request();
    return status.isGranted;
  }
}
