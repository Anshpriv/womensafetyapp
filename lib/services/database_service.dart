import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  final String uid;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DatabaseService({required this.uid});

  // ============================
  // ✅ User Profile Methods
  // ============================

  /// ✅ Save profile data (used in ProfileSetupScreen)
  Future<void> saveUserProfile({
    required String name,
    required String phone,
    required String bloodGroup,
    required String emergencyNote,
  }) async {
    await _db.collection("users").doc(uid).set({
      "uid": uid,
      "name": name.trim(),
      "phone": phone.trim(),
      "bloodGroup": bloodGroup.trim(),
      "emergencyNote": emergencyNote.trim(),
      "updatedAt": FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// ✅ Stream user profile
  Stream<DocumentSnapshot<Map<String, dynamic>>> get userProfileStream {
    return _db.collection("users").doc(uid).snapshots();
  }

  // ============================
  // ✅ Emergency Contacts Methods
  // ============================

  /// ✅ Add contact (used in EmergencyContactsScreen)
  Future<void> addContact(String name, String phone, bool isPrimary) async {
    final ref = _db.collection("users").doc(uid).collection("contacts").doc();

    if (isPrimary) {
      // remove primary from others
      final all = await _db
          .collection("users")
          .doc(uid)
          .collection("contacts")
          .get();

      for (final doc in all.docs) {
        await doc.reference.update({"isPrimary": false});
      }
    }

    await ref.set({
      "id": ref.id,
      "name": name.trim(),
      "phone": phone.trim(),
      "isPrimary": isPrimary,
      "createdAt": FieldValue.serverTimestamp(),
    });
  }

  /// ✅ Delete contact
  Future<void> deleteContact(String contactId) async {
    await _db
        .collection("users")
        .doc(uid)
        .collection("contacts")
        .doc(contactId)
        .delete();
  }

  /// ✅ Set primary contact
  Future<void> setPrimaryContact(String contactId) async {
    final all = await _db.collection("users").doc(uid).collection("contacts").get();

    for (final doc in all.docs) {
      await doc.reference.update({"isPrimary": doc.id == contactId});
    }
  }

  /// ✅ Stream contacts list
  Stream<QuerySnapshot<Map<String, dynamic>>> get contactsStream {
    return _db
        .collection("users")
        .doc(uid)
        .collection("contacts")
        .orderBy("createdAt", descending: true)
        .snapshots();
  }

  /// ✅ Get emergency contacts as List (for home screen call feature)
  /// Returns contacts sorted: Primary first, then by creation date
  Future<List<Map<String, dynamic>>> getEmergencyContacts() async {
    try {
      final snapshot = await _db
          .collection("users")
          .doc(uid)
          .collection("contacts")
          .get();

      final contacts = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      // ✅ Sort: Primary contact FIRST, then by creation date
      contacts.sort((a, b) {
        // Primary contact always comes first
        if (a['isPrimary'] == true && b['isPrimary'] != true) return -1;
        if (b['isPrimary'] == true && a['isPrimary'] != true) return 1;
        
        // If both primary or both not primary, sort by creation date
        final aTime = a['createdAt'] as Timestamp?;
        final bTime = b['createdAt'] as Timestamp?;
        
        if (aTime == null || bTime == null) return 0;
        return bTime.compareTo(aTime); // Newest first
      });

      return contacts;
    } catch (e) {
      print('❌ Error getting contacts: $e');
      return [];
    }
  }

  // ============================
  // ✅ NEW: Live Location Tracking
  // ============================

  /// ✅ Update live location for real-time tracking
  Future<void> updateLiveLocation({
    required double latitude,
    required double longitude,
    required DateTime timestamp,
  }) async {
    // Store latest location in user document for quick access
    await _db.collection("users").doc(uid).update({
      "lastKnownLocation": {
        "latitude": latitude,
        "longitude": longitude,
        "timestamp": FieldValue.serverTimestamp(),
        "updatedAt": timestamp.toIso8601String(),
      }
    });

    // Also store in tracking history (optional - for path tracking)
    await _db.collection("users").doc(uid).collection("locationHistory").add({
      "latitude": latitude,
      "longitude": longitude,
      "timestamp": FieldValue.serverTimestamp(),
      "updatedAt": timestamp.toIso8601String(),
    });
  }

  /// ✅ Stream live location updates (latest location)
  Stream<DocumentSnapshot<Map<String, dynamic>>> get liveLocationStream {
    return _db.collection("users").doc(uid).snapshots();
  }

  /// ✅ Get location history (for tracking path)
  Stream<QuerySnapshot<Map<String, dynamic>>> getLocationHistory({int limit = 100}) {
    return _db
        .collection("users")
        .doc(uid)
        .collection("locationHistory")
        .orderBy("timestamp", descending: true)
        .limit(limit)
        .snapshots();
  }

  /// ✅ Clear old location history (cleanup - optional)
  Future<void> clearLocationHistory() async {
    final batch = _db.batch();
    final snapshots = await _db
        .collection("users")
        .doc(uid)
        .collection("locationHistory")
        .get();

    for (var doc in snapshots.docs) {
      batch.delete(doc.reference);
    }

    await batch.commit();
  }

  // ============================
  // ✅ NEW: Fake Call Settings
  // ============================

  /// ✅ Save fake call settings
  Future<void> saveFakeCallSettings({
    required String callerName,
    required String callerNumber,
    int delaySeconds = 5,
  }) async {
    await _db.collection("users").doc(uid).update({
      "fakeCallSettings": {
        "callerName": callerName.trim(),
        "callerNumber": callerNumber.trim(),
        "delaySeconds": delaySeconds,
        "updatedAt": FieldValue.serverTimestamp(),
      }
    });
  }

  /// ✅ Get fake call settings
  Future<Map<String, dynamic>?> getFakeCallSettings() async {
    final doc = await _db.collection("users").doc(uid).get();
    final data = doc.data();
    return data?["fakeCallSettings"] as Map<String, dynamic>?;
  }

  // ============================
  // ✅ NEW: Voice Command Logs
  // ============================

  /// ✅ Log voice command trigger
  Future<void> logVoiceCommand({
    required String command,
    required bool triggered,
  }) async {
    await _db.collection("users").doc(uid).collection("voiceCommandLogs").add({
      "command": command,
      "triggered": triggered,
      "timestamp": FieldValue.serverTimestamp(),
    });
  }

  /// ✅ Stream voice command logs
  Stream<QuerySnapshot<Map<String, dynamic>>> get voiceCommandLogsStream {
    return _db
        .collection("users")
        .doc(uid)
        .collection("voiceCommandLogs")
        .orderBy("timestamp", descending: true)
        .limit(20)
        .snapshots();
  }
}
