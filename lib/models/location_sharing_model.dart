import 'package:cloud_firestore/cloud_firestore.dart';

class LocationShare {
  final String shareId;
  final String sharedByUid;
  final String sharedByName;
  final String sharedByPhone;
  final String sharedWithPhone;
  final DateTime createdAt;
  final bool isActive;

  LocationShare({
    required this.shareId,
    required this.sharedByUid,
    required this.sharedByName,
    required this.sharedByPhone,
    required this.sharedWithPhone,
    required this.createdAt,
    required this.isActive,
  });

  Map<String, dynamic> toMap() {
    return {
      'sharedByUid': sharedByUid,
      'sharedByName': sharedByName,
      'sharedByPhone': sharedByPhone,
      'sharedWithPhone': sharedWithPhone,
      'createdAt': Timestamp.fromDate(createdAt),
      'isActive': isActive,
    };
  }

  factory LocationShare.fromMap(String id, Map<String, dynamic> map) {
    return LocationShare(
      shareId: id,
      sharedByUid: map['sharedByUid'] ?? '',
      sharedByName: map['sharedByName'] ?? 'Unknown',
      sharedByPhone: map['sharedByPhone'] ?? '',
      sharedWithPhone: map['sharedWithPhone'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isActive: map['isActive'] ?? false,
    );
  }
}

class SharedLocation {
  final double lat;
  final double lng;
  final double speed;
  final DateTime updatedAt;
  final bool isSharing;

  SharedLocation({
    required this.lat,
    required this.lng,
    required this.speed,
    required this.updatedAt,
    required this.isSharing,
  });

  factory SharedLocation.fromMap(Map<String, dynamic> map) {
    return SharedLocation(
      lat: map['lat'] ?? 0.0,
      lng: map['lng'] ?? 0.0,
      speed: map['speed'] ?? 0.0,
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isSharing: map['isSharing'] ?? false,
    );
  }
}
