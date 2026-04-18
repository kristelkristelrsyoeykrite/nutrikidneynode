/// User account status enum for tracking progression through auth and onboarding
enum UserStatus {
  unauthenticated,      // No active session
  pendingVerification,  // Email/phone verification required
  verified,             // Email/phone verified, ready for profile setup
  profileSetupInProgress, // Currently setting up health profile
  profileComplete,      // Profile setup complete
  active,               // Fully onboarded and active user
}

extension UserStatusExtension on UserStatus {
  /// Convert enum to string for Firebase/database storage
  String toShortString() {
    return toString().split('.').last;
  }

  /// Convert string from Firebase/database to enum
  static UserStatus fromString(String status) {
    try {
      return UserStatus.values.firstWhere(
        (e) => e.toShortString() == status,
      );
    } catch (e) {
      return UserStatus.unauthenticated;
    }
  }

  /// Get display name for debugging/logging
  String getDisplayName() {
    switch (this) {
      case UserStatus.unauthenticated:
        return 'Unauthenticated';
      case UserStatus.pendingVerification:
        return 'Pending Verification';
      case UserStatus.verified:
        return 'Verified';
      case UserStatus.profileSetupInProgress:
        return 'Profile Setup In Progress';
      case UserStatus.profileComplete:
        return 'Profile Complete';
      case UserStatus.active:
        return 'Active';
    }
  }
}
