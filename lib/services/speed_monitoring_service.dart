import 'package:cloud_firestore/cloud_firestore.dart';

class SpeedMonitoringService {
  final String uid;
  SpeedMonitoringService({required this.uid});

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  // Speed limit in km/h
  static const double SPEED_LIMIT = 80.0;

  // Check if speed exceeds limit
  bool isOverspeed(double speedKmh) {
    return speedKmh > SPEED_LIMIT;
  }

  // Log overspeed incident
  Future<void> logOverspeedIncident({
    required double speedKmh,
    required double lat,
    required double lng,
    String? tripId,
  }) async {
    try {
      await _db
          .collection("users")
          .doc(uid)
          .collection("overspeed_incidents")
          .add({
        'speed': speedKmh,
        'speedLimit': SPEED_LIMIT,
        'lat': lat,
        'lng': lng,
        'tripId': tripId,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Update trip overspeed count if tripId provided
      if (tripId != null) {
        await _db
            .collection("users")
            .doc(uid)
            .collection("trips")
            .doc(tripId)
            .update({
          'overspeedCount': FieldValue.increment(1),
        });
      }
    } catch (e) {
      // Silent fail
    }
  }

  // Get today's overspeed incidents
  Stream<QuerySnapshot> getTodayOverspeedIncidents() {
    final startOfDay = DateTime.now().copyWith(
      hour: 0,
      minute: 0,
      second: 0,
      millisecond: 0,
    );

    return _db
        .collection("users")
        .doc(uid)
        .collection("overspeed_incidents")
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  // Get overspeed count for a trip
  Future<int> getTripOverspeedCount(String tripId) async {
    try {
      final snapshot = await _db
          .collection("users")
          .doc(uid)
          .collection("overspeed_incidents")
          .where('tripId', isEqualTo: tripId)
          .get();

      return snapshot.docs.length;
    } catch (e) {
      return 0;
    }
  }
}
