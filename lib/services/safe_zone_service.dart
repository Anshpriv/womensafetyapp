import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/safe_zone.dart';
import '../models/boundary_alert.dart';

class SafeZoneService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String guardianId;

  SafeZoneService({required this.guardianId});

  Stream<List<SafeZone>> getSafeZones() {
    return _firestore
        .collection('safe_zones')
        .where('guardianId', isEqualTo: guardianId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => SafeZone.fromMap(doc.data(), doc.id))
          .toList();
    });
  }

  Future<void> addSafeZone(SafeZone zone) async {
    await _firestore.collection('safe_zones').add(zone.toMap());
  }

  Future<void> updateSafeZone(SafeZone zone) async {
    await _firestore.collection('safe_zones').doc(zone.id).update(zone.toMap());
  }

  Future<void> deleteSafeZone(String id) async {
    await _firestore.collection('safe_zones').doc(id).delete();
  }

  Future<void> toggleSafeZone(String id, bool active) async {
    await _firestore.collection('safe_zones').doc(id).update({'active': active});
  }

  Stream<List<BoundaryAlert>> getBoundaryAlerts() {
    return _firestore
        .collection('boundary_alerts')
        .where('guardianId', isEqualTo: guardianId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => BoundaryAlert.fromMap(doc.data(), doc.id))
          .toList();
    });
  }
}
