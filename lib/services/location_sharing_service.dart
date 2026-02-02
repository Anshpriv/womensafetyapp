import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/location_sharing_model.dart';

class LocationSharingService {
  final String uid;
  LocationSharingService({required this.uid});

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ✅ Share your location with a contact
  Future<bool> shareLocationWithContact(String contactPhone, String yourName, String yourPhone) async {
    try {
      await _db.collection("location_shares").add({
        'sharedByUid': uid,
        'sharedByName': yourName,
        'sharedByPhone': yourPhone,
        'sharedWithPhone': contactPhone,
        'createdAt': FieldValue.serverTimestamp(),
        'isActive': true,
      });
      return true;
    } catch (e) {
      return false;
    }
  }

  // ✅ Stop sharing with a contact
  Future<void> stopSharingWithContact(String shareId) async {
    try {
      await _db.collection("location_shares").doc(shareId).update({
        'isActive': false,
      });
    } catch (e) {
      // Silent fail
    }
  }

  // ✅ Get list of people sharing location with YOU
  Stream<QuerySnapshot> getPeopleSharingWithMe(String myPhone) {
    return _db
        .collection("location_shares")
        .where('sharedWithPhone', isEqualTo: myPhone)
        .where('isActive', isEqualTo: true)
        .snapshots();
  }

  // ✅ Get someone's live location
  Stream<DocumentSnapshot> getPersonLocation(String theirUid) {
    return _db
        .collection("users")
        .doc(theirUid)
        .collection("live_location")
        .doc("current")
        .snapshots();
  }

  // ✅ Get list of people YOU are sharing with
  Stream<QuerySnapshot> getPeopleYouShareWith() {
    return _db
        .collection("location_shares")
        .where('sharedByUid', isEqualTo: uid)
        .where('isActive', isEqualTo: true)
        .snapshots();
  }
}

