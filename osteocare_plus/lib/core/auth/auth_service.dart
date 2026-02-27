import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'user_session.dart';

class AuthService {
  AuthService._internal();

  static final AuthService instance = AuthService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Builds a synthetic email from the phone number so we can use
  /// Firebase email/password auth while the user only sees phone + password.
  String _emailFromPhone(String phone) {
    final trimmed = phone.replaceAll(RegExp(r'\s+'), '');
    return '$trimmed@osteocare.app';
  }

  Future<void> signInOrSignUpWithPhone({
    required String name,
    required String phone,
    required String password,
  }) async {
    final email = _emailFromPhone(phone);

    UserCredential credential;
    try {
      credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        credential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        await _firestore.collection('users').doc(credential.user!.uid).set({
          'name': name,
          'phone': phone,
          'createdAt': FieldValue.serverTimestamp(),
        });
      } else {
        rethrow;
      }
    }

    final uid = credential.user!.uid;
    final profileSnap = await _firestore.collection('users').doc(uid).get();
    final profileData =
        profileSnap.data() ?? <String, dynamic>{'name': name, 'phone': phone};

    UserSession.instance.setUser(
      uid: uid,
      name: profileData['name'] as String? ?? name,
      phone: profileData['phone'] as String? ?? phone,
    );
  }

  Future<void> loadCurrentUserIfAny() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final doc = await _firestore.collection('users').doc(user.uid).get();
    final data = doc.data();
    if (data == null) return;

    UserSession.instance.setUser(
      uid: user.uid,
      name: data['name'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
    UserSession.instance.clear();
  }
}

