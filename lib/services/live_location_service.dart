import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

class LiveLocationService {
  final String uid;
  LiveLocationService({required this.uid});

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Timer? _timer;
  bool _running = false;

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

  // ✅ Start live tracking (every 10 sec)
  Future<bool> start() async {
    final ok = await _checkPermission();
    if (!ok) return false;

    if (_running) return true; // already running
    _running = true;

    // cancel old timer if any
    _timer?.cancel();

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

    return true;
  }

  // ✅ Stop tracking
  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  // ✅ Save ONLY CURRENT location (safe)
  Future<void> _saveLocation(Position pos) async {
    final data = {
      "lat": pos.latitude,
      "lng": pos.longitude,
      "accuracy": pos.accuracy,
      "speed": pos.speed,
      "updatedAt": FieldValue.serverTimestamp(),
    };

    await _db
        .collection("users")
        .doc(uid)
        .collection("live_location")
        .doc("current")
        .set(data, SetOptions(merge: true));
  }
}
