class UserSession {
  UserSession._internal();

  static final UserSession instance = UserSession._internal();

  String? uid;
  String? name;
  String? phone;
  String? lastRiskLevel;

  void setUser({
    required String uid,
    required String name,
    required String phone,
  }) {
    this.uid = uid;
    this.name = name;
    this.phone = phone;
  }

  void setLastRiskLevel(String level) {
    lastRiskLevel = level;
  }

  void clear() {
    uid = null;
    name = null;
    phone = null;
    lastRiskLevel = null;
  }
}

