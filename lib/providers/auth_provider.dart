import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool get isLoggedIn => _auth.currentUser != null;
  User? get currentUser => _auth.currentUser;

  Future<void> logout() async {
    await _auth.signOut();
    notifyListeners();
  }
}