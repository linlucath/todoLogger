import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 设备信息
class DeviceInfo {
  final String deviceId;
  final String deviceName;
  final String ipAddress;
  final int port;
  final DateTime lastSeen;
  final bool isConnected;

  DeviceInfo({
    required this.deviceId,
    required this.deviceName,
    required this.ipAddress,
    required this.port,
    required this.lastSeen,
    this.isConnected = false,
  });

  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
      ipAddress: json['ipAddress'] as String,
      port: json['port'] as int,
      lastSeen: DateTime.parse(json['lastSeen'] as String),
      isConnected: json['isConnected'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'deviceId': deviceId,
      'deviceName': deviceName,
      'ipAddress': ipAddress,
      'port': port,
      'lastSeen': lastSeen.toIso8601String(),
      'isConnected': isConnected,
    };
  }

  DeviceInfo copyWith({
    String? deviceId,
    String? deviceName,
    String? ipAddress,
    int? port,
    DateTime? lastSeen,
    bool? isConnected,
  }) {
    return DeviceInfo(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      lastSeen: lastSeen ?? this.lastSeen,
      isConnected: isConnected ?? this.isConnected,
    );
  }

  /// 生成当前设备信息（持久化设备ID和设备名称）
  static Future<DeviceInfo> getCurrentDevice(int port) async {
    final prefs = await SharedPreferences.getInstance();

    // 1️⃣ 持久化设备ID - 确保同一设备始终使用相同ID
    String? deviceId = prefs.getString('sync_device_id');
    if (deviceId == null) {
      const uuid = Uuid();
      deviceId = uuid.v4();
      await prefs.setString('sync_device_id', deviceId);
      print('🆕 [DeviceInfo] 生成新设备ID: $deviceId');
    } else {
      print('📱 [DeviceInfo] 加载已有设备ID: $deviceId');
    }

    // 2️⃣ 持久化设备名称 - 用户可修改，优先使用保存的名称
    String? deviceName = prefs.getString('sync_device_name');
    if (deviceName == null) {
      // 首次运行，根据平台生成默认名称
      deviceName = Platform.isWindows
          ? 'Windows-${Platform.localHostname}'
          : Platform.isMacOS
              ? 'Mac-${Platform.localHostname}'
              : Platform.isLinux
                  ? 'Linux-${Platform.localHostname}'
                  : Platform.isAndroid
                      ? 'Android-${Platform.localHostname}'
                      : Platform.isIOS
                          ? 'iOS-${Platform.localHostname}'
                          : 'Unknown-${Platform.localHostname}';
      await prefs.setString('sync_device_name', deviceName);
      print('🆕 [DeviceInfo] 生成新设备名称: $deviceName');
    } else {
      print('📝 [DeviceInfo] 加载已有设备名称: $deviceName');
    }

    return DeviceInfo(
      deviceId: deviceId,
      deviceName: deviceName,
      ipAddress: '', // 将在运行时获取
      port: port,
      lastSeen: DateTime.now(),
      isConnected: true,
    );
  }

  /// 更新设备名称（允许用户自定义设备名称）
  static Future<void> updateDeviceName(String newName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sync_device_name', newName);
    print('✏️  [DeviceInfo] 更新设备名称: $newName');
  }

  /// 获取当前保存的设备ID（用于调试）
  static Future<String?> getSavedDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('sync_device_id');
  }

  /// 获取当前保存的设备名称（用于调试）
  static Future<String?> getSavedDeviceName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('sync_device_name');
  }

  /// 重置设备信息（仅用于测试或故障排除）
  static Future<void> resetDeviceInfo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sync_device_id');
    await prefs.remove('sync_device_name');
    print('🔄 [DeviceInfo] 已重置设备信息');
  }
}

/// 同步消息类型
enum SyncMessageType {
  // 连接相关
  handshake, // 握手
  ping, // 心跳
  pong, // 心跳响应

  // 数据同步
  dataRequest, // 请求数据
  dataResponse, // 响应数据
  dataUpdate, // 数据更新通知

  // 实时计时
  timerStart, // 开始计时
  timerStop, // 停止计时
  timerUpdate, // 计时更新
  timerForceStop, // 强制停止计时（冲突解决）

  // 错误
  error, // 错误消息
}

/// 同步消息
class SyncMessage {
  final String messageId;
  final SyncMessageType type;
  final String? senderId;
  final DateTime timestamp;
  final Map<String, dynamic>? data;
  final String? syncSessionId; // 用于防止循环同步

