import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  final String uid;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DatabaseService({required this.uid});

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
}
