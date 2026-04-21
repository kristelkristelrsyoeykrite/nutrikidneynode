import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = "http://10.231.54.184:3000";
  static const Map<String, String> _jsonHeaders = {
    "Content-Type": "application/json",
  };

  static String? _userId;
  static String? get userId => _userId;

  static Map<String, dynamic> step1Data = {};
  static Map<String, dynamic> step2Data = {};
  static Map<String, dynamic> step3Data = {};
  static Map<String, dynamic> step4Data = {};
  static Map<String, dynamic> signupData = {};
  static String? userRole;

  static void setUserId(String userId) {
    _userId = userId;
    print("DEBUG: UserId stored: $_userId");
  }

  static void setSignupData(Map<String, dynamic> data) {
    signupData = Map<String, dynamic>.from(data);
    print("DEBUG: Signup data stored: $signupData");
  }

  static void setUserRole(String? role) {
    userRole = role;
    print("DEBUG: User role stored: $userRole");
  }

  static void clearProfileSetupData() {
    step1Data = {};
    step2Data = {};
    step3Data = {};
    step4Data = {};
    print("DEBUG: Profile setup data cleared");
  }

  static Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse("$baseUrl$path");
    final payload = body ?? const <String, dynamic>{};
    print("DEBUG POST $path payload: $payload");

    final response = await http.post(
      uri,
      headers: _jsonHeaders,
      body: jsonEncode(payload),
    );

    print("DEBUG POST $path status: ${response.statusCode}");
    print("DEBUG POST $path body: ${response.body}");

    if (response.body.isEmpty) {
      return {
        "success": response.statusCode >= 200 && response.statusCode < 300,
      };
    }

    final decoded = jsonDecode(response.body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    return {
      "success": response.statusCode >= 200 && response.statusCode < 300,
      "data": decoded,
    };
  }

  static Future<void> _sendHealthStep(
    String path,
    Map<String, dynamic> data,
    void Function(Map<String, dynamic>) cache,
  ) async {
    cache(Map<String, dynamic>.from(data));
    await _post(path, body: data);
  }

  static Future<void> sendStep1(Map<String, dynamic> data) async {
    await _sendHealthStep("/api/health/step1", data, (value) => step1Data = value);
  }

  static Future<void> sendStep2(Map<String, dynamic> data) async {
    await _sendHealthStep("/api/health/step2", data, (value) => step2Data = value);
  }

  static Future<void> sendStep3(Map<String, dynamic> data) async {
    await _sendHealthStep("/api/health/step3", data, (value) => step3Data = value);
  }

  static Future<void> sendStep4(Map<String, dynamic> data) async {
    await _sendHealthStep("/api/health/step4", data, (value) => step4Data = value);
  }

  static Future<Map<String, dynamic>> submitAll() async {
    if (_userId == null) {
      throw Exception("UserId not set. Please complete signup first.");
    }

    return _post(
      "/api/health/submit-all",
      body: {
        "userId": _userId,
        "step1": step1Data,
        "step2": step2Data,
        "step3": step3Data,
        "step4": step4Data,
        "userRole": userRole,
      },
    );
  }

  static Future<Map<String, dynamic>> getDashboardSummary() async {
    final currentUserId = _userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) {
      throw Exception("UserId not set. Please log in again.");
    }

    setUserId(currentUserId);
    return _post(
      "/api/health/dashboard-summary",
      body: {
        "userId": currentUserId,
      },
    );
  }

  static Future<Map<String, dynamic>> getHealthSummary() async {
    final currentUserId = _userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) {
      throw Exception("UserId not set. Please log in again.");
    }

    setUserId(currentUserId);
    return _post(
      "/api/health/health-summary",
      body: {
        "userId": currentUserId,
      },
    );
  }

  static Future<Map<String, dynamic>> saveMeasurement({
    required String metricType,
    required String value,
    String? date,
    bool recalculateNutritionTargets = false,
  }) async {
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }

    return _post(
      "/api/health/save-measurement",
      body: {
        "userId": _userId,
        "metricType": metricType,
        "value": value,
        "date": date,
        "recalculateNutritionTargets": recalculateNutritionTargets,
      },
    );
  }

  static Future<Map<String, dynamic>> saveLabResult({
    required String metricType,
    required String value,
    required String resultDate,
    String? labResultId,
  }) async {
    final currentUserId = _userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) {
      throw Exception("UserId not set. Please log in again.");
    }

    setUserId(currentUserId);
    return _post(
      "/api/health/save-lab-result",
      body: {
        "userId": currentUserId,
        "labResultId": labResultId,
        "metricType": metricType,
        "value": value,
        "resultDate": resultDate,
      },
    );
  }

  static Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> data,
  ) async {
    final currentUserId = _userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) {
      throw Exception("UserId not set. Please log in again.");
    }

    setUserId(currentUserId);
    data['userId'] = currentUserId;
    return _post("/api/health/update-profile", body: data);
  }

  static Future<Map<String, dynamic>> saveMedication(Map<String, dynamic> data) async {
    final currentUserId = _userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) {
      throw Exception("UserId not set. Please log in again.");
    }

    setUserId(currentUserId);
    data['userId'] = currentUserId;
    return _post("/api/health/save-medication", body: data);
  }

  static Future<Map<String, dynamic>> updateMedication(
    String medicationId,
    Map<String, dynamic> data,
  ) async {
    final currentUserId = _userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) {
      throw Exception("UserId not set. Please log in again.");
    }

    setUserId(currentUserId);
    data['userId'] = currentUserId;
    data['medicationId'] = medicationId;
    return _post("/api/health/update-medication", body: data);
  }

  static Future<Map<String, dynamic>> deleteMedication(String medicationId) async {
    final currentUserId = _userId ?? FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) {
      throw Exception("UserId not set. Please log in again.");
    }

    setUserId(currentUserId);
    return _post(
      "/api/health/delete-medication",
      body: {
        "userId": currentUserId,
        "medicationId": medicationId,
      },
    );
  }

  static Future<Map<String, dynamic>> signup(Map<String, dynamic> data) async {
    final decoded = await _post("/signup", body: data);
    final userId = decoded["userId"] ?? decoded["uid"];
    if (decoded["success"] == true && userId is String && userId.isNotEmpty) {
      setUserId(userId);
    }
    return decoded;
  }

  static Future<Map<String, dynamic>> checkUserExists(
    Map<String, dynamic> data,
  ) async {
    return _post("/check-user", body: data);
  }

  static Future<Map<String, dynamic>> verifyPhonePassword(
    Map<String, dynamic> data,
  ) async {
    return _post("/verify-phone-password", body: data);
  }

  static Future<Map<String, dynamic>> resetPassword(
    Map<String, dynamic> data,
  ) async {
    return _post("/reset-password", body: data);
  }

  static Future<Map<String, dynamic>> verifyEmailDomain(
    Map<String, dynamic> data,
  ) async {
    return _post("/verify-email-domain", body: data);
  }

  static Future<Map<String, dynamic>> startEmailVerification(
    Map<String, dynamic> data,
  ) async {
    return _post("/send-email-verification", body: data);
  }

  static Future<Map<String, dynamic>> verifyEmailToken(
    Map<String, dynamic> data,
  ) async {
    return _post("/verify-email-token", body: data);
  }

  static Future<Map<String, dynamic>> verifyEmailAndCreateProfile(
    Map<String, dynamic> data,
  ) async {
    final decoded = await _post("/verify-email-and-create-user", body: data);
    final userId = decoded["userId"] ?? decoded["uid"];
    if (decoded["success"] == true && userId is String && userId.isNotEmpty) {
      setUserId(userId);
    }
    return decoded;
  }

  static Future<Map<String, dynamic>> createUserAfterEmailVerification(
    Map<String, dynamic> data,
  ) async {
    return verifyEmailAndCreateProfile(data);
  }

  static Future<Map<String, dynamic>> verifyPhoneAndCreateProfile(
    Map<String, dynamic> data,
  ) async {
    final decoded = await _post("/verify-phone-and-create-user", body: data);
    final userId = decoded["userId"] ?? decoded["uid"];
    if (decoded["success"] == true && userId is String && userId.isNotEmpty) {
      setUserId(userId);
    }
    return decoded;
  }

  static Future<Map<String, dynamic>> saveUserProfile(
    Map<String, dynamic> data,
  ) async {
    return _post("/api/user/profile/save", body: data);
  }

  static Future<Map<String, dynamic>> deleteUserAccount(String uid) async {
    return _post("/api/user/cancel-verification", body: {"uid": uid});
  }

  static Future<Map<String, dynamic>> createUser({
    required String fullName,
    String? email,
    String? phoneNumber,
    required String password,
  }) async {
    return _post(
      "/api/user/create",
      body: {
        "fullName": fullName,
        "email": email,
        "phoneNumber": phoneNumber,
        "password": password,
      },
    );
  }

  static Future<Map<String, dynamic>> sendEmailVerification(String uid) async {
    return _post("/api/user/send-email-verification", body: {"uid": uid});
  }

  static Future<Map<String, dynamic>> sendPhoneOtp({
    required String uid,
    required String phoneNumber,
  }) async {
    return _post(
      "/api/user/send-phone-otp",
      body: {
        "uid": uid,
        "phoneNumber": phoneNumber,
      },
    );
  }

  static Future<Map<String, dynamic>> completeEmailVerification(
    String uid,
  ) async {
    return _post("/api/user/complete-email-verification", body: {"uid": uid});
  }

  static Future<Map<String, dynamic>> completePhoneVerification(
    String uid,
  ) async {
    return _post("/api/user/complete-phone-verification", body: {"uid": uid});
  }

  static Future<Map<String, dynamic>> saveUserProfileAfterVerification({
    required String uid,
    required String fullName,
    String? email,
    String? phoneNumber,
    String? password,
    String? userRole,
    String status = "verified",
  }) async {
    return saveUserProfile({
      "uid": uid,
      "fullName": fullName,
      "email": email,
      "phoneNumber": phoneNumber,
      "password": password,
      "userRole": userRole,
      "status": status,
    });
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    return _post(
      "/api/user/login",
      body: {
        "email": email,
        "password": password,
      },
    );
  }

  static Future<Map<String, dynamic>> getProfileStatus({
    String? uid,
    String? email,
    String? phoneNumber,
  }) async {
    return _post(
      "/api/user/profile-status",
      body: {
        "uid": uid,
        "email": email,
        "phoneNumber": phoneNumber,
      },
    );
  }

  static Future<Map<String, dynamic>> sendPasswordReset(String email) async {
    return _post("/api/user/send-password-reset", body: {"email": email});
  }

  static Future<Map<String, dynamic>> resetPasswordWithCode({
    required String oobCode,
    required String newPassword,
  }) async {
    return _post(
      "/api/user/reset-password",
      body: {
        "oobCode": oobCode,
        "newPassword": newPassword,
      },
    );
  }

  static Future<Map<String, dynamic>> signOut(String uid) async {
    return _post("/api/user/sign-out", body: {"uid": uid});
  }
}
