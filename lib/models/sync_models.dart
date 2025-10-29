import 'dart:io';
import 'package:uuid/uuid.dart';

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

  /// 生成当前设备信息
  static Future<DeviceInfo> getCurrentDevice(int port) async {
    final uuid = const Uuid();
    final deviceId = uuid.v4();
    final deviceName = Platform.isWindows
        ? 'Windows-${Platform.localHostname}'
        : Platform.isMacOS
            ? 'Mac-${Platform.localHostname}'
            : Platform.isLinux
                ? 'Linux-${Platform.localHostname}'
                : Platform.isAndroid
                    ? 'Android'
                    : Platform.isIOS
                        ? 'iOS'
                        : 'Unknown';

    return DeviceInfo(
      deviceId: deviceId,
      deviceName: deviceName,
      ipAddress: '', // 将在运行时获取
      port: port,
      lastSeen: DateTime.now(),
      isConnected: true,
    );
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
