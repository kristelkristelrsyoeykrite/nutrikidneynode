import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String baseUrl = "http://10.251.113.184:3000";
  static String? _userId; // Store userId from signup
  
  // Store each step's data locally
  static Map<String, dynamic> step1Data = {};
  static Map<String, dynamic> step2Data = {};
  static Map<String, dynamic> step3Data = {};
  static Map<String, dynamic> step4Data = {};
  // Pending signup data collected during registration; actual signup occurs on final submit
  static Map<String, dynamic> signupData = {};

  static void setUserId(String userId) {
    _userId = userId;
    print("DEBUG: UserId stored: $_userId");
  }

  static void setSignupData(Map<String, dynamic> data) {
    signupData = data;
    print("DEBUG: Signup data stored: $signupData");
  }

  static Future<void> sendStep1(Map<String, dynamic> data) async {
    print("Step 1 data collected: $data");
    step1Data = data;
    
    final response = await http.post(
      Uri.parse("$baseUrl/api/health/step1"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(data),
    );

    print("Step 1 Response: ${response.body}");
  }
  static Future<void> sendStep2(Map<String, dynamic> data) async {
  print("Step 2 data collected: $data");
  step2Data = data;
  
  final response = await http.post(
    Uri.parse("$baseUrl/api/health/step2"),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode(data),
  );

  print("Step 2 Response: ${response.body}");
}
static Future<void> sendStep3(Map<String, dynamic> data) async {
  print("Step 3 data collected: $data");
  step3Data = data;
  
  final response = await http.post(
    Uri.parse("$baseUrl/api/health/step3"),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode(data),
  );

  print("Step 3 Response: ${response.body}");
}

static Future<void> sendStep4(Map<String, dynamic> data) async {
  print("Step 4 data collected: $data");
  step4Data = data;
  
  final response = await http.post(
    Uri.parse("$baseUrl/api/health/step4"),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode(data),
  );

  print("Step 4 Response: ${response.body}");
}

  // FINAL SUBMIT - Send all collected data to database
  static Future<Map<String, dynamic>> submitAll() async {
    if (_userId == null) {
      throw Exception("UserId not set. Please complete signup first.");
    }

    print("DEBUG: Submitting all data for user: $_userId");
    
    final allData = {
      "userId": _userId,
      "step1": step1Data,
      "step2": step2Data,
      "step3": step3Data,
      "step4": step4Data,
    };

    print("DEBUG: Final submission data: $allData");

    final response = await http.post(
      Uri.parse("$baseUrl/api/health/submit-all"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(allData),
    );

    print("DEBUG: Submit-all response status: ${response.statusCode}");
    print("DEBUG: Submit-all response body: ${response.body}");

    final decoded = jsonDecode(response.body);
    return decoded;
  }
static Future<Map<String, dynamic>> signup(Map<String, dynamic> data) async {
  print("DEBUG: Calling signup with data: $data");
  final response = await http.post(
    Uri.parse("$baseUrl/signup"),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode(data),
  );

  print("DEBUG: Signup response status: ${response.statusCode}");
  print("DEBUG: Signup response body: ${response.body}");

  final decoded = jsonDecode(response.body);
  
  // Store userId after successful signup
  if (decoded["success"] == true && decoded["userId"] != null) {
    setUserId(decoded["userId"]);
  }

  return decoded;
}

  static Future<Map<String, dynamic>> checkUserExists(Map<String, dynamic> data) async {
    print("DEBUG: Checking if user exists with: $data");
    final response = await http.post(
      Uri.parse("$baseUrl/check-user"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(data),
    );

    print("DEBUG: check-user status: ${response.statusCode}");
    print("DEBUG: check-user body: ${response.body}");

    final decoded = jsonDecode(response.body);
    return decoded;
  }

  static Future<Map<String, dynamic>> verifyPhonePassword(Map<String, dynamic> data) async {
    print("DEBUG: Verifying phone password with: $data");
    final response = await http.post(
      Uri.parse("$baseUrl/verify-phone-password"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(data),
    );

    print("DEBUG: verify-phone-password status: ${response.statusCode}");
    print("DEBUG: verify-phone-password body: ${response.body}");

    final decoded = jsonDecode(response.body);
    return decoded;
  }

  static Future<Map<String, dynamic>> resetPassword(Map<String, dynamic> data) async {
    print("DEBUG: Resetting password with: $data");
    final response = await http.post(
      Uri.parse("$baseUrl/reset-password"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(data),
    );

    print("DEBUG: reset-password status: ${response.statusCode}");
    print("DEBUG: reset-password body: ${response.body}");

    final decoded = jsonDecode(response.body);
    return decoded;
  }

  static Future<Map<String, dynamic>> verifyEmailDomain(Map<String, dynamic> data) async {
    print("DEBUG: Verifying email domain with: $data");
    final response = await http.post(
      Uri.parse("$baseUrl/verify-email-domain"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(data),
    );

    print("DEBUG: verify-email-domain status: ${response.statusCode}");
    print("DEBUG: verify-email-domain body: ${response.body}");

    final decoded = jsonDecode(response.body);
    return decoded;
  }

  static Future<Map<String, dynamic>> verifyEmailAndCreateProfile(Map<String, dynamic> data) async {
    print("DEBUG: Calling verify-email-and-create-user with data: $data");
    final response = await http.post(
      Uri.parse("$baseUrl/verify-email-and-create-user"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(data),
    );

    print("DEBUG: verify-email-and-create-user status: ${response.statusCode}");
    print("DEBUG: verify-email-and-create-user body: ${response.body}");

    final decoded = jsonDecode(response.body);
    
    // Store userId after successful verification
    if (decoded["success"] == true && decoded["userId"] != null) {
      setUserId(decoded["userId"]);
    }

    return decoded;
  }

  static Future<Map<String, dynamic>> verifyPhoneAndCreateProfile(Map<String, dynamic> data) async {
    print("DEBUG: Calling verify-phone-and-create-user with data: $data");
    final response = await http.post(
      Uri.parse("$baseUrl/verify-phone-and-create-user"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(data),
    );

    print("DEBUG: verify-phone-and-create-user status: ${response.statusCode}");
    print("DEBUG: verify-phone-and-create-user body: ${response.body}");

    final decoded = jsonDecode(response.body);
    
    // Store userId after successful verification
    if (decoded["success"] == true && decoded["userId"] != null) {
      setUserId(decoded["userId"]);
    }

    return decoded;
  }

  static Future<Map<String, dynamic>> sendEmailVerification(Map<String, dynamic> data) async {
    print("DEBUG: Calling send-email-verification with data: $data");
    final response = await http.post(
      Uri.parse("$baseUrl/send-email-verification"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(data),
    );

    print("DEBUG: send-email-verification status: ${response.statusCode}");
    print("DEBUG: send-email-verification body: ${response.body}");

    final decoded = jsonDecode(response.body);
    return decoded;
  }

  static Future<Map<String, dynamic>> verifyEmailToken(Map<String, dynamic> data) async {
    print("DEBUG: Calling verify-email-and-create-user with data: $data");
    final response = await http.post(
      Uri.parse("$baseUrl/verify-email-and-create-user"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(data),
    );

    print("DEBUG: verify-email-and-create-user status: ${response.statusCode}");
    print("DEBUG: verify-email-and-create-user body: ${response.body}");

    final decoded = jsonDecode(response.body);
    
    // Store userId after successful verification
    if (decoded["success"] == true && decoded["userId"] != null) {
      setUserId(decoded["userId"]);
    }

    return decoded;
  }

  // New method for post-verification email user creation
  static Future<Map<String, dynamic>> createUserAfterEmailVerification(Map<String, dynamic> data) async {
    print("DEBUG: Creating user after email verification with data: $data");
    final response = await http.post(
      Uri.parse("$baseUrl/verify-email-and-create-user"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode(data),
    );

    print("DEBUG: Email user creation status: ${response.statusCode}");
    print("DEBUG: Email user creation body: ${response.body}");

    final decoded = jsonDecode(response.body);
    
    // Store userId after successful creation
    if (decoded["success"] == true && decoded["userId"] != null) {
      setUserId(decoded["userId"]);
    }

    return decoded;
  }
}

