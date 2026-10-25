class ChildModel {
  final int? id;
  final String childCode;
  final String displayName;
  final int? age;
  final String pinHash;
  final String? schoolName;
  final String? remoteUserId;
  final bool isActive;
  final String createdAt;
  final String updatedAt;

  const ChildModel({
    this.id,
    required this.childCode,
    required this.displayName,
    this.age,
    required this.pinHash,
    this.schoolName,
    this.remoteUserId,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'child_code': childCode,
      'display_name': displayName,
      'age': age,
      'pin_hash': pinHash,
      if (schoolName != null) 'school_name': schoolName,
      if (remoteUserId != null) 'remote_user_id': remoteUserId,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory ChildModel.fromMap(Map<String, dynamic> map) {
    return ChildModel(
      id: map['id'] as int?,
      childCode: map['child_code'] as String,
      displayName: map['display_name'] as String,
      age: map['age'] as int?,
      pinHash: map['pin_hash'] as String,
      schoolName: map['school_name'] as String?,
      remoteUserId: map['remote_user_id'] as String?,
      isActive: (map['is_active'] as int? ?? 1) == 1,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }

  ChildModel copyWith({
    int? id,
    String? childCode,
    String? displayName,
    int? age,
    String? pinHash,
    String? schoolName,
    String? remoteUserId,
    bool? isActive,
    String? createdAt,
    String? updatedAt,
  }) {
    return ChildModel(
      id: id ?? this.id,
      childCode: childCode ?? this.childCode,
      displayName: displayName ?? this.displayName,
      age: age ?? this.age,
      pinHash: pinHash ?? this.pinHash,
      schoolName: schoolName ?? this.schoolName,
      remoteUserId: remoteUserId ?? this.remoteUserId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}