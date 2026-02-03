import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;

  Future<bool> refreshSession() async {
    final user = _auth.currentUser;
    if (user == null) {
      return false;
    }

    try {
      await user.reload();
      return _auth.currentUser != null;
    } on FirebaseAuthException catch (e) {
      const invalidCodes = {
        'invalid-credential',
        'invalid-user-token',
        'user-token-expired',
        'user-disabled',
      };
      if (invalidCodes.contains(e.code)) {
        await _auth.signOut();
        return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<UserCredential> signInOrCreateEmail(
    String email,
    String password, {
    String? displayName,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _upsertUserProfile(credential.user!, displayName: displayName);
      return credential;
    } on FirebaseAuthException catch (e) {
      if (e.code != 'user-not-found' && e.code != 'invalid-credential') {
        rethrow;
      }
      try {
        final credential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
        await _upsertUserProfile(credential.user!, displayName: displayName);
        return credential;
      } on FirebaseAuthException catch (createError) {
        if (createError.code == 'email-already-in-use') {
          rethrow;
        }
        rethrow;
      }
    }
  }

  Future<void> _upsertUserProfile(User user, {String? displayName}) async {
    final doc = _db.collection('users').doc(user.uid);
    await doc.set(
      {
        'email': user.email,
        'displayName': displayName ?? user.displayName,
        'createdAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> signOut() => _auth.signOut();
}
