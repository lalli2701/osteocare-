class UserSession {
  UserSession._internal();

  static final UserSession instance = UserSession._internal();

  String? userId;
  String? userName;
  String? phone;
  String? lastRiskLevel;

  void setUser({
    required String userId,
    required String userName,
    required String phone,
  }) {
    this.userId = userId;
    this.userName = userName;
    this.phone = phone;
  }

  void setLastRiskLevel(String level) {
    lastRiskLevel = level;
  }

  void clear() {
    userId = null;
    userName = null;
    phone = null;
    lastRiskLevel = null;
  }
}