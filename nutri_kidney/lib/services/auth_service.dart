import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: '119513656180-i05nhjkfcrgnsetmb3vn4bdtbl858283.apps.googleusercontent.com',
    scopes: const ['email', 'profile'],
  );

  /// Check if user has a valid "Remember Me" session.
  /// Call this AFTER Firebase has had time to restore its auth state,
  /// e.g. inside a FutureBuilder or after awaiting authStateChanges.first.
  static Future<bool> hasRememberedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool('rememberMe') ?? false;
      final savedUserId = prefs.getString('userId');

      print('--- hasRememberedSession Debug ---');
      print('rememberMe flag: $rememberMe');
      print('savedUserId: $savedUserId');

      if (!rememberMe || savedUserId == null || savedUserId.isEmpty) {
        print('Signing out, retrieving previous creds');
        print('Remember Me not set — clearing any Firebase session');
        await _auth.signOut();
        await _googleSignIn.signOut();
        return false;
      }

      // Wait for Firebase to restore its auth state (avoids the race condition
      // where currentUser is null immediately after app launch).
      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        print('currentUser null — waiting for authStateChanges...');
        currentUser = await _auth
            .authStateChanges()
            .firstWhere((u) => u != null, orElse: () => null);
      }

      print('currentUser after wait: ${currentUser?.uid}');

      if (currentUser == null || currentUser.uid != savedUserId) {
        print('Signing out, retrieving previous creds');
        print('UID mismatch or no session — signing out');
        await _auth.signOut();
        await _googleSignIn.signOut();
        return false;
      }

      print('Remember Me session valid — auto-login as ${currentUser.email}');
      return true;
    } catch (e) {
      print('Error checking remembered session: $e');
      return false;
    }
  }

  /// Get the current "Remember Me" flag value.
  /// Use this on the login screen to pre-check the toggle.
  static Future<bool> getRememberMeFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('rememberMe') ?? false;
    } catch (e) {
      print('Error getting rememberMe flag: $e');
      return false;
    }
  }

  /// Call this immediately after a successful login/signup,
  /// passing the confirmed UID from FirebaseAuth.
  static Future<void> saveRememberedSession(String userId, bool rememberMe, {String? contact}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (rememberMe && userId.isNotEmpty) {
        await prefs.setBool('rememberMe', true);
        await prefs.setString('userId', userId);
        if (contact != null && contact.isNotEmpty) {
          await prefs.setString('savedContact', contact);
        }
        print('Session saved: rememberMe=true, userId=$userId, contact=$contact');
      } else {
        // User explicitly chose NOT to be remembered — clear everything
        await prefs.remove('rememberMe');
        await prefs.remove('userId');
        await prefs.remove('savedContact');
        print('Session NOT saved: rememberMe=false — preferences cleared');
      }
    } catch (e) {
      print('Error saving session: $e');
    }
  }

  /// Get the saved contact (email or phone) from the last "Remember Me" session.
  static Future<String?> getSavedContact() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('savedContact');
    } catch (e) {
      print('Error getting saved contact: $e');
      return null;
    }
  }

  /// Call this on explicit logout.
  /// Only clears the saved userId to invalidate the auto-login session.
  /// Preserves the rememberMe flag and savedContact for a smoother next login
  /// (the toggle will be pre-checked and the email/phone will be pre-filled).
  static Future<void> clearRememberedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('userId'); // Invalidate the session token only
      // NOTE: 'rememberMe' and 'savedContact' are intentionally kept
      // so the user can easily log in again without retyping their email/phone.
      print('Session cleared (rememberMe preference preserved)');
    } catch (e) {
      print('Error clearing session: $e');
    }
  }

  /// Shared Google Sign-In for both login and registration.
  static Future<Map<String, dynamic>> handleGoogleSignIn() async {
    try {
      try {
        await _googleSignIn.disconnect();
      } catch (e) {
        print('Disconnect warning: $e');
      }

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return {'success': false, 'error': 'Google Sign-In cancelled'};
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      return {
        'success': true,
        'user': userCredential,
        'isNewUser': userCredential.additionalUserInfo?.isNewUser ?? false,
        'email': googleUser.email,
        'displayName': googleUser.displayName,
        'photoUrl': googleUser.photoUrl,
      };
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': 'Firebase error: ${e.message}'};
    } catch (e) {
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  /// Google Sign-In for LOGIN ONLY - Checks database BEFORE signing in with Firebase
  /// This prevents unregistered accounts from being created
  static Future<Map<String, dynamic>> handleGoogleSignInLogin() async {
    try {
      try {
        await _googleSignIn.disconnect();
      } catch (e) {
        print('Disconnect warning: $e');
      }

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return {'success': false, 'error': 'Google Sign-In cancelled'};
      }

      final email = googleUser.email;
      print('DEBUG: Google Sign-In email: $email');

      // CHECK DATABASE FIRST - before Firebase creates the account
      if (email.isNotEmpty) {
        final checkResult = await ApiService.checkUserExists({"email": email});
        print('DEBUG: Database check for $email -> $checkResult');
        
        if (checkResult['success'] != true || checkResult['exists'] != true) {
          // User not registered - reject and don't complete Firebase sign-in
          print('DEBUG: User $email not found in database - rejecting login');
          return {
            'success': false,
            'error': 'Account Not Found',
            'message': 'This Google account is not registered. Please sign up first.',
          };
        }
      }

      // Database check passed - NOW sign in with Firebase
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);

      return {
        'success': true,
        'user': userCredential,
        'isNewUser': userCredential.additionalUserInfo?.isNewUser ?? false,
        'email': googleUser.email,
        'displayName': googleUser.displayName,
        'photoUrl': googleUser.photoUrl,
      };
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': 'Firebase error: ${e.message}'};
    } catch (e) {
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  /// Get current user (may be null if not signed in).
  static User? getCurrentUser() => _auth.currentUser;

  /// Sign out and clear the active session.
  /// The rememberMe preference is preserved for a smoother next login.
  static Future<void> signOut() async {
    try {
      await clearRememberedSession(); // Clears userId only, keeps rememberMe
      await _auth.signOut();
      await _googleSignIn.signOut();
      print('User signed out and session cleared');
    } catch (e) {
      print('Error signing out: $e');
    }
  }
}