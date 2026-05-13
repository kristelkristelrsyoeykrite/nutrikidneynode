import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:nutri_kidney/services/api_service.dart';
import 'package:nutri_kidney/services/push_notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId:
        '119513656180-i05nhjkfcrgnsetmb3vn4bdtbl858283.apps.googleusercontent.com',
    scopes: const ['email', 'profile'],
  );

  static Future<bool> hasRememberedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool('rememberMe') ?? false;
      final savedUserId = prefs.getString('userId');
      final savedContact = prefs.getString('savedContact');

      print('--- hasRememberedSession Debug ---');
      print('rememberMe flag: $rememberMe');
      print('savedUserId: $savedUserId');
      print('savedContact: $savedContact');

      if (!rememberMe || savedUserId == null || savedUserId.isEmpty) {
        print('Remember Me not set - clearing any Firebase session');
        await _auth.signOut();
        await _googleSignIn.signOut();
        return false;
      }

      User? currentUser = _auth.currentUser;
      if (currentUser == null) {
        print('currentUser null - checking authStateChanges...');
        try {
          currentUser = await _auth
              .authStateChanges()
              .first
              .timeout(const Duration(seconds: 2), onTimeout: () => null);
        } catch (_) {
          currentUser = null;
        }
      }

      print('currentUser after wait: ${currentUser?.uid}');

      final profileStatus = await ApiService.getProfileStatus(uid: savedUserId);
      if (profileStatus['success'] != true ||
          profileStatus['exists'] != true ||
          profileStatus['verified'] != true ||
          profileStatus['needsProfileSetup'] == true) {
        print('No completed app profile found for remembered session - signing out');
        await _auth.signOut();
        await _googleSignIn.signOut();
        return false;
      }

      if (currentUser == null) {
        print('No Firebase session for remembered login - signing out');
        await _auth.signOut();
        await _googleSignIn.signOut();
        return false;
      }

      if (currentUser.uid != savedUserId) {
        print('UID mismatch for remembered session - signing out');
        await _auth.signOut();
        await _googleSignIn.signOut();
        return false;
      }

      await currentUser.reload();
      currentUser = _auth.currentUser;

      if (currentUser == null || currentUser.uid != savedUserId) {
        print('Session lost after reload - signing out');
        await _auth.signOut();
        await _googleSignIn.signOut();
        return false;
      }

      final hasEmail =
          currentUser.email != null && currentUser.email!.isNotEmpty;
      if (hasEmail && currentUser.emailVerified != true) {
        print('Unverified email session detected - signing out');
        await _auth.signOut();
        await _googleSignIn.signOut();
        return false;
      }

      ApiService.setUserId(savedUserId);
      ApiService.clearSessionCache();
      print('Remember Me session valid - auto-login as ${currentUser.email}');
      return true;
    } catch (e) {
      print('Error checking remembered session: $e');
      return false;
    }
  }

  static Future<bool> getRememberMeFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('rememberMe') ?? false;
    } catch (e) {
      print('Error getting rememberMe flag: $e');
      return false;
    }
  }

  static Future<void> saveRememberedSession(
    String userId,
    bool rememberMe, {
    String? contact,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (rememberMe && userId.isNotEmpty) {
        await prefs.setBool('rememberMe', true);
        await prefs.setString('userId', userId);
        if (contact != null && contact.isNotEmpty) {
          await prefs.setString('savedContact', contact);
        }
        print(
          'Session saved: rememberMe=true, userId=$userId, contact=$contact',
        );
      } else {
        await prefs.remove('rememberMe');
        await prefs.remove('userId');
        await prefs.remove('savedContact');
        print('Session NOT saved: rememberMe=false - preferences cleared');
      }
    } catch (e) {
      print('Error saving session: $e');
    }
  }

  static Future<String?> getSavedContact() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('savedContact');
    } catch (e) {
      print('Error getting saved contact: $e');
      return null;
    }
  }

  static Future<void> clearRememberedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('userId');
      print('Session cleared (rememberMe preference preserved)');
    } catch (e) {
      print('Error clearing session: $e');
    }
  }

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

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final profileStatus = await ApiService.getProfileStatus(
        email: googleUser.email,
      );
      if (profileStatus['success'] != true ||
          profileStatus['exists'] != true ||
          profileStatus['verified'] != true) {
        await _googleSignIn.signOut();
        return {
          'success': false,
          'error':
              'No registered app account was found for this Google account. Please sign up first.',
        };
      }

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
        'profileStatus': profileStatus,
      };
    } on FirebaseAuthException catch (e) {
      return {'success': false, 'error': 'Firebase error: ${e.message}'};
    } catch (e) {
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  static Future<Map<String, dynamic>> getGoogleProfileForRegistration() async {
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

      final result = {
        'success': true,
        'email': googleUser.email,
        'displayName': googleUser.displayName,
        'photoUrl': googleUser.photoUrl,
      };

      await _googleSignIn.signOut();

      return result;
    } catch (e) {
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  static User? getCurrentUser() => _auth.currentUser;

  static Future<void> signOut() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedUserId = prefs.getString('userId');
      final currentUser = _auth.currentUser;
      final userIdToNotify =
          currentUser?.uid ?? (savedUserId != null && savedUserId.isNotEmpty ? savedUserId : null);

      if (userIdToNotify != null) {
        try {
          await PushNotificationService.unregisterCurrentDeviceToken();
          await ApiService.signOut(userIdToNotify);
        } catch (e) {
          print('Error notifying backend of sign out: $e');
        }
      }

      await clearRememberedSession();
      await _auth.signOut();
      await _googleSignIn.signOut();
      ApiService.clearUserId();
      print('User signed out and session cleared');
    } catch (e) {
      print('Error signing out: $e');
    }
  }
}
