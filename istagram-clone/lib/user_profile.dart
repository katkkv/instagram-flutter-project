class UserProfile {
  final String id;
  final String username;
  final String email;
  final String bio;

  UserProfile({
    required this.id,
    required this.username,
    required this.email,
    required this.bio,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'bio': bio,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'] ?? '', // Обработка отсутствующего значения
      username: map['username'] ?? '', // Обработка отсутствующего значения
      email: map['email'] ?? '', // Обработка отсутствующего значения
      bio: map['bio'] ?? '',
    );
  }

  // Добавление метода toJson
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'bio': bio,
    };
  }

  // Добавление метода fromJson
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] ?? '', // Обработка отсутствующего значения
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      bio: json['bio'] ?? '',
    );
  }

  @override
  String toString() {
    return 'UserProfile{id: $id, username: $username, email: $email, bio: $bio}';
  }
}