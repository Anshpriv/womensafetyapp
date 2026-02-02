import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../models/route_model.dart';
import 'speed_monitoring_service.dart';
import 'notification_service.dart';

class RouteTrackingService {
  final String uid;
  RouteTrackingService({required this.uid});

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Timer? _timer;
  bool _running = false;
  String? _currentTripId;
  Position? _lastPosition;
  double _totalDistance = 0.0;
  double _maxSpeed = 0.0;
  bool _lastWasOverspeed = false;

  SpeedMonitoringService? _speedService;

  // Start a new trip
  Future<String?> startTrip() async {
    if (_running) return _currentTripId;

    try {
      // Create new trip document
      final tripDoc = await _db
          .collection("users")
          .doc(uid)
          .collection("trips")
          .add({
        'startTime': FieldValue.serverTimestamp(),
        'endTime': null,
        'isActive': true,
        'totalDistance': 0.0,
        'overspeedCount': 0,
        'maxSpeed': 0.0,
      });

      _currentTripId = tripDoc.id;
      _totalDistance = 0.0;
      _maxSpeed = 0.0;
      _lastPosition = null;
      _speedService = SpeedMonitoringService(uid: uid);

      _running = true;

      // Start tracking every 10 seconds
      _timer = Timer.periodic(const Duration(seconds: 10), (_) async {
        await _trackLocation();
      });

      return _currentTripId;
    } catch (e) {
      return null;
    }
  }

  // Track location during trip
  Future<void> _trackLocation() async {
    if (!_running || _currentTripId == null) return;

    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );

      final speedKmh = pos.speed * 3.6; // Convert m/s to km/h

      // Update max speed
      if (speedKmh > _maxSpeed) {
        _maxSpeed = speedKmh;
        await _db
            .collection("users")
            .doc(uid)
            .collection("trips")
            .doc(_currentTripId)
            .update({'maxSpeed': _maxSpeed});
      }

      // Calculate distance from last position
      if (_lastPosition != null) {
        final distance = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          pos.latitude,
          pos.longitude,
        ) / 1000; // Convert meters to km

        _totalDistance += distance;

        await _db
            .collection("users")
            .doc(uid)
            .collection("trips")
            .doc(_currentTripId)
            .update({'totalDistance': _totalDistance});
      }

      // Save route point
      final routePoint = RoutePoint(
        lat: pos.latitude,
        lng: pos.longitude,
        speed: pos.speed,
        timestamp: DateTime.now(),
        accuracy: pos.accuracy,
      );

      await _db
          .collection("users")
          .doc(uid)
          .collection("trips")
          .doc(_currentTripId)
          .collection("route_points")
          .add(routePoint.toMap());

      // Check overspeed
      if (_speedService != null && _speedService!.isOverspeed(speedKmh)) {
        // Only log if this is a new overspeed event (not continuous)
        if (!_lastWasOverspeed) {
          await _speedService!.logOverspeedIncident(
            speedKmh: speedKmh,
            lat: pos.latitude,
            lng: pos.longitude,
            tripId: _currentTripId,
          );
          
          // ✅ SHOW NOTIFICATION
          await NotificationService.showOverspeedAlert(
            speed: speedKmh,
            limit: SpeedMonitoringService.SPEED_LIMIT,
          );
          
          _lastWasOverspeed = true;
        }
      } else {
        _lastWasOverspeed = false;
      }

      _lastPosition = pos;
    } catch (e) {
      // Ignore errors
    }
  }

  // End current trip
  Future<void> endTrip() async {
    if (!_running || _currentTripId == null) return;

    _running = false;
    _timer?.cancel();

    try {
      // Get trip data for notification
      final tripDoc = await _db
          .collection("users")
          .doc(uid)
          .collection("trips")
          .doc(_currentTripId)
          .get();
      
      final tripData = tripDoc.data();
      final overspeedCount = tripData?['overspeedCount'] ?? 0;

      await _db
          .collection("users")
          .doc(uid)
          .collection("trips")
          .doc(_currentTripId)
          .update({
        'endTime': FieldValue.serverTimestamp(),
        'isActive': false,
      });

      // ✅ SHOW TRIP COMPLETED NOTIFICATION
      await NotificationService.showTripCompleted(
        distance: _totalDistance,
        overspeedCount: overspeedCount,
      );

      // Schedule deletion after 1 day
      await _scheduleOldTripDeletion();
    } catch (e) {
      // Silent fail
    }

    _currentTripId = null;
    _lastPosition = null;
    _speedService = null;
  }

  // Delete trips older than 1 day after they ended
  Future<void> _scheduleOldTripDeletion() async {
    try {
      final oneDayAgo = DateTime.now().subtract(const Duration(days: 1));

      final oldTrips = await _db
          .collection("users")
          .doc(uid)
          .collection("trips")
          .where('isActive', isEqualTo: false)
          .where('endTime', isLessThan: Timestamp.fromDate(oneDayAgo))
          .get();

      for (var doc in oldTrips.docs) {
        // Delete route points subcollection
        final routePoints = await doc.reference.collection('route_points').get();
        for (var point in routePoints.docs) {
          await point.reference.delete();
        }

        // Delete trip document
        await doc.reference.delete();
      }
    } catch (e) {
      // Silent fail
    }
  }

  // Get current active trip
  Stream<DocumentSnapshot>? getCurrentTripStream() {
    if (_currentTripId == null) return null;

    return _db
        .collection("users")
        .doc(uid)
        .collection("trips")
        .doc(_currentTripId)
        .snapshots();
  }

  // Get all trips
  Stream<QuerySnapshot> getTripsStream() {
    return _db
        .collection("users")
        .doc(uid)
        .collection("trips")
        .orderBy('startTime', descending: true)
        .limit(20)
        .snapshots();
  }

  // Check if tracking is active
  bool get isTracking => _running;

  String? get currentTripId => _currentTripId;
}
