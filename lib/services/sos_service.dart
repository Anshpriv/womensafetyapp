import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'sms_service.dart';
import 'permission_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SOSService {
  final String uid;
  SOSService({required this.uid});

  static const String _cachedContactsKey = 'cached_emergency_contacts';
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<Position?> _getLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      final ok = await PermissionService.requestLocationPermission();
      if (!ok) return null;

      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (_) {
        return await Geolocator.getLastKnownPosition();
      }
    } catch (_) {
      return null;
    }
  }

  Future<String> _getAddress(double lat, double lng) async {
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isEmpty) return "Address not found";

      final p = placemarks.first;

      final parts = [
        p.name,
        p.street,
        p.subLocality,
        p.locality,
        p.administrativeArea,
        p.postalCode,
      ].where((e) => e != null && e.toString().trim().isNotEmpty).toList();

      return parts.join(", ");
    } catch (_) {
      return "Address not found";
    }
  }

  Future<List<String>> _getContacts() async {
    try {
      final snap = await _db
          .collection("users")
          .doc(uid)
          .collection("contacts")
          .get();

      final cloudContacts = snap.docs
          .map((d) => (d.data()["phone"] ?? "").toString().trim())
          .where((p) => p.isNotEmpty)
          .toSet()
          .toList();

      if (cloudContacts.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_cachedContactsKey, cloudContacts);
      }

      return cloudContacts;
    } catch (_) {
      try {
        final prefs = await SharedPreferences.getInstance();
        return (prefs.getStringList(_cachedContactsKey) ?? const [])
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toSet()
            .toList();
      } catch (_) {
        return [];
      }
    }
  }

  Future<void> _saveSosEvent(Map<String, dynamic> data) async {
    await _db.collection("users").doc(uid).collection("sos_events").add(data);
  }

  Future<String> triggerSOS() async {
    // ✅ SMS permission
    final smsOk = await PermissionService.requestSmsPermission();
    if (!smsOk) return "⚠️ SMS permission denied";

    // ✅ location
    final pos = await _getLocation();
    if (pos == null) return "⚠️ Location missing";

    final address = await _getAddress(pos.latitude, pos.longitude);

    // ✅ FIX: remove duplicates + remove empty contacts
    final contacts = (await _getContacts())
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();

    final mapLink =
        "https://www.google.com/maps/search/?api=1&query=${pos.latitude},${pos.longitude}";

    final message =
        "🚨 SOS ALERT! I need help.\n\n📍Location: $address\n\n🗺️ Map: $mapLink";

    try {
      await _saveSosEvent({
        "time": FieldValue.serverTimestamp(),
        "lat": pos.latitude,
        "lng": pos.longitude,
        "address": address,
        "map": mapLink,
        "contactsCount": contacts.length,
      });
    } catch (_) {
      // Never block SOS SMS on cloud logging failures.
    }

    if (contacts.isEmpty) return "⚠️ No emergency contacts found";

    // ✅ REAL BACKGROUND SMS
    final sent = await SmsService.sendToAll(
      phones: contacts,
      message: message,
    );

    return "✅ SOS sent to $sent/${contacts.length} contacts (background)";
  }
}
