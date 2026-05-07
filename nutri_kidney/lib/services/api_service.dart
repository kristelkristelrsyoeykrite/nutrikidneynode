import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class ApiService {
 static const String baseUrl = "http://127.0.0.1:3000";


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

  static void clearUserId() {
    _userId = null;
    print("DEBUG: UserId cleared");
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
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }
    final now = DateTime.now();
    final today =
        "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    return _post(
      "/api/health/dashboard-summary",
      body: {
        "userId": _userId,
        "date": today,
      },
    );
  }

  static Future<Map<String, dynamic>> getHealthSummary() async {
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }
    return _post(
      "/api/health/health-summary",
      body: {
        "userId": _userId,
      },
    );
  }

  static Future<Map<String, dynamic>> getAnalyticsSummary({
    required String range,
    String? endDate,
  }) async {
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }
    return _post(
      "/api/health/analytics-summary",
      body: {
        "userId": _userId,
        "range": range,
        "endDate": endDate,
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
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }
    return _post(
      "/api/health/save-lab-result",
      body: {
        "userId": _userId,
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
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }
    data['userId'] = _userId;
    return _post("/api/health/update-profile", body: data);
  }

  static Future<Map<String, dynamic>> unlinkCaregiverChild({
    String? linkedChildUserId,
  }) async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/user/unlink-caregiver-child",
      body: {
        "uid": currentUserId,
        "linkedChildUserId": linkedChildUserId,
      },
    );
  }

  static Future<Map<String, dynamic>> saveMedication(Map<String, dynamic> data) async {
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }
    data['userId'] = _userId;
    return _post("/api/health/save-medication", body: data);
  }

  static Future<Map<String, dynamic>> updateMedication(
    String medicationId,
    Map<String, dynamic> data,
  ) async {
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }
    data['userId'] = _userId;
    data['medicationId'] = medicationId;
    return _post("/api/health/update-medication", body: data);
  }

  static Future<Map<String, dynamic>> deleteMedication(String medicationId) async {
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }
    return _post(
      "/api/health/delete-medication",
      body: {
        "userId": _userId,
        "medicationId": medicationId,
      },
    );
  }

  static Future<Map<String, dynamic>> extractPrescription({
    required String imagePath,
    String contentType = "image/jpeg",
  }) async {
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }
    final bytes = await File(imagePath).readAsBytes();
    return _post(
      "/api/health/medications/scan",
      body: {
        "userId": _userId,
        "imageBase64": base64Encode(bytes),
        "contentType": contentType,
      },
    );
  }

  static Future<Map<String, dynamic>> confirmMedicationScan(
    Map<String, dynamic> data,
  ) async {
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }
    data['userId'] = _userId;
    return _post("/api/health/medications/confirm", body: data);
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
    String? userRole,
  }) async {
    return _post(
      "/api/user/create",
      body: {
        "fullName": fullName,
        "email": email,
        "phoneNumber": phoneNumber,
        "password": password,
        "userRole": userRole,
      },
    );
  }

  static Future<Map<String, dynamic>> sendEmailVerification(String uid) async {
    return _post("/api/user/send-email-verification", body: {"uid": uid});
  }

  static Future<Map<String, dynamic>> completeEmailVerification(
    String uid,
  ) async {
    return _post("/api/user/complete-email-verification", body: {"uid": uid});
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

  static Future<Map<String, dynamic>> changePassword({
    required String currentPassword,
    required String newPassword,
    required String verificationContact,
  }) async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/user/change-password",
      body: {
        "uid": currentUserId,
        "currentPassword": currentPassword,
        "newPassword": newPassword,
        "verificationContact": verificationContact,
      },
    );
  }

  static Future<Map<String, dynamic>> getSecuritySettings() async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/user/security-settings",
      body: {
        "uid": currentUserId,
      },
    );
  }

  static Future<Map<String, dynamic>> updateSecuritySettings({
    required bool mfaEnabled,
    String? mfaMethod,
    String? mfaCode,
  }) async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/user/update-security-settings",
      body: {
        "uid": currentUserId,
        "mfaEnabled": mfaEnabled,
        "mfaMethod": mfaMethod,
        if (mfaCode != null) "mfaCode": mfaCode,
      },
    );
  }

  static Future<Map<String, dynamic>> startAuthenticatorMfaSetup({
    String? email,
  }) async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/user/mfa/authenticator/setup/start",
      body: {
        "uid": currentUserId,
        "email": email,
      },
    );
  }

  static Future<Map<String, dynamic>> verifyAuthenticatorMfaSetup({
    required String code,
  }) async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/user/mfa/authenticator/setup/verify",
      body: {
        "uid": currentUserId,
        "code": code,
      },
    );
  }

  static Future<Map<String, dynamic>> verifyAuthenticatorMfaCode({
    required String uid,
    required String code,
  }) async {
    return _post(
      "/api/user/mfa/authenticator/verify",
      body: {
        "uid": uid,
        "code": code,
      },
    );
  }

  static Future<Map<String, dynamic>> getGamificationSummary() async {
    final currentUserId = _requireCurrentUserId();
    final now = DateTime.now();
    final today =
        "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    return _post(
      "/api/gamification/summary",
      body: {
        "userId": currentUserId,
        "date": today,
      },
    );
  }

  static Future<Map<String, dynamic>> getGamificationLeaderboard({
    int limit = 10,
  }) async {
    return _post(
      "/api/gamification/leaderboard",
      body: {"limit": limit},
    );
  }

  static Future<Map<String, dynamic>> updateLeaderboardVisibility({
    required bool showOnLeaderboard,
  }) async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/gamification/leaderboard-visibility",
      body: {
        "userId": currentUserId,
        "showOnLeaderboard": showOnLeaderboard,
      },
    );
  }

  static Future<Map<String, dynamic>> getReminderSettings({
    String? profileUserId,
  }) async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/user/reminder-settings",
      body: {
        "uid": currentUserId,
        "profileUserId": profileUserId,
      },
    );
  }

  static Future<Map<String, dynamic>> updateReminderSettings({
    String? profileUserId,
    required bool medicationReminders,
    required bool hydrationAlerts,
    required bool breakfastReminder,
    required bool lunchReminder,
    required bool snackReminder,
    required bool dinnerReminder,
  }) async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/user/update-reminder-settings",
      body: {
        "uid": currentUserId,
        "profileUserId": profileUserId,
        "medicationReminders": medicationReminders,
        "hydrationAlerts": hydrationAlerts,
        "mealReminders": {
          "breakfast": breakfastReminder,
          "lunch": lunchReminder,
          "snack": snackReminder,
          "dinner": dinnerReminder,
        },
      },
    );
  }

  static Future<Map<String, dynamic>> saveCaregiverChildAgeGroup({
    required String childAgeGroup,
  }) async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/user/caregiver-child-age",
      body: {
        "uid": currentUserId,
        "childAgeGroup": childAgeGroup,
      },
    );
  }

  static Future<Map<String, dynamic>> generateCaregiverLinkCode() async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/user/generate-caregiver-link-code",
      body: {"uid": currentUserId},
    );
  }

  static Future<Map<String, dynamic>> linkCaregiverWithCode({
    required String linkingCode,
  }) async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/user/link-caregiver-account",
      body: {
        "uid": currentUserId,
        "linkingCode": linkingCode,
      },
    );
  }

  static Future<Map<String, dynamic>> registerDeviceToken({
    required String token,
    required String platform,
  }) async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/user/device-token/register",
      body: {
        "uid": currentUserId,
        "token": token,
        "platform": platform,
      },
    );
  }

  static Future<Map<String, dynamic>> unregisterDeviceToken({
    required String token,
  }) async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/user/device-token/unregister",
      body: {
        "uid": currentUserId,
        "token": token,
      },
    );
  }

  static Future<Map<String, dynamic>> sendTestPushNotification() async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/user/push-notification/send-test",
      body: {
        "uid": currentUserId,
      },
    );
  }

  static String _requireCurrentUserId() {
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }
    return _userId!;
  }

  static Future<Map<String, dynamic>> searchFoods(
    String query, {
    int page = 0,
  }) async {
    final response = await _post(
      "/api/food/search",
      body: {
        "query": query,
        "page": page,
      },
    );
    if (response["success"] == false) {
      throw Exception(response["error"] ?? "Food search failed.");
    }

    final rawFoods = response["foods"] ?? response["choices"];
    if (rawFoods is List) {
      response["foods"] = rawFoods
          .whereType<Map>()
          .map((food) {
            final data = Map<String, dynamic>.from(food);
            return {
              "foodId": (data["foodId"] ?? data["food_id"])?.toString(),
              "name": data["name"] ?? data["food_name"] ?? "Food",
              "brandName": data["brandName"] ?? data["brand_name"] ?? "",
              "foodType": data["foodType"] ?? data["food_type"] ?? "",
              "servingDescription": data["servingDescription"] ??
                  data["preview_description"] ??
                  "Select serving",
              "calories": data["calories"] ?? 0,
              "protein": data["protein"] ?? 0,
              "carbohydrate": data["carbohydrate"] ?? 0,
              "fat": data["fat"] ?? 0,
              "sodium": data["sodium"] ?? 0,
              "potassium": data["potassium"] ?? 0,
              "phosphorus": data["phosphorus"] ?? 0,
              "source": data["source"] ?? "fatsecret",
              "raw": data,
            };
          })
          .toList();
    }

    return response;
  }

  static Future<Map<String, dynamic>> getFoodDetails(String foodId) async {
    final response = await _post(
      "/api/food/details",
      body: {
        "foodId": foodId,
      },
    );
    if (response["success"] == false) {
      throw Exception(response["error"] ?? "Food details failed.");
    }

    final food = response["food"] is Map
        ? Map<String, dynamic>.from(response["food"])
        : response;
    final servings = food["servings"];
    if (servings is List) {
      response["servings"] = servings;
    }
    return response;
  }

  static Future<Map<String, dynamic>> recognizeFoodImage({
    required String imagePath,
    String contentType = "image/jpeg",
  }) async {
    final bytes = await File(imagePath).readAsBytes();
    final response = await _post(
      "/api/food/recognize-image",
      body: {
        "imageBase64": base64Encode(bytes),
        "contentType": contentType,
      },
    );

    final recognizedFood = response["recognizedFood"] ??
        response["food"] ??
        (response["result"] is Map ? response["result"]["food"] : null);
    if (recognizedFood is Map) {
      final food = Map<String, dynamic>.from(recognizedFood);
      response["recognizedFood"] = food;
      response["food"] = food;
      final servings = food["servings"];
      if (servings is List) {
        response["servings"] = servings;
      }
    }

    final recognizedFoods = response["recognizedFoods"] ??
        response["recognized_foods"] ??
        (response["result"] is Map ? response["result"]["recognized_foods"] : null);
    if (recognizedFoods is List) {
      response["recognizedFoods"] = recognizedFoods
          .whereType<Map>()
          .map((food) => Map<String, dynamic>.from(food))
          .toList(growable: false);
    }

    return response;
  }

  static Future<Map<String, dynamic>> getFoodLogs({
    String? date,
    String? dateFrom,
    String? dateTo,
    int limit = 100,
  }) async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/food/logs/list",
      body: {
        "userId": currentUserId,
        "date": date,
        "dateFrom": dateFrom,
        "dateTo": dateTo,
        "limit": limit,
      },
    );
  }

  static Future<Map<String, dynamic>> addFoodLog({
    required String mealType,
    required String name,
    required String portion,
    required int calories,
    String? date,
    String? foodId,
    double? protein,
    double? carbohydrate,
    double? fat,
    double? sodium,
    double? potassium,
    double? phosphorus,
    String? servingId,
    double? quantity,
    String source = "manual_entry",
    bool needsManualReview = false,
    Map<String, dynamic>? raw,
    double? waterMl,
    bool userConfirmedAllergyWarning = false,
  }) async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/food/logs/add",
      body: {
        "userId": currentUserId,
        "mealType": mealType,
        "date": date,
        "loggedAt": DateTime.now().toIso8601String(),
        "foodId": foodId,
        "servingId": servingId,
        "quantity": quantity,
        "name": name,
        "portion": portion,
        "calories": calories,
        "protein": protein,
        "carbohydrate": carbohydrate,
        "fat": fat,
        "sodium": sodium,
        "potassium": potassium,
        "phosphorus": phosphorus,
        "source": source,
        "needsManualReview": needsManualReview,
        "raw": raw,
        "waterMl": waterMl,
        "userConfirmedAllergyWarning": userConfirmedAllergyWarning,
      },
    );
  }

  static Future<Map<String, dynamic>> deleteFoodLog(String foodLogId) async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/food/logs/delete",
      body: {
        "userId": currentUserId,
        "foodLogId": foodLogId,
      },
    );
  }

  static Future<Map<String, dynamic>> updateFoodLog({
    required String foodLogId,
    required String mealType,
    required String name,
    required String portion,
    required int calories,
    String? date,
    String? servingId,
    double? quantity,
    double? protein,
    double? carbohydrate,
    double? fat,
    double? sodium,
    double? potassium,
    double? phosphorus,
    Map<String, dynamic>? raw,
    double? waterMl,
  }) async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/food/logs/update",
      body: {
        "userId": currentUserId,
        "foodLogId": foodLogId,
        "mealType": mealType,
        "date": date,
        "name": name,
        "portion": portion,
        "servingId": servingId,
        "quantity": quantity,
        "calories": calories,
        "protein": protein,
        "carbohydrate": carbohydrate,
        "fat": fat,
        "sodium": sodium,
        "potassium": potassium,
        "phosphorus": phosphorus,
        "raw": raw,
        "waterMl": waterMl,
      },
    );
  }
}
