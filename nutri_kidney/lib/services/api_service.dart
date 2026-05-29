import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'api_cache.dart';

class ApiService {
 static const String baseUrl = "https://nutrikidneynode.onrender.com";


  static const Map<String, String> _jsonHeaders = {
    "Content-Type": "application/json",
  };

  static String _cacheKey(List<Object?> parts) => ApiCache.key(parts);

  static String _withTryAgain(Object? message) {
    final text = message?.toString().trim();
    final base = text == null || text.isEmpty ? "Request failed." : text;
    return base.toLowerCase().contains("try again")
        ? base
        : "$base Please try again.";
  }

  static String _readableError(Object error) {
    return error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
  }


  static void _invalidateCurrentUserCache(Iterable<String> sections) {
    final currentUserId = _userId;
    if (currentUserId == null) return;
    ApiCache.invalidatePrefixes(
      sections.map((section) => _cacheKey(["user", currentUserId, section])),
    );
  }

  static Map<String, dynamic> _invalidateOnSuccess(
    Map<String, dynamic> response,
    Iterable<String> sections,
  ) {
    if (response["success"] != false) {
      _invalidateCurrentUserCache(sections);
    }
    return response;
  }

  static String? _userId;
  static String? get userId => _userId;

  static Map<String, dynamic> step1Data = {};
  static Map<String, dynamic> step2Data = {};
  static Map<String, dynamic> step3Data = {};
  static Map<String, dynamic> step4Data = {};
  static Map<String, dynamic> signupData = {};
  static String? userRole;
  static String? activeChildProfileId;
  static String? pendingCaregiverChildAgeGroup;
  static String? selectedManagedChildProfileId;

  static void setUserId(String userId) {
    if (_userId != userId) {
      ApiCache.clear();
      selectedManagedChildProfileId = null;
    }
    _userId = userId;
    print("DEBUG: UserId stored: $_userId");
  }

  static void clearSessionCache() {
    ApiCache.clear();
    print("DEBUG: Session cache cleared");
  }

  static void clearUserId() {
    _userId = null;
    selectedManagedChildProfileId = null;
    ApiCache.clear();
    print("DEBUG: UserId cleared");
  }

  static void setSignupData(Map<String, dynamic> data) {
    signupData = Map<String, dynamic>.from(data);
    print("DEBUG: Signup data stored: $signupData");
  }

