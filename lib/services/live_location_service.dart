import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'sms_service.dart';

class LiveLocationService {
  final String uid;
  LiveLocationService({required this.uid});

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Timer? _timer;
  Timer? _smsTimer;
  bool _running = false;
  bool _smsSent = false;

  // ✅ Permission check
  Future<bool> _checkPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  // ✅ Get emergency contacts
  Future<List<String>> _getContacts() async {
    try {
      final snap = await _db
          .collection("users")
          .doc(uid)
          .collection("contacts")
          .get();

      return snap.docs
          .map((d) => (d.data()["phone"] ?? "").toString().trim())
          .where((p) => p.isNotEmpty)
          .toSet()
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ✅ Get user name
  Future<String> _getUserName() async {
    try {
      final doc = await _db.collection("users").doc(uid).get();
      return doc.data()?["name"] ?? "User";
    } catch (_) {
      return "User";
    }
  }

  // ✅ Send start SMS
  Future<void> _sendStartSMS(Position pos) async {
    if (_smsSent) return;

    final contacts = await _getContacts();
    if (contacts.isEmpty) return;

    final name = await _getUserName();
    final mapLink = "https://maps.google.com/?q=${pos.latitude},${pos.longitude}";
    final now = DateTime.now();
    final time = "${now.hour}:${now.minute.toString().padLeft(2, '0')}";

    final message = "📍 LIVE TRACKING STARTED\n\n"
        "$name is now sharing location.\n\n"
        "Current location: $mapLink\n\n"
        "Started: $time";

    await SmsService.sendToAll(
      phones: contacts,
      message: message,
    );

    _smsSent = true;
  }

  // ✅ Send periodic update SMS (every 10 minutes)
  Future<void> _sendUpdateSMS(Position pos) async {
    final contacts = await _getContacts();
    if (contacts.isEmpty) return;

    final name = await _getUserName();
    final mapLink = "https://maps.google.com/?q=${pos.latitude},${pos.longitude}";
    final now = DateTime.now();
    final time = "${now.hour}:${now.minute.toString().padLeft(2, '0')}";

    final message = "📍 Location Update\n\n"
        "$name's new location:\n"
        "$mapLink\n\n"
        "Updated: $time";

    await SmsService.sendToAll(
      phones: contacts,
      message: message,
    );
  }

  // ✅ Send stop SMS
  Future<void> _sendStopSMS(Position? pos) async {
    final contacts = await _getContacts();
    if (contacts.isEmpty) return;

    final name = await _getUserName();
    final now = DateTime.now();
    final time = "${now.hour}:${now.minute.toString().padLeft(2, '0')}";

    String message = "🛑 LIVE TRACKING STOPPED\n\n$name has stopped sharing location.\n\nEnded: $time";

    if (pos != null) {
      final mapLink = "https://maps.google.com/?q=${pos.latitude},${pos.longitude}";
      message = "🛑 LIVE TRACKING STOPPED\n\n"
          "$name has stopped sharing location.\n\n"
          "Last known location: $mapLink\n\n"
          "Ended: $time";
    }

    await SmsService.sendToAll(
      phones: contacts,
      message: message,
    );
  }

  // ✅ Start live tracking (every 10 sec)
  Future<bool> start() async {
    final ok = await _checkPermission();
    if (!ok) return false;

    if (_running) return true; // already running
    _running = true;
    _smsSent = false;

    // Cancel old timers if any
    _timer?.cancel();
    _smsTimer?.cancel();

    // Get initial position and send start SMS
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );
      await _saveLocation(pos);
      await _sendStartSMS(pos);
    } catch (e) {
      // Ignore
    }

    // Location tracking timer (every 10 seconds)
    _timer = Timer.periodic(const Duration(seconds: 10), (_) async {
      try {
        if (!_running) return;

        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 10),
        );

        await _saveLocation(pos);
      } catch (e) {
        // ignore temporary errors
      }
    });

    // SMS update timer (every 10 minutes)
    _smsTimer = Timer.periodic(const Duration(minutes: 10), (_) async {
      try {
        if (!_running) return;

        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 10),
        );

        await _sendUpdateSMS(pos);
      } catch (e) {
        // ignore
      }
    });

    return true;
  }

  // ✅ Stop tracking
  Future<void> stop() async {
    if (!_running) return;

    // Get last position and send stop SMS
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 5),
      );
      await _sendStopSMS(pos);
    } catch (e) {
      await _sendStopSMS(null);
    }

    _running = false;
    _smsSent = false;
    _timer?.cancel();
    _smsTimer?.cancel();
    _timer = null;
    _smsTimer = null;
  }

  // ✅ Save ONLY CURRENT location (safe)
  Future<void> _saveLocation(Position pos) async {
    final data = {
      "lat": pos.latitude,
      "lng": pos.longitude,
      "accuracy": pos.accuracy,
      "speed": pos.speed,
      "updatedAt": FieldValue.serverTimestamp(),
      "isSharing": true, // ✅ NEW: For in-app sharing
    };

    await _db
        .collection("users")
        .doc(uid)
        .collection("live_location")
        .doc("current")
        .set(data, SetOptions(merge: true));
  }
}
