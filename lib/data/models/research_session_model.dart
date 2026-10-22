class ResearchSessionModel {
  final int? id;
  final String? clientSessionUuid;
  final int childId;
  final int deviceId;
  final int sessionNumber;
  final String startedAt;
  final String? endedAt;
  final String? notes;
  final bool isSynced;

  const ResearchSessionModel({
    this.id,
    this.clientSessionUuid,
    required this.childId,
    required this.deviceId,
    required this.sessionNumber,
    required this.startedAt,
    this.endedAt,
    this.notes,
    this.isSynced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      if (clientSessionUuid != null) 'client_session_uuid': clientSessionUuid,
      'child_id': childId,
      'device_id': deviceId,
      'session_number': sessionNumber,
      'started_at': startedAt,
      'ended_at': endedAt,
      'notes': notes,
      'is_synced': isSynced ? 1 : 0,
    };
  }

  factory ResearchSessionModel.fromMap(Map<String, dynamic> map) {
    return ResearchSessionModel(
      id: map['id'] as int?,
      clientSessionUuid: map['client_session_uuid'] as String?,
      childId: map['child_id'] as int,
      deviceId: map['device_id'] as int,
      sessionNumber: map['session_number'] as int,
      startedAt: map['started_at'] as String,
      endedAt: map['ended_at'] as String?,
      notes: map['notes'] as String?,
      isSynced: (map['is_synced'] as int?) == 1,
    );
  }

  ResearchSessionModel copyWith({
    int? id,
    String? clientSessionUuid,
    int? childId,
    int? deviceId,
    int? sessionNumber,
    String? startedAt,
    String? endedAt,
    String? notes,
    bool? isSynced,
  }) {
    return ResearchSessionModel(
      id: id ?? this.id,
      clientSessionUuid: clientSessionUuid ?? this.clientSessionUuid,
      childId: childId ?? this.childId,
      deviceId: deviceId ?? this.deviceId,
      sessionNumber: sessionNumber ?? this.sessionNumber,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      notes: notes ?? this.notes,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}

