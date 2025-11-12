/// 计时器操作记录模型
///
/// 专门用于同步场景下的计时器冲突检测和解决
/// 独立于 ActivityRecord，只关注计时器的启动/停止操作
/// 类似 Git 的 reflog，记录每一次计时器状态变化

/// 计时器操作类型
enum TimerOperationType {
  start, // 启动计时器
  stop, // 停止计时器
  pause, // 暂停（预留）
  resume, // 恢复（预留）
}

/// 计时器操作记录
///
/// 每次计时器启动或停止时创建一条记录，用于：
/// 1. 跨设备同步时判断计时器的最新状态
/// 2. 检测并解决计时器冲突（例如：设备 A 正在计时，设备 B 已停止同一活动）
/// 3. 提供操作历史追溯能力
class TimerOperationRecord {
  /// 操作ID（UUID，全局唯一）
  final String operationId;

  /// 活动ID（关联到具体的活动）
  final String activityId;

  /// 活动名称（冗余字段，便于调试）
  final String activityName;

  /// 操作类型（启动/停止）
  final TimerOperationType operationType;

  /// 操作时间戳
  final DateTime operationTime;

  /// 操作发起的设备ID
  final String deviceId;

  /// 操作发起的设备名称
  final String deviceName;

  /// 对于 stop 操作：活动的实际结束时间（可能与 operationTime 不同）
  /// 对于 start 操作：活动的实际开始时间
  final DateTime? actualTime;

  /// 关联的 Todo ID（如果有）
  final String? linkedTodoId;

  /// 操作序列号（同一活动的操作按顺序递增）
  /// 用于判断操作的先后顺序，解决时间戳可能的误差
  final int sequenceNumber;

  /// 是否已同步到所有设备
  final bool isSynced;

  TimerOperationRecord({
    required this.operationId,
    required this.activityId,
    required this.activityName,
    required this.operationType,
    required this.operationTime,
    required this.deviceId,
    required this.deviceName,
    this.actualTime,
    this.linkedTodoId,
    required this.sequenceNumber,
    this.isSynced = false,
  });

  /// 从 JSON 创建
  factory TimerOperationRecord.fromJson(Map<String, dynamic> json) {
    return TimerOperationRecord(
      operationId: json['operationId'] as String,
      activityId: json['activityId'] as String,
      activityName: json['activityName'] as String,
      operationType: TimerOperationType.values.firstWhere(
        (e) => e.name == json['operationType'],
      ),
      operationTime: DateTime.parse(json['operationTime'] as String),
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      actualTime: json['actualTime'] != null
          ? DateTime.parse(json['actualTime'] as String)
          : null,
      linkedTodoId: json['linkedTodoId'] as String?,
      sequenceNumber: json['sequenceNumber'] as int,
      isSynced: json['isSynced'] as bool? ?? false,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'operationId': operationId,
      'activityId': activityId,
      'activityName': activityName,
      'operationType': operationType.name,
      'operationTime': operationTime.toIso8601String(),
      'deviceId': deviceId,
      'deviceName': deviceName,
      'actualTime': actualTime?.toIso8601String(),
      'linkedTodoId': linkedTodoId,
      'sequenceNumber': sequenceNumber,
      'isSynced': isSynced,
    };
  }