  SyncMessage({
    String? messageId,
    required this.type,
    this.senderId,
    DateTime? timestamp,
    this.data,
    this.syncSessionId,
  })  : messageId = messageId ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now();

  factory SyncMessage.fromJson(Map<String, dynamic> json) {
    return SyncMessage(
      messageId: json['messageId'] as String,
      type: SyncMessageType.values
          .firstWhere((e) => e.toString() == json['type'] as String),
      senderId: json['senderId'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      data: json['data'] as Map<String, dynamic>?,
      syncSessionId: json['syncSessionId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'type': type.toString(),
      'senderId': senderId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
      if (syncSessionId != null) 'syncSessionId': syncSessionId,
    };
  }

  /// 创建握手消息
  static SyncMessage handshake(DeviceInfo device) {
    return SyncMessage(
      type: SyncMessageType.handshake,
      senderId: device.deviceId,
      data: device.toJson(),
    );
  }

  /// 创建心跳消息
  static SyncMessage ping(String deviceId) {
    return SyncMessage(
      type: SyncMessageType.ping,
      senderId: deviceId,
    );
  }

  /// 创建心跳响应消息
  static SyncMessage pong(String deviceId) {
    return SyncMessage(
      type: SyncMessageType.pong,
      senderId: deviceId,
    );
  }

  /// 创建数据请求消息
  static SyncMessage dataRequest(String deviceId, String dataType) {
    return SyncMessage(
      type: SyncMessageType.dataRequest,
      senderId: deviceId,
      data: {'dataType': dataType},
    );
  }

  /// 创建数据响应消息
  static SyncMessage dataResponse(
      String deviceId, String dataType, dynamic responseData) {
    return SyncMessage(
      type: SyncMessageType.dataResponse,
      senderId: deviceId,
      data: {
        'dataType': dataType,
        'data': responseData,
      },
    );
  }

  /// 创建数据更新消息
  static SyncMessage dataUpdate(
      String deviceId, String dataType, dynamic updateData,
      {String? syncSessionId}) {
    return SyncMessage(
      type: SyncMessageType.dataUpdate,
      senderId: deviceId,
      syncSessionId: syncSessionId,
      data: {
        'dataType': dataType,
        'data': updateData,
      },
    );
  }

  /// 🎯 创建计时开始消息
  ///
  /// 这是计时器同步的第一步：当一个设备上的计时器启动时，创建此消息广播给其他设备
  ///
  /// 参数说明：
  /// - [deviceId] 发起计时的设备ID（发送方标识）
  /// - [activityId] 活动的唯一标识符（由UUID生成，确保全局唯一）
  /// - [activityName] 活动名称（用户输入，如"学习"、"工作"等）
  /// - [startTime] 计时开始的精确时间戳
  /// - [initialDuration] 发送消息时计时器已运行的秒数（默认为0）
  /// - [linkedTodoId] 可选：关联的待办事项ID（如果计时器绑定了某个Todo）
  /// - [linkedTodoTitle] 可选：关联的待办事项标题（用于显示）
  ///
  /// 消息结构示例：
  /// ```json
  /// {
  ///   "type": "timerStart",
  ///   "senderId": "device-123-abc",
  ///   "data": {
  ///     "activityId": "uuid-xxx-yyy-zzz",
  ///     "activityName": "学习",
  ///     "startTime": "2025-11-05T10:30:00.000Z",
  ///     "initialDuration": 0,
  ///     "linkedTodoId": "todo-456",
  ///     "linkedTodoTitle": "完成作业"
  ///   }
  /// }
  /// ```
  ///
  /// 这个消息会通过 TCP Socket 发送到所有已连接的设备
  static SyncMessage timerStart({
    required String deviceId,
    required String activityId,
    required String activityName,
    required DateTime startTime,
    int initialDuration = 0,
    String? linkedTodoId,
    String? linkedTodoTitle,
  }) {
    return SyncMessage(
      type: SyncMessageType.timerStart,
      senderId: deviceId,
      data: {
        'activityId': activityId,
        'activityName': activityName,
        'linkedTodoId': linkedTodoId,
        'linkedTodoTitle': linkedTodoTitle,
        'startTime': startTime.toIso8601String(),
        'initialDuration': initialDuration,
      },
    );
  }

  /// 🛑 创建计时停止消息
  ///
  /// 当计时器停止时，创建此消息通知所有设备移除该计时器
  ///
  /// 参数说明：
  /// - [deviceId] 停止计时的设备ID
  /// - [activityId] 要停止的活动ID（必须与启动时的ID匹配）
  /// - [startTime] 计时开始时间（用于验证）
  /// - [endTime] 计时结束时间
  /// - [duration] 总持续时间（秒）
  ///
  /// 消息结构示例：
  /// ```json
  /// {
  ///   "type": "timerStop",
  ///   "senderId": "device-123-abc",
  ///   "data": {
  ///     "activityId": "uuid-xxx-yyy-zzz",
  ///     "startTime": "2025-11-05T10:30:00.000Z",
  ///     "endTime": "2025-11-05T11:00:00.000Z",
  ///     "duration": 1800  // 30分钟 = 1800秒
  ///   }
  /// }
  /// ```
  ///
  /// 接收方会验证 activityId 是否匹配，防止误删其他活动
  static SyncMessage timerStop({
    required String deviceId,
    required String activityId,
    required DateTime startTime,
    required DateTime endTime,
    required int duration,
  }) {
    return SyncMessage(
      type: SyncMessageType.timerStop,
      senderId: deviceId,
      data: {
        'activityId': activityId,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'duration': duration,
      },
    );
  }

  /// ⏱️ 创建计时更新消息
  ///
  /// 定期（每秒）广播计时器的当前时长，保持所有设备同步
  ///
  /// 参数说明：
  /// - [deviceId] 发送更新的设备ID
  /// - [activityId] 活动ID（用于识别是哪个计时器）
  /// - [currentDuration] 当前累计时长（秒）
  ///
  /// 消息结构示例：
  /// ```json
  /// {
  ///   "type": "timerUpdate",
  ///   "senderId": "device-123-abc",
  ///   "data": {
  ///     "activityId": "uuid-xxx-yyy-zzz",
  ///     "currentDuration": 125  // 已运行2分5秒
  ///   }
  /// }
  /// ```
  ///
  /// 为什么需要定期更新？
  /// 1. 保持所有设备显示的时长一致
  /// 2. 帮助新连接的设备快速同步当前状态
  /// 3. 检测网络连接是否正常（心跳机制）
  static SyncMessage timerUpdate({
    required String deviceId,
    required String activityId,
    required int currentDuration,
  }) {
    return SyncMessage(
      type: SyncMessageType.timerUpdate,
      senderId: deviceId,
      data: {
        'activityId': activityId,
        'currentDuration': currentDuration,
      },
    );
  }

  /// 创建错误消息
  static SyncMessage error(String deviceId, String errorMessage) {
    return SyncMessage(
      type: SyncMessageType.error,
      senderId: deviceId,
      data: {'error': errorMessage},
    );
  }
}

/// 📊 计时器状态数据模型
///
/// 这个类表示一个正在运行的计时器的完整状态，用于在多设备间同步显示
///
/// 设计理念：
/// - activityId 作为唯一标识（UUID），确保不同设备间的计时器可以准确匹配
/// - linkedTodoId 是可选的，允许计时器独立存在或与待办事项关联
/// - 包含设备信息（deviceId, deviceName），便于在UI上显示"谁在做什么"
///
/// 使用场景：
/// 1. 本地计时器：用户在当前设备启动计时
/// 2. 远程计时器：从其他设备同步过来，显示在"其他设备活动"列表中
///
/// 同步流程：
/// ```
/// 设备A启动计时 -> 创建TimerState -> 广播timerStart消息
///   -> 设备B收到消息 -> 创建TimerState -> 显示在UI上
///   -> 定期收到timerUpdate -> 更新currentDuration
///   -> 收到timerStop -> 移除TimerState
/// ```
class TimerState {
  /// 活动的唯一ID（UUID格式）
  /// 例如: "550e8400-e29b-41d4-a716-446655440000"
  /// 这是跨设备识别同一个计时器的关键
  final String activityId;

  /// 活动名称（用户可见）
  /// 例如: "学习"、"工作"、"健身"
  final String activityName;

  /// 可选：关联的Todo项ID
  /// 如果用户从待办事项启动计时，这里会记录Todo的ID
  /// 用于在计时结束后自动标记Todo为完成
  final String? linkedTodoId;

  /// 可选：关联的Todo项标题
  /// 用于在UI上显示，例如："完成数学作业"
  final String? linkedTodoTitle;

  /// 计时开始的精确时间戳（远程设备的时间）
  /// 注意：由于设备间可能存在时间差，不应直接使用此时间计算时长
  final DateTime startTime;

  /// 本地接收到计时器消息时的时间
  /// 用于计算相对时长，避免设备时间差导致的问题
  final DateTime receivedAt;

  /// 接收时计时器已运行的初始秒数
  /// 例如：如果远程设备已经运行了10秒才发送消息，这里就是10
  final int initialDuration;

  /// 当前累计时长（秒）
  /// 每秒更新一次，通过 timerUpdate 消息同步
  final int currentDuration;

  /// 运行此计时器的设备ID
  /// 用于区分是本地计时器还是远程计时器
  final String deviceId;

  /// 运行此计时器的设备名称
  /// 用于在UI上显示，例如："iPhone 13 Pro"
  final String deviceName;

  TimerState({
    required this.activityId,
    required this.activityName,
    this.linkedTodoId,
    this.linkedTodoTitle,
    required this.startTime,
    DateTime? receivedAt,
    int? initialDuration,
    required this.currentDuration,
    required this.deviceId,
    required this.deviceName,
  })  : receivedAt = receivedAt ?? DateTime.now(),
        initialDuration = initialDuration ?? 0;

  factory TimerState.fromJson(Map<String, dynamic> json) {
    return TimerState(
      activityId: json['activityId'] as String,
      activityName: json['activityName'] as String,
      linkedTodoId: json['linkedTodoId'] as String?,
      linkedTodoTitle: json['linkedTodoTitle'] as String?,
      startTime: DateTime.parse(json['startTime'] as String),
      receivedAt: json['receivedAt'] != null
          ? DateTime.parse(json['receivedAt'] as String)
          : DateTime.now(),
      initialDuration: (json['initialDuration'] as int?) ?? 0,
      currentDuration: json['currentDuration'] as int,
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'activityId': activityId,
      'activityName': activityName,
      'linkedTodoId': linkedTodoId,
      'linkedTodoTitle': linkedTodoTitle,
      'startTime': startTime.toIso8601String(),
      'receivedAt': receivedAt.toIso8601String(),
      'initialDuration': initialDuration,
      'currentDuration': currentDuration,
      'deviceId': deviceId,
      'deviceName': deviceName,
    };
  }

  TimerState copyWith({
    String? activityId,
    String? activityName,
    String? linkedTodoId,
    String? linkedTodoTitle,
    DateTime? startTime,
    DateTime? receivedAt,
    int? initialDuration,
    int? currentDuration,
    String? deviceId,
    String? deviceName,
  }) {
    return TimerState(
      activityId: activityId ?? this.activityId,
      activityName: activityName ?? this.activityName,
      linkedTodoId: linkedTodoId ?? this.linkedTodoId,
      linkedTodoTitle: linkedTodoTitle ?? this.linkedTodoTitle,
      startTime: startTime ?? this.startTime,
      receivedAt: receivedAt ?? this.receivedAt,
      initialDuration: initialDuration ?? this.initialDuration,
      currentDuration: currentDuration ?? this.currentDuration,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
    );
  }
}

/// 同步数据类型
enum SyncDataType {
  todos, // 待办事项
  timeLogs, // 时间日志
  targets, // 目标
  statistics, // 统计数据
  all, // 所有数据
}

/// 数据同步更新事件
class SyncDataUpdatedEvent {
  final String dataType; // 数据类型：todos, timeLogs, targets
  final String fromDeviceId; // 来源设备ID
  final String fromDeviceName; // 来源设备名称
  final int itemCount; // 更新的项目数量
  final DateTime timestamp; // 时间戳

  SyncDataUpdatedEvent({
    required this.dataType,
    required this.fromDeviceId,
    required this.fromDeviceName,
    required this.itemCount,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// 同步进度事件
class SyncProgressEvent {
  final String deviceId; // 目标设备ID
  final String deviceName; // 目标设备名称
  final String
      phase; // 当前阶段：connecting, syncing_todos, syncing_logs, syncing_targets, completed
  final String dataType; // 当前同步的数据类型
  final int currentItem; // 当前处理的项目索引
  final int totalItems; // 总项目数
  final double progress; // 进度百分比 (0.0 - 1.0)
  final String? message; // 状态消息
  final DateTime timestamp; // 时间戳

  SyncProgressEvent({
    required this.deviceId,
    required this.deviceName,
    required this.phase,
    required this.dataType,
    this.currentItem = 0,
    this.totalItems = 0,
    this.progress = 0.0,
    this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  SyncProgressEvent copyWith({
    String? deviceId,
    String? deviceName,
    String? phase,
    String? dataType,
    int? currentItem,
    int? totalItems,
    double? progress,
    String? message,
    DateTime? timestamp,
  }) {
    return SyncProgressEvent(
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      phase: phase ?? this.phase,
      dataType: dataType ?? this.dataType,
      currentItem: currentItem ?? this.currentItem,
      totalItems: totalItems ?? this.totalItems,
      progress: progress ?? this.progress,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}
