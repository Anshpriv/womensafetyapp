import 'package:cloud_firestore/cloud_firestore.dart';

class RoutePoint {
  final double lat;
  final double lng;
  final double speed; // m/s
  final DateTime timestamp;
  final double accuracy;

  RoutePoint({
    required this.lat,
    required this.lng,
    required this.speed,
    required this.timestamp,
    required this.accuracy,
  });

  // Convert m/s to km/h
  double get speedKmh => speed * 3.6;

  Map<String, dynamic> toMap() {
    return {
      'lat': lat,
      'lng': lng,
      'speed': speed,
      'timestamp': Timestamp.fromDate(timestamp),
      'accuracy': accuracy,
    };
  }

  factory RoutePoint.fromMap(Map<String, dynamic> map) {
    return RoutePoint(
      lat: map['lat'] ?? 0.0,
      lng: map['lng'] ?? 0.0,
      speed: map['speed'] ?? 0.0,
      timestamp: (map['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      accuracy: map['accuracy'] ?? 0.0,
    );
  }
}

class Trip {
  final String id;
  final DateTime startTime;
  final DateTime? endTime;
  final bool isActive;
  final double totalDistance; // km
  final int overspeedCount;
  final double maxSpeed; // km/h

  Trip({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.isActive,
    this.totalDistance = 0.0,
    this.overspeedCount = 0,
    this.maxSpeed = 0.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'startTime': Timestamp.fromDate(startTime),
      'endTime': endTime != null ? Timestamp.fromDate(endTime!) : null,
      'isActive': isActive,
      'totalDistance': totalDistance,
      'overspeedCount': overspeedCount,
      'maxSpeed': maxSpeed,
    };
  }

  factory Trip.fromMap(String id, Map<String, dynamic> map) {
    return Trip(
      id: id,
      startTime: (map['startTime'] as Timestamp?)?.toDate() ?? DateTime.now(),
      endTime: (map['endTime'] as Timestamp?)?.toDate(),
      isActive: map['isActive'] ?? false,
      totalDistance: (map['totalDistance'] ?? 0.0).toDouble(),
      overspeedCount: map['overspeedCount'] ?? 0,
      maxSpeed: (map['maxSpeed'] ?? 0.0).toDouble(),
    );
  }
}
