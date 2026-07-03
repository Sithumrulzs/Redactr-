import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Thin wrapper around Firebase Auth + Google Sign-In. This is the app's
/// only real external dependency — everything else in the project runs
/// fully offline/on-device by design; auth is the deliberate exception.
class AuthService {
  final FirebaseAuth? _firebaseAuthOverride;
  final GoogleSignIn? _googleSignInOverride;

  AuthService({FirebaseAuth? firebaseAuth, GoogleSignIn? googleSignIn})
      : _firebaseAuthOverride = firebaseAuth,
        _googleSignInOverride = googleSignIn;

  // Lazy on purpose: FirebaseAuth.instance throws if Firebase.initializeApp()
  // hasn't resolved yet, and AuthService is constructed before AuthGate knows
  // whether that's true (see main.dart).
  FirebaseAuth get _firebaseAuth => _firebaseAuthOverride ?? FirebaseAuth.instance;
  GoogleSignIn get _googleSignIn => _googleSignInOverride ?? GoogleSignIn();

  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  User? get currentUser => _firebaseAuth.currentUser;

  /// Returns null if the user cancels the Google account picker.
  Future<UserCredential?> signInWithGoogle() async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null;

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    return _firebaseAuth.signInWithCredential(credential);
  }

  /// Throws a FirebaseAuthException on failure (e.g. 'email-already-in-use',
  /// 'weak-password') — the sign-in screen maps these to friendly text.
  Future<UserCredential> signUpWithEmail(String email, String password) {
    return _firebaseAuth.createUserWithEmailAndPassword(email: email, password: password);
  }

  /// Throws a FirebaseAuthException on failure (e.g. 'user-not-found',
  /// 'wrong-password'/'invalid-credential').
  Future<UserCredential> signInWithEmail(String email, String password) {
    return _firebaseAuth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _firebaseAuth.signOut();
  }

  /// Permanently deletes the Firebase Auth account and revokes Google access.
  ///
  /// Firebase requires recent authentication before account deletion.
  /// If the session is stale ([FirebaseAuthException] with code
  /// `requires-recent-login`), this re-authenticates via Google first, then
  /// retries. Callers should delete Firestore user data (via
  /// [CompanyService.deleteUserData]) BEFORE calling this so the server-side
  /// record is removed even if the client-side step is interrupted.
  Future<void> deleteAccount() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) return;

    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        await _reauthenticateWithGoogle(user);
        await user.delete();
      } else {
        rethrow;
      }
    }

    // Revoke OAuth grant so the Google account picker shows up clean next
    // time — same as what iOS/Android apps do on account deletion.
    await _googleSignIn.disconnect();
  }

  Future<void> _reauthenticateWithGoogle(User user) async {
    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) throw Exception('Sign-in was cancelled.');
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    await user.reauthenticateWithCredential(credential);
  }
}
