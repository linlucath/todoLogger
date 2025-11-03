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
      final uuid = const Uuid();
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

  SyncMessage({
    String? messageId,
    required this.type,
    this.senderId,
    DateTime? timestamp,
    this.data,
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'type': type.toString(),
      'senderId': senderId,
      'timestamp': timestamp.toIso8601String(),
      'data': data,
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
      String deviceId, String dataType, dynamic updateData) {
    return SyncMessage(
      type: SyncMessageType.dataUpdate,
      senderId: deviceId,
      data: {
        'dataType': dataType,
        'data': updateData,
      },
    );
  }

  /// 创建计时开始消息
  static SyncMessage timerStart(
      String deviceId, String todoId, DateTime startTime) {
    return SyncMessage(
      type: SyncMessageType.timerStart,
      senderId: deviceId,
      data: {
        'todoId': todoId,
        'startTime': startTime.toIso8601String(),
      },
    );
  }

  /// 创建计时停止消息
  static SyncMessage timerStop(String deviceId, String todoId,
      DateTime startTime, DateTime endTime, int duration) {
    return SyncMessage(
      type: SyncMessageType.timerStop,
      senderId: deviceId,
      data: {
        'todoId': todoId,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'duration': duration,
      },
    );
  }

  /// 创建计时更新消息
  static SyncMessage timerUpdate(
      String deviceId, String todoId, int currentDuration) {
    return SyncMessage(
      type: SyncMessageType.timerUpdate,
      senderId: deviceId,
      data: {
        'todoId': todoId,
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

/// 计时状态
class TimerState {
  final String todoId;
  final String todoTitle;
  final DateTime startTime;
  final int currentDuration; // 秒
  final String deviceId;
  final String deviceName;

  TimerState({
    required this.todoId,
    required this.todoTitle,
    required this.startTime,
    required this.currentDuration,
    required this.deviceId,
    required this.deviceName,
  });

  factory TimerState.fromJson(Map<String, dynamic> json) {
    return TimerState(
      todoId: json['todoId'] as String,
      todoTitle: json['todoTitle'] as String,
      startTime: DateTime.parse(json['startTime'] as String),
      currentDuration: json['currentDuration'] as int,
      deviceId: json['deviceId'] as String,
      deviceName: json['deviceName'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'todoId': todoId,
      'todoTitle': todoTitle,
      'startTime': startTime.toIso8601String(),
      'currentDuration': currentDuration,
      'deviceId': deviceId,
      'deviceName': deviceName,
    };
  }

  TimerState copyWith({
    String? todoId,
    String? todoTitle,
    DateTime? startTime,
    int? currentDuration,
    String? deviceId,
    String? deviceName,
  }) {
    return TimerState(
      todoId: todoId ?? this.todoId,
      todoTitle: todoTitle ?? this.todoTitle,
      startTime: startTime ?? this.startTime,
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
