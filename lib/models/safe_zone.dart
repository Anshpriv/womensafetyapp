import 'package:cloud_firestore/cloud_firestore.dart';

class SafeZone {
  final String id;
  final String childId;
  final String guardianId;
  final String zoneName;
  final double latitude;
  final double longitude;
  final double radius;
  final bool active;
  final DateTime? createdAt;

  SafeZone({
    required this.id,
    required this.childId,
    required this.guardianId,
    required this.zoneName,
    required this.latitude,
    required this.longitude,
    required this.radius,
    required this.active,
    this.createdAt,
  });

  factory SafeZone.fromMap(Map<String, dynamic> map, String docId) {
    return SafeZone(
      id: docId,
      childId: map['childId'] ?? '',
      guardianId: map['guardianId'] ?? '',
      zoneName: map['zoneName'] ?? '',
      latitude: (map['latitude'] ?? 0.0).toDouble(),
      longitude: (map['longitude'] ?? 0.0).toDouble(),
      radius: (map['radius'] ?? 0.0).toDouble(),
      active: map['active'] ?? false,
      createdAt: map['createdAt'] != null ? (map['createdAt'] as Timestamp).toDate() : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'childId': childId,
      'guardianId': guardianId,
      'zoneName': zoneName,
      'latitude': latitude,
      'longitude': longitude,
      'radius': radius,
      'active': active,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    };
  }
}
