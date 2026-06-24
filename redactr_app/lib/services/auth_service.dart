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
}
