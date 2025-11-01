import 'dart:async';
import 'dart:io';

/// 同步错误类型
enum SyncErrorType {
  // 网络相关
  networkUnavailable, // 网络不可用
  connectionTimeout, // 连接超时
  connectionFailed, // 连接失败
  connectionLost, // 连接丢失

  // 设备相关
  deviceNotFound, // 设备未找到
  deviceOffline, // 设备离线
  deviceBusy, // 设备忙碌

  // 数据相关
  dataCorrupted, // 数据损坏
  dataConflict, // 数据冲突
  dataValidationFailed, // 数据验证失败
  dataTooLarge, // 数据过大

  // 系统相关
  portInUse, // 端口被占用
  permissionDenied, // 权限被拒绝
  resourceExhausted, // 资源耗尽

  // 操作相关
  operationCancelled, // 操作取消
  operationTimeout, // 操作超时
  operationInProgress, // 操作正在进行中（并发冲突）

  // 未知错误
  unknown, // 未知错误
}

/// 同步错误
class SyncError implements Exception {
  final SyncErrorType type;
  final String message;
  final String? details;
  final Object? originalError;
  final StackTrace? stackTrace;
  final DateTime timestamp;
  final bool isRecoverable; // 是否可恢复

  SyncError({
    required this.type,
    required this.message,
    this.details,
    this.originalError,
    this.stackTrace,
    DateTime? timestamp,
    this.isRecoverable = true,
  }) : timestamp = timestamp ?? DateTime.now();

  /// 获取用户友好的错误消息
  String getUserFriendlyMessage() {
    switch (type) {
      case SyncErrorType.networkUnavailable:
        return '网络不可用，请检查网络连接';
      case SyncErrorType.connectionTimeout:
        return '连接超时，请检查网络或重试';
      case SyncErrorType.connectionFailed:
        return '连接失败，请确保设备在同一网络';
      case SyncErrorType.connectionLost:
        return '连接已断开，正在尝试重新连接...';
      case SyncErrorType.deviceNotFound:
        return '未找到设备，请确保对方已启用同步';
      case SyncErrorType.deviceOffline:
        return '设备已离线';
      case SyncErrorType.deviceBusy:
        return '设备正忙，请稍后重试';
      case SyncErrorType.dataCorrupted:
        return '数据损坏，请重新同步';
      case SyncErrorType.dataConflict:
        return '数据冲突，已自动解决';
      case SyncErrorType.dataValidationFailed:
        return '数据验证失败';
      case SyncErrorType.dataTooLarge:
        return '数据过大，请分批同步';
      case SyncErrorType.portInUse:
        return '端口被占用，已自动切换端口';
      case SyncErrorType.permissionDenied:
        return '权限不足，请检查应用权限';
      case SyncErrorType.resourceExhausted:
        return '系统资源不足';
      case SyncErrorType.operationCancelled:
        return '操作已取消';
      case SyncErrorType.operationTimeout:
        return '操作超时';
      case SyncErrorType.operationInProgress:
        return '同步操作正在进行中';
      case SyncErrorType.unknown:
        return '发生未知错误';
    }
  }

  /// 获取建议的操作
  String getSuggestion() {
    switch (type) {
      case SyncErrorType.networkUnavailable:
        return '请检查WiFi连接，确保设备连接到同一网络';
      case SyncErrorType.connectionTimeout:
      case SyncErrorType.connectionFailed:
        return '请确保两台设备在同一WiFi网络，关闭路由器的AP隔离';
      case SyncErrorType.deviceNotFound:
        return '请在对方设备上启用同步功能';
      case SyncErrorType.portInUse:
        return '应用已自动切换到备用端口，无需操作';
      case SyncErrorType.dataConflict:
        return '冲突已按最新修改时间自动解决';
      case SyncErrorType.permissionDenied:
        return '请在系统设置中授予应用网络权限';
      case SyncErrorType.operationInProgress:
        return '请等待当前同步完成后再试';
      default:
        return '请重试或重启应用';
    }
  }

  /// 是否需要显示给用户
  bool shouldShowToUser() {
    // 某些错误不需要显示给用户
    switch (type) {
      case SyncErrorType.dataConflict: // 自动解决的冲突
      case SyncErrorType.portInUse: // 自动切换端口
      case SyncErrorType.operationInProgress: // 操作进行中（已在UI上显示）
        return false;
      default:
        return true;
    }
  }

  @override
  String toString() {
    final buffer = StringBuffer();
    buffer.writeln('SyncError: $message');
    buffer.writeln('Type: $type');
    if (details != null) {
      buffer.writeln('Details: $details');
    }
    if (originalError != null) {
      buffer.writeln('Original Error: $originalError');
    }
    return buffer.toString();
  }

  /// 从异常创建同步错误
  factory SyncError.fromException(Object error, {StackTrace? stackTrace}) {
    // 根据异常类型判断错误类型
    SyncErrorType type = SyncErrorType.unknown;
    String message = error.toString();
    bool isRecoverable = true;

    if (error is SocketException) {
      if (error.osError?.errorCode == 10061 || // Windows: Connection refused
          error.osError?.errorCode == 111) {
        // Linux: Connection refused
        type = SyncErrorType.connectionFailed;
        message = '连接被拒绝';
      } else if (error.osError?.errorCode == 10048 || // Windows: Address in use
          error.osError?.errorCode == 98) {
        // Linux: Address in use
        type = SyncErrorType.portInUse;
        message = '端口已被占用';
      } else if (error.message.contains('Network is unreachable')) {
        type = SyncErrorType.networkUnavailable;
        message = '网络不可达';
      } else {
        type = SyncErrorType.connectionFailed;
        message = '网络连接失败';
      }
    } else if (error is TimeoutException) {
      type = SyncErrorType.connectionTimeout;
      message = '连接超时';
    } else if (error is FormatException) {
      type = SyncErrorType.dataCorrupted;
      message = '数据格式错误';
      isRecoverable = false;
    }

    return SyncError(
      type: type,
      message: message,
      originalError: error,
      stackTrace: stackTrace,
      isRecoverable: isRecoverable,
    );
  }

  /// 创建网络错误
  factory SyncError.network(String message, {Object? originalError}) {
    return SyncError(
      type: SyncErrorType.networkUnavailable,
      message: message,
      originalError: originalError,
    );
  }

  /// 创建连接错误
  factory SyncError.connection(String message, {Object? originalError}) {
    return SyncError(
      type: SyncErrorType.connectionFailed,
      message: message,
      originalError: originalError,
    );
  }

  /// 创建超时错误
  factory SyncError.timeout(String message) {
    return SyncError(
      type: SyncErrorType.connectionTimeout,
      message: message,
    );
  }

  /// 创建数据错误
  factory SyncError.dataError(String message, {Object? originalError}) {
    return SyncError(
      type: SyncErrorType.dataCorrupted,
      message: message,
      originalError: originalError,
      isRecoverable: false,
    );
  }
}
