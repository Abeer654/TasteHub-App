// ============================================================
//  user.dart - the logged-in account shape
// ============================================================

class User {
  const User({required this.id, required this.username});

  final int id;
  final String username;

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] is num ? (json['id'] as num).toInt() : 0,
      username: json['username'] is String ? json['username'] as String : '',
    );
  }
}

class AuthSession {
  const AuthSession({required this.token, required this.user});

  final String token;
  final User user;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final user = json['user'];
    return AuthSession(
      token: json['token'] is String ? json['token'] as String : '',
      user: user is Map<String, dynamic>
          ? User.fromJson(user)
          : const User(id: 0, username: ''),
    );
  }
}