  static String? normalizeUserRole(String? role) {
    final normalized = role?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized == "parent_caregiver") return "caregiver";
    if (normalized.contains("adolescent")) return "adolescent";
    if (normalized.contains("caregiver")) return "caregiver";
    return normalized;
  }

  static void setUserRole(String? role) {
    userRole = normalizeUserRole(role);
    print("DEBUG: User role stored: $userRole");
  }

  static void clearProfileSetupData() {
    step1Data = {};
    step2Data = {};
    step3Data = {};
    step4Data = {};
    activeChildProfileId = null;
    pendingCaregiverChildAgeGroup = null;
    print("DEBUG: Profile setup data cleared");
  }

  static void setSelectedManagedChildProfileId(String? profileUserId) {
    selectedManagedChildProfileId =
        profileUserId != null && profileUserId.isNotEmpty
            ? profileUserId
            : null;
    print(
      "DEBUG: Selected managed child profile id stored: $selectedManagedChildProfileId",
    );
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
        "statusCode": response.statusCode,
        "rateLimited": response.statusCode == 429,
      };
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      final preview = response.body
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return {
        "success": false,
        "statusCode": response.statusCode,
        "rateLimited": response.statusCode == 429,
        "error": response.statusCode >= 500
            ? "The backend is temporarily unavailable. Please try again."
            : "Unexpected server response.",
        "rawBody": preview.length > 240 ? preview.substring(0, 240) : preview,
      };
    }
    if (decoded is Map<String, dynamic>) {
      return {
        ...decoded,
        "statusCode": response.statusCode,
        "rateLimited": response.statusCode == 429,
      };
    }

    return {
      "success": response.statusCode >= 200 && response.statusCode < 300,
      "statusCode": response.statusCode,
      "rateLimited": response.statusCode == 429,
      "data": decoded,
    };
  }

  static Future<void> _sendHealthStep(
    String path,
    Map<String, dynamic> data,
    void Function(Map<String, dynamic>) cache,
  ) async {
    final payload = {
      ...data,
      if (activeChildProfileId != null) "childProfileId": activeChildProfileId,
      if (activeChildProfileId != null) "profileUserId": activeChildProfileId,
    };
    cache(Map<String, dynamic>.from(data));
    await _post(path, body: payload);
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

    final response = await _post(
      "/api/health/submit-all",
      body: {
        "userId": _userId,
        "step1": step1Data,
        "step2": step2Data,
        "step3": step3Data,
        "step4": step4Data,
        "userRole": userRole,
        if (pendingCaregiverChildAgeGroup != null)
          "caregiverChildAgeGroup": pendingCaregiverChildAgeGroup,
        if (activeChildProfileId != null)
          "childProfileId": activeChildProfileId,
      },
    );
    if (response["success"] == true) {
      activeChildProfileId = null;
      pendingCaregiverChildAgeGroup = null;
    }
    return _invalidateOnSuccess(response, [
      "dashboard-summary",
      "health-summary",
      "analytics-summary",
      "reminder-settings",
    ]);
  }

  static Future<Map<String, dynamic>> getDashboardSummary({
    String? profileUserId,
    bool forceRefresh = false,
  }) async {
    final currentUserId = _requireCurrentUserId();
    final now = DateTime.now();
    final today =
        "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    Future<Map<String, dynamic>> fetch() => _post(
          "/api/health/dashboard-summary",
          body: {
            "userId": currentUserId,
            "date": today,
            if (profileUserId != null) "profileUserId": profileUserId,
          },
        );

    final key = _cacheKey([
        "user",
        currentUserId,
        "dashboard-summary",
        profileUserId ?? "active",
        today,
      ]);
    if (forceRefresh) ApiCache.invalidate(key);

    return ApiCache.getOrFetch(
      key,
      fetch,
      ttl: const Duration(minutes: 1),
    );
  }

  static Future<Map<String, dynamic>> getHealthSummary({
    String? profileUserId,
    bool forceRefresh = false,
  }) async {
    final currentUserId = _requireCurrentUserId();
    Future<Map<String, dynamic>> fetch() => _post(
          "/api/health/health-summary",
          body: {
            "userId": currentUserId,
            if (profileUserId != null) "profileUserId": profileUserId,
          },
        );

    final key = _cacheKey([
        "user",
        currentUserId,
        "health-summary",
        profileUserId ?? "active",
      ]);
    if (forceRefresh) ApiCache.invalidate(key);

    return ApiCache.getOrFetch(
      key,
      fetch,
      ttl: const Duration(minutes: 3),
    );
  }

  static Future<Map<String, dynamic>> getMissedMedicationReminders({
    String? profileUserId,
    int limit = 20,
  }) async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/health/missed-medication-reminders",
      body: {
        "userId": currentUserId,
        if (profileUserId != null) "profileUserId": profileUserId,
        "limit": limit,
      },
    );
  }

  static Future<Map<String, dynamic>> getAnalyticsSummary({
    required String range,
    String? endDate,
    String? profileUserId,
  }) async {
    final currentUserId = _requireCurrentUserId();
    Future<Map<String, dynamic>> fetch() => _post(
          "/api/health/analytics-summary",
          body: {
            "userId": currentUserId,
            "range": range,
            "endDate": endDate,
            if (profileUserId != null) "profileUserId": profileUserId,
          },
        );

    return ApiCache.getOrFetch(
      _cacheKey([
        "user",
        currentUserId,
        "analytics-summary",
        profileUserId ?? "active",
        range,
        endDate,
      ]),
      fetch,
      ttl: const Duration(minutes: 2),
    );
  }

  static Future<Map<String, dynamic>> saveMeasurement({
    String? profileUserId,
    required String metricType,
    required String value,
    String? date,
    bool recalculateNutritionTargets = false,
  }) async {
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }

    final response = await _post(
      "/api/health/save-measurement",
      body: {
        "userId": _userId,
        if (profileUserId != null) "profileUserId": profileUserId,
        "metricType": metricType,
        "value": value,
        "date": date,
        "recalculateNutritionTargets": recalculateNutritionTargets,
      },
    );
    return _invalidateOnSuccess(response, [
      "dashboard-summary",
      "health-summary",
      "analytics-summary",
    ]);
  }

  static Future<Map<String, dynamic>> deleteMeasurement({
    String? profileUserId,
    required String metricType,
    bool recalculateNutritionTargets = false,
  }) async {
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }

    final response = await _post(
      "/api/health/delete-measurement",
      body: {
        "userId": _userId,
        if (profileUserId != null) "profileUserId": profileUserId,
        "metricType": metricType,
        "recalculateNutritionTargets": recalculateNutritionTargets,
      },
    );
    return _invalidateOnSuccess(response, [
      "dashboard-summary",
      "health-summary",
      "analytics-summary",
    ]);
  }

  static Future<Map<String, dynamic>> saveLabResult({
    String? profileUserId,
    required String metricType,
    required String value,
    required String resultDate,
    String? labResultId,
  }) async {
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }
    final response = await _post(
      "/api/health/save-lab-result",
      body: {
        "userId": _userId,
        if (profileUserId != null) "profileUserId": profileUserId,
        "labResultId": labResultId,
        "metricType": metricType,
        "value": value,
        "resultDate": resultDate,
      },
    );
    return _invalidateOnSuccess(response, [
      "dashboard-summary",
      "health-summary",
      "analytics-summary",
    ]);
  }

  static Future<Map<String, dynamic>> deleteLabResult({
    String? profileUserId,
    required String labResultId,
    required String metricType,
  }) async {
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }
    final response = await _post(
      "/api/health/delete-lab-result",
      body: {
        "userId": _userId,
        if (profileUserId != null) "profileUserId": profileUserId,
        "labResultId": labResultId,
        "metricType": metricType,
      },
    );
    return _invalidateOnSuccess(response, [
      "dashboard-summary",
      "health-summary",
      "analytics-summary",
    ]);
  }

  static Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> data,
  ) async {
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }
    data['userId'] = _userId;
    final response = await _post("/api/health/update-profile", body: data);
    return _invalidateOnSuccess(response, [
      "dashboard-summary",
      "health-summary",
      "analytics-summary",
      "reminder-settings",
    ]);
  }

  static Future<Map<String, dynamic>> unlinkCaregiverChild({
    String? linkedChildUserId,
  }) async {
    final currentUserId = _requireCurrentUserId();
    final response = await _post(
      "/api/user/unlink-caregiver-child",
      body: {
        "uid": currentUserId,
        "linkedChildUserId": linkedChildUserId,
      },
    );
    return _invalidateOnSuccess(response, [
      "dashboard-summary",
      "health-summary",
      "reminder-settings",
    ]);
  }

  static Future<Map<String, dynamic>> archiveDirectChildProfile({
    String? childProfileId,
  }) async {
    final currentUserId = _requireCurrentUserId();
    final response = await _post(
      "/api/user/archive-direct-child-profile",
      body: {
        "uid": currentUserId,
        if (childProfileId != null) "childProfileId": childProfileId,
      },
    );
    return _invalidateOnSuccess(response, [
      "dashboard-summary",
      "health-summary",
      "reminder-settings",
    ]);
  }

  static Future<Map<String, dynamic>> saveMedication(
    Map<String, dynamic> data, {
    String? profileUserId,
  }) async {
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }
    data['userId'] = _userId;
    if (profileUserId != null) {
      data['profileUserId'] = profileUserId;
      data['childProfileId'] ??= profileUserId;
    }
    final response = await _post("/api/health/save-medication", body: data);
    return _invalidateOnSuccess(response, [
      "dashboard-summary",
      "health-summary",
      "analytics-summary",
    ]);
  }

  static Future<Map<String, dynamic>> updateMedication(
    String medicationId,
    Map<String, dynamic> data, {
    String? profileUserId,
  }) async {
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }
    data['userId'] = _userId;
    data['medicationId'] = medicationId;
    if (profileUserId != null) {
      data['profileUserId'] = profileUserId;
      data['childProfileId'] ??= profileUserId;
    }
    final response = await _post("/api/health/update-medication", body: data);
    return _invalidateOnSuccess(response, [
      "dashboard-summary",
      "health-summary",
      "analytics-summary",
    ]);
  }

  static Future<Map<String, dynamic>> deleteMedication(
    String medicationId, {
    String? profileUserId,
  }) async {
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }
    final response = await _post(
      "/api/health/delete-medication",
      body: {
        "userId": _userId,
        "medicationId": medicationId,
        if (profileUserId != null) "profileUserId": profileUserId,
        if (profileUserId != null) "childProfileId": profileUserId,
      },
    );
    return _invalidateOnSuccess(response, [
      "dashboard-summary",
      "health-summary",
      "analytics-summary",
    ]);
  }

  static Future<Map<String, dynamic>> markMedicationTaken(
    String medicationId, {
    String? time,
    String? expectedDate,
    String? profileUserId,
  }) async {
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }

    final response = await _post(
      "/api/health/medications/mark-taken",
      body: {
        "userId": _userId,
        "medicationId": medicationId,
        if (time != null) "time": time,
        if (expectedDate != null) "expectedDate": expectedDate,
        if (profileUserId != null) "profileUserId": profileUserId,
        if (profileUserId != null) "childProfileId": profileUserId,
      },
    );

    return _invalidateOnSuccess(response, [
      "dashboard-summary",
      "health-summary",
      "analytics-summary",
    ]);
  }

  static Future<Map<String, dynamic>> markMedicationUntaken(
    String medicationId, {
    String? time,
    String? expectedDate,
    String? profileUserId,
  }) async {
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }

    final response = await _post(
      "/api/health/medications/mark-untaken",
      body: {
        "userId": _userId,
        "medicationId": medicationId,
        if (time != null) "time": time,
        if (expectedDate != null) "expectedDate": expectedDate,
        if (profileUserId != null) "profileUserId": profileUserId,
        if (profileUserId != null) "childProfileId": profileUserId,
      },
    );

    return _invalidateOnSuccess(response, [
      "dashboard-summary",
      "health-summary",
      "analytics-summary",
    ]);
  }

  static Future<Map<String, dynamic>> extractPrescription({
    required Uint8List imageBytes,
    String contentType = "image/jpeg",
  }) async {
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }
    return _post(
      "/api/health/medications/scan",
      body: {
        "userId": _userId,
        "imageBase64": base64Encode(imageBytes),
        "contentType": contentType,
      },
    );
  }

  static Future<Map<String, dynamic>> getAiUsageStatus(String feature) async {
    final currentUserId = _requireCurrentUserId();
    final path = feature == "food_image"
        ? "/api/food/ai-usage/status"
        : "/api/health/ai-usage/status";
    return _post(
      path,
      body: {
        "userId": currentUserId,
        "feature": feature,
      },
    );
  }

  static Map<String, dynamic>? aiUsageFromResponse(Map<String, dynamic> response) {
    final usage = response["aiUsage"];
    if (usage is Map) {
      return Map<String, dynamic>.from(usage);
    }
    return null;
  }

  static String? aiUsageLabel(Map<String, dynamic>? usage) {
    if (usage == null) return null;
    final used = usage["used"] ?? usage["count"];
    final limit = usage["limit"];
    if (used == null || limit == null) return null;
    return "$used/$limit";
  }

  static String aiLimitMessage(Map<String, dynamic> response) {
    final usageLabel = aiUsageLabel(aiUsageFromResponse(response));
    final base = response["error"]?.toString().trim();
    final message = base == null || base.isEmpty
        ? "You have exceeded today's AI scan limit. Please try again tomorrow."
        : base;
    return usageLabel == null ? message : "$message\n\nUsage today: $usageLabel";
  }

  static Future<Map<String, dynamic>> confirmMedicationScan(
    Map<String, dynamic> data,
  ) async {
    if (_userId == null) {
      throw Exception("UserId not set. Please log in again.");
    }
    data['userId'] = _userId;
    final response = await _post("/api/health/medications/confirm", body: data);
    return _invalidateOnSuccess(response, [
      "dashboard-summary",
      "health-summary",
    ]);
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

  static Future<Map<String, dynamic>> requestAccountDeletion({
    required String password,
    required String totpCode,
    required String idToken,
  }) async {
    final currentUserId = _requireCurrentUserId();
    final response = await _post(
      "/api/account/delete",
      body: {
        "userId": currentUserId,
        "password": password,
        "totpCode": totpCode,
        "confirmationText": "DELETE MY ACCOUNT",
        "idToken": idToken,
      },
    );
    if (response["success"] == true) {
      ApiCache.clear();
    }
    return response;
  }

  static Future<Map<String, dynamic>> createUser({
    required String fullName,
    String? email,
    String? phoneNumber,
    required String password,
    String? userRole,
    bool privacyConsentAccepted = false,
  }) async {
    return _post(
      "/api/user/create",
      body: {
        "fullName": fullName,
        "email": email,
        "phoneNumber": phoneNumber,
        "password": password,
        "userRole": userRole,
        "privacyConsentAccepted": privacyConsentAccepted,
      },
    );
  }

  static Future<Map<String, dynamic>> updatePrivacyConsent({
    required bool accepted,
  }) async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/user/privacy-consent",
      body: {
        "uid": currentUserId,
        "accepted": accepted,
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
    return ApiCache.getOrFetch(
      _cacheKey(["user", currentUserId, "security-settings"]),
      () => _post(
        "/api/user/security-settings",
        body: {
          "uid": currentUserId,
        },
      ),
      ttl: const Duration(minutes: 5),
    );
  }

  static Future<Map<String, dynamic>> updateSecuritySettings({
    required bool mfaEnabled,
    String? mfaMethod,
    String? mfaCode,
  }) async {
    final currentUserId = _requireCurrentUserId();
    final response = await _post(
      "/api/user/update-security-settings",
      body: {
        "uid": currentUserId,
        "mfaEnabled": mfaEnabled,
        "mfaMethod": mfaMethod,
        if (mfaCode != null) "mfaCode": mfaCode,
      },
    );
    return _invalidateOnSuccess(response, [
      "security-settings",
      "dashboard-summary",
      "health-summary",
    ]);
  }

  static Future<Map<String, dynamic>> startAuthenticatorMfaSetup({
    String? email,
  }) async {
    final currentUserId = _requireCurrentUserId();
    final response = await _post(
      "/api/user/mfa/authenticator/setup/start",
      body: {
        "uid": currentUserId,
        "email": email,
      },
    );
    return _invalidateOnSuccess(response, [
      "security-settings",
      "dashboard-summary",
      "health-summary",
    ]);
  }

  static Future<Map<String, dynamic>> verifyAuthenticatorMfaSetup({
    required String code,
  }) async {
    final currentUserId = _requireCurrentUserId();
    final response = await _post(
      "/api/user/mfa/authenticator/setup/verify",
      body: {
        "uid": currentUserId,
        "code": code,
      },
    );
    return _invalidateOnSuccess(response, [
      "security-settings",
      "dashboard-summary",
      "health-summary",
    ]);
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

  static Future<Map<String, dynamic>> getGamificationSummary({
    String? profileUserId,
  }) async {
    final currentUserId = _requireCurrentUserId();
    final now = DateTime.now();
    final today =
        "${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    Future<Map<String, dynamic>> fetch() => _post(
          "/api/gamification/summary",
          body: {
            "userId": currentUserId,
            if (profileUserId != null) "profileUserId": profileUserId,
            "date": today,
          },
        );

    return ApiCache.getOrFetch(
      _cacheKey([
        "user",
        currentUserId,
        "gamification-summary",
        profileUserId ?? "active",
        today,
      ]),
      fetch,
      ttl: const Duration(minutes: 1),
    );
  }

  static Future<Map<String, dynamic>> getGamificationLeaderboard({
    int limit = 10,
  }) async {
    return ApiCache.getOrFetch(
      _cacheKey(["global", "gamification-leaderboard", limit]),
      () => _post(
        "/api/gamification/leaderboard",
        body: {"limit": limit},
      ),
      ttl: const Duration(minutes: 1),
    );
  }

  static Future<Map<String, dynamic>> updateLeaderboardVisibility({
    required bool showOnLeaderboard,
  }) async {
    final currentUserId = _requireCurrentUserId();
    final response = await _post(
      "/api/gamification/leaderboard-visibility",
      body: {
        "userId": currentUserId,
        "showOnLeaderboard": showOnLeaderboard,
      },
    );
    if (response["success"] != false) {
      _invalidateCurrentUserCache(["gamification-summary"]);
      ApiCache.invalidatePrefixes(["global|gamification-leaderboard"]);
    }
    return response;
  }

  static Future<Map<String, dynamic>> getReminderSettings({
    String? profileUserId,
  }) async {
    final currentUserId = _requireCurrentUserId();
    return ApiCache.getOrFetch(
      _cacheKey(["user", currentUserId, "reminder-settings", profileUserId]),
      () => _post(
        "/api/user/reminder-settings",
        body: {
          "uid": currentUserId,
          "profileUserId": profileUserId,
        },
      ),
      ttl: const Duration(minutes: 3),
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
    final response = await _post(
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
    return _invalidateOnSuccess(response, [
      "dashboard-summary",
      "health-summary",
      "reminder-settings",
    ]);
  }

  static Future<Map<String, dynamic>> saveCaregiverChildAgeGroup({
    required String childAgeGroup,
  }) async {
    final currentUserId = _requireCurrentUserId();
    final response = await _post(
      "/api/user/caregiver-child-age",
      body: {
        "uid": currentUserId,
        "childAgeGroup": childAgeGroup,
      },
    );
    if (response["success"] != false) {
      final childProfileId = response["childProfileId"]?.toString();
      clearProfileSetupData();
      pendingCaregiverChildAgeGroup = childAgeGroup;
      if (childProfileId != null && childProfileId.isNotEmpty) {
        activeChildProfileId = childProfileId;
        print("DEBUG: Active child profile id stored: $activeChildProfileId");
      }
    }
    return _invalidateOnSuccess(response, [
      "dashboard-summary",
      "health-summary",
    ]);
  }

  static Future<Map<String, dynamic>> generateCaregiverLinkCode() async {
    final currentUserId = _requireCurrentUserId();
    final response = await _post(
      "/api/user/generate-caregiver-link-code",
      body: {"uid": currentUserId},
    );
    return _invalidateOnSuccess(response, [
      "dashboard-summary",
      "health-summary",
    ]);
  }

  static Future<Map<String, dynamic>> linkCaregiverWithCode({
    required String linkingCode,
  }) async {
    final currentUserId = _requireCurrentUserId();
    final response = await _post(
      "/api/user/link-caregiver-account",
      body: {
        "uid": currentUserId,
        "linkingCode": linkingCode,
      },
    );
    return _invalidateOnSuccess(response, [
      "dashboard-summary",
      "health-summary",
      "reminder-settings",
    ]);
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
    final Map<String, dynamic> response;
    try {
      response = await _post(
        "/api/food/search",
        body: {
          "query": query,
          "page": page,
        },
      );
    } catch (error) {
      throw Exception(_withTryAgain(_readableError(error)));
    }
    if (response["success"] == false) {
      throw Exception(
        _withTryAgain(response["error"] ?? "Food search failed."),
      );
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
    final Map<String, dynamic> response;
    try {
      response = await _post(
        "/api/food/details",
        body: {
          "foodId": foodId,
        },
      );
    } catch (error) {
      throw Exception(_withTryAgain(_readableError(error)));
    }
    if (response["success"] == false) {
      throw Exception(
        _withTryAgain(response["error"] ?? "Food details failed."),
      );
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
    required Uint8List imageBytes,
    String contentType = "image/jpeg",
  }) async {
    final currentUserId = _requireCurrentUserId();
    final response = await _post(
      "/api/food/recognize-image",
      body: {
        "userId": currentUserId,
        "imageBase64": base64Encode(imageBytes),
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
    String? profileUserId,
    String? date,
    String? dateFrom,
    String? dateTo,
    int limit = 100,
    bool forceRefresh = false,
  }) async {
    final currentUserId = _requireCurrentUserId();
    Future<Map<String, dynamic>> fetch() => _post(
          "/api/food/logs/list",
          body: {
            "userId": currentUserId,
            if (profileUserId != null) "profileUserId": profileUserId,
            if (profileUserId != null) "childProfileId": profileUserId,
            "date": date,
            "dateFrom": dateFrom,
            "dateTo": dateTo,
            "limit": limit,
          },
        );

    final key = _cacheKey([
        "user",
        currentUserId,
        "food-logs",
        profileUserId ?? "active",
        date,
        dateFrom,
        dateTo,
        limit,
      ]);
    if (forceRefresh) ApiCache.invalidate(key);

    return ApiCache.getOrFetch(
      key,
      fetch,
      ttl: const Duration(minutes: 1),
    );
  }

  static Future<Map<String, dynamic>> addFoodLog({
    String? profileUserId,
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
    Map<String, dynamic>? fluidContribution,
    bool userConfirmedAllergyWarning = false,
  }) async {
    final currentUserId = _requireCurrentUserId();
    final response = await _post(
      "/api/food/logs/add",
      body: {
        "userId": currentUserId,
        if (profileUserId != null) "profileUserId": profileUserId,
        if (profileUserId != null) "childProfileId": profileUserId,
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
        "fluidContribution": fluidContribution,
        "userConfirmedAllergyWarning": userConfirmedAllergyWarning,
      },
    );
    return _invalidateOnSuccess(response, [
      "dashboard-summary",
      "health-summary",
      "analytics-summary",
      "food-logs",
      "gamification-summary",
    ]);
  }

  static Future<Map<String, dynamic>> previewFoodLog({
    String? profileUserId,
    required String mealType,
    required String foodId,
    required String servingId,
    required double quantity,
    String? userNotes,
  }) async {
    final currentUserId = _requireCurrentUserId();
    return _post(
      "/api/food/preview",
      body: {
        "userId": currentUserId,
        if (profileUserId != null) "profileUserId": profileUserId,
        if (profileUserId != null) "childProfileId": profileUserId,
        "mealType": mealType,
        "foodId": foodId,
        "servingId": servingId,
        "quantity": quantity,
        "loggedAt": DateTime.now().toIso8601String(),
        "userNotes": userNotes,
      },
    );
  }

  static Future<Map<String, dynamic>> deleteFoodLog(
    String foodLogId, {
    String? profileUserId,
  }) async {
    final currentUserId = _requireCurrentUserId();
    final response = await _post(
      "/api/food/logs/delete",
      body: {
        "userId": currentUserId,
        "foodLogId": foodLogId,
        if (profileUserId != null) "profileUserId": profileUserId,
        if (profileUserId != null) "childProfileId": profileUserId,
      },
    );
    return _invalidateOnSuccess(response, [
      "dashboard-summary",
      "health-summary",
      "analytics-summary",
      "food-logs",
      "gamification-summary",
    ]);
  }

  static Future<Map<String, dynamic>> updateFoodLog({
    String? profileUserId,
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
    final response = await _post(
      "/api/food/logs/update",
      body: {
        "userId": currentUserId,
        if (profileUserId != null) "profileUserId": profileUserId,
        if (profileUserId != null) "childProfileId": profileUserId,
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
    return _invalidateOnSuccess(response, [
      "dashboard-summary",
      "health-summary",
      "analytics-summary",
      "food-logs",
      "gamification-summary",
    ]);
  }
}
