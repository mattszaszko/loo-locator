import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Returns `null` on success, or an error message for the UI.
Future<String?> signInWithGoogleForFirebase() async {
  final google = GoogleSignIn.instance;
  if (!google.supportsAuthenticate()) {
    return 'Google sign-in is not available on this platform yet.';
  }
  try {
    final account = await google.authenticate();
    final auth = account.authentication;
    final idToken = auth.idToken;
    if (idToken == null) {
      return 'Could not get Google ID token.';
    }
    final credential = GoogleAuthProvider.credential(idToken: idToken);
    await FirebaseAuth.instance.signInWithCredential(credential);
    return null;
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled ||
        e.code == GoogleSignInExceptionCode.interrupted) {
      return null;
    }
    return e.description ?? e.toString();
  } on FirebaseAuthException catch (e) {
    return e.message ?? 'Google sign-in failed';
  } catch (e) {
    return e.toString();
  }
}