  /// 创建副本
  TimerOperationRecord copyWith({
    String? operationId,
    String? activityId,
    String? activityName,
    TimerOperationType? operationType,
    DateTime? operationTime,
    String? deviceId,
    String? deviceName,
    DateTime? actualTime,
    String? linkedTodoId,
    int? sequenceNumber,
    bool? isSynced,
  }) {
    return TimerOperationRecord(
      operationId: operationId ?? this.operationId,
      activityId: activityId ?? this.activityId,
      activityName: activityName ?? this.activityName,
      operationType: operationType ?? this.operationType,
      operationTime: operationTime ?? this.operationTime,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      actualTime: actualTime ?? this.actualTime,
      linkedTodoId: linkedTodoId ?? this.linkedTodoId,
      sequenceNumber: sequenceNumber ?? this.sequenceNumber,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  @override
  String toString() {
    return 'TimerOperation('
        'type: ${operationType.name}, '
        'activity: $activityName, '
        'device: $deviceName, '
        'time: $operationTime, '
        'seq: $sequenceNumber)';
  }
}

/// 计时器状态快照
///
/// 用于快速判断某个活动的当前状态，避免遍历所有操作记录
class TimerStateSnapshot {
  /// 活动ID
  final String activityId;

  /// 最后一次操作类型
  final TimerOperationType lastOperation;

  /// 最后一次操作时间
  final DateTime lastOperationTime;

  /// 最后一次操作的设备ID
  final String lastOperationDevice;

  /// 最后一次操作的序列号
  final int lastSequenceNumber;

  /// 是否正在运行
  bool get isRunning => lastOperation == TimerOperationType.start;

  TimerStateSnapshot({
    required this.activityId,
    required this.lastOperation,
    required this.lastOperationTime,
    required this.lastOperationDevice,
    required this.lastSequenceNumber,
  });

  factory TimerStateSnapshot.fromJson(Map<String, dynamic> json) {
    return TimerStateSnapshot(
      activityId: json['activityId'] as String,
      lastOperation: TimerOperationType.values.firstWhere(
        (e) => e.name == json['lastOperation'],
      ),
      lastOperationTime: DateTime.parse(json['lastOperationTime'] as String),
      lastOperationDevice: json['lastOperationDevice'] as String,
      lastSequenceNumber: json['lastSequenceNumber'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'activityId': activityId,
      'lastOperation': lastOperation.name,
      'lastOperationTime': lastOperationTime.toIso8601String(),
      'lastOperationDevice': lastOperationDevice,
      'lastSequenceNumber': lastSequenceNumber,
    };
  }

  @override
  String toString() {
    return 'TimerSnapshot(activity: $activityId, '
        'status: ${isRunning ? "RUNNING" : "STOPPED"}, '
        'lastOp: ${lastOperation.name}, '
        'device: $lastOperationDevice)';
  }
}

/// 计时器冲突检测结果
class TimerConflictResult {
  /// 是否存在冲突
  final bool hasConflict;

  /// 冲突类型
  final TimerConflictType? conflictType;

  /// 冲突描述
  final String description;

  /// 应该采取的操作
  final TimerConflictAction? suggestedAction;

  /// 相关的操作记录
  final List<TimerOperationRecord> relatedOperations;

  TimerConflictResult({
    required this.hasConflict,
    this.conflictType,
    required this.description,
    this.suggestedAction,
    this.relatedOperations = const [],
  });

  /// 无冲突
  factory TimerConflictResult.noConflict() {
    return TimerConflictResult(
      hasConflict: false,
      description: '无冲突',
    );
  }

  /// 远程已停止
  factory TimerConflictResult.remoteStopped(
    TimerOperationRecord stopOperation,
  ) {
    return TimerConflictResult(
      hasConflict: true,
      conflictType: TimerConflictType.remoteStopped,
      description: '活动已在设备 ${stopOperation.deviceName} 停止',
      suggestedAction: TimerConflictAction.stopLocal,
      relatedOperations: [stopOperation],
    );
  }

  /// 远程正在运行
  factory TimerConflictResult.remoteRunning(
    TimerOperationRecord startOperation,
  ) {
    return TimerConflictResult(
      hasConflict: true,
      conflictType: TimerConflictType.remoteRunning,
      description: '活动正在设备 ${startOperation.deviceName} 运行',
      suggestedAction: TimerConflictAction.acceptRemote,
      relatedOperations: [startOperation],
    );
  }

  /// 多设备同时运行
  factory TimerConflictResult.multipleRunning(
    List<TimerOperationRecord> operations,
  ) {
    return TimerConflictResult(
      hasConflict: true,
      conflictType: TimerConflictType.multipleRunning,
      description: '多个设备同时运行相同活动',
      suggestedAction: TimerConflictAction.keepLatest,
      relatedOperations: operations,
    );
  }
}

/// 冲突类型
enum TimerConflictType {
  remoteStopped, // 远程已停止，本地还在运行
  remoteRunning, // 远程正在运行，本地已停止或未运行
  multipleRunning, // 多个设备同时运行
  sequenceOutOfOrder, // 操作序列乱序
}

/// 建议的冲突解决操作
enum TimerConflictAction {
  stopLocal, // 停止本地计时器
  acceptRemote, // 接受远程状态
  keepLatest, // 保留最新的操作
  requestUserDecision, // 请求用户决定
}
