class DeviceModel {
  final int? id;
  final String deviceId;
  final String? deviceLabel;
  final String platform;
  final String? appVersion;
  final String registeredAt;
  final String? lastUsedAt;

  const DeviceModel({
    this.id,
    required this.deviceId,
    this.deviceLabel,
    required this.platform,
    this.appVersion,
    required this.registeredAt,
    this.lastUsedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'device_id': deviceId,
      'device_label': deviceLabel,
      'platform': platform,
      'app_version': appVersion,
      'registered_at': registeredAt,
      'last_used_at': lastUsedAt,
    };
  }

  factory DeviceModel.fromMap(Map<String, dynamic> map) {
    return DeviceModel(
      id: map['id'] as int?,
      deviceId: map['device_id'] as String,
      deviceLabel: map['device_label'] as String?,
      platform: map['platform'] as String,
      appVersion: map['app_version'] as String?,
      registeredAt: map['registered_at'] as String,
      lastUsedAt: map['last_used_at'] as String?,
    );
  }

  DeviceModel copyWith({
    int? id,
    String? deviceId,
    String? deviceLabel,
    String? platform,
    String? appVersion,
    String? registeredAt,
    String? lastUsedAt,
  }) {
    return DeviceModel(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      deviceLabel: deviceLabel ?? this.deviceLabel,
      platform: platform ?? this.platform,
      appVersion: appVersion ?? this.appVersion,
      registeredAt: registeredAt ?? this.registeredAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }
}
