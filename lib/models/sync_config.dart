/// 同步连接配置
class SyncConnectionConfig {
  /// 连接超时时间（秒）
  final int connectionTimeout;

  /// WebSocket握手超时时间（秒）
  final int handshakeTimeout;

  /// 数据传输超时时间（秒）
  final int dataTransferTimeout;

  /// 心跳间隔（秒）
  final int pingInterval;

  /// 心跳超时时间（秒）
  final int pingTimeout;

  /// 是否自动重连
  final bool autoReconnect;

  /// 最大重连次数（0表示无限重连）
  final int maxReconnectAttempts;

  /// 重连延迟（秒）- 基础值
  final int reconnectDelay;

  /// 是否使用指数退避重连
  final bool useExponentialBackoff;

  /// 指数退避最大延迟（秒）
  final int maxReconnectDelay;

  const SyncConnectionConfig({
    this.connectionTimeout = 10,
    this.handshakeTimeout = 5,
    this.dataTransferTimeout = 30,
    this.pingInterval = 30,
    this.pingTimeout = 10,
    this.autoReconnect = true,
    this.maxReconnectAttempts = 5,
    this.reconnectDelay = 3,
    this.useExponentialBackoff = true,
    this.maxReconnectDelay = 60,
  });

  /// 默认配置
  static const SyncConnectionConfig defaultConfig = SyncConnectionConfig();

  /// 快速连接配置（更短的超时时间）
  static const SyncConnectionConfig fast = SyncConnectionConfig(
    connectionTimeout: 5,
    handshakeTimeout: 3,
    dataTransferTimeout: 15,
    pingInterval: 15,
    maxReconnectAttempts: 3,
  );

  /// 稳定连接配置（更长的超时时间，更多重试）
  static const SyncConnectionConfig stable = SyncConnectionConfig(
    connectionTimeout: 15,
    handshakeTimeout: 8,
    dataTransferTimeout: 60,
    pingInterval: 45,
    maxReconnectAttempts: 10,
    reconnectDelay: 5,
  );

  /// 计算重连延迟（支持指数退避）
  Duration getReconnectDelay(int attemptNumber) {
    if (!useExponentialBackoff) {
      return Duration(seconds: reconnectDelay);
    }

    // 指数退避：delay * 2^(attemptNumber-1)
    final delaySeconds = reconnectDelay * (1 << (attemptNumber - 1));
    final cappedDelay =
        delaySeconds > maxReconnectDelay ? maxReconnectDelay : delaySeconds;

    return Duration(seconds: cappedDelay);
  }

  /// 从JSON创建
  factory SyncConnectionConfig.fromJson(Map<String, dynamic> json) {
    return SyncConnectionConfig(
      connectionTimeout: json['connectionTimeout'] as int? ?? 10,
      handshakeTimeout: json['handshakeTimeout'] as int? ?? 5,
      dataTransferTimeout: json['dataTransferTimeout'] as int? ?? 30,
      pingInterval: json['pingInterval'] as int? ?? 30,
      pingTimeout: json['pingTimeout'] as int? ?? 10,
      autoReconnect: json['autoReconnect'] as bool? ?? true,
      maxReconnectAttempts: json['maxReconnectAttempts'] as int? ?? 5,
      reconnectDelay: json['reconnectDelay'] as int? ?? 3,
      useExponentialBackoff: json['useExponentialBackoff'] as bool? ?? true,
      maxReconnectDelay: json['maxReconnectDelay'] as int? ?? 60,
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() {
    return {
      'connectionTimeout': connectionTimeout,
      'handshakeTimeout': handshakeTimeout,
      'dataTransferTimeout': dataTransferTimeout,
      'pingInterval': pingInterval,
      'pingTimeout': pingTimeout,
      'autoReconnect': autoReconnect,
      'maxReconnectAttempts': maxReconnectAttempts,
      'reconnectDelay': reconnectDelay,
      'useExponentialBackoff': useExponentialBackoff,
      'maxReconnectDelay': maxReconnectDelay,
    };
  }

  /// 复制并修改部分属性
  SyncConnectionConfig copyWith({
    int? connectionTimeout,
    int? handshakeTimeout,
    int? dataTransferTimeout,
    int? pingInterval,
    int? pingTimeout,
    bool? autoReconnect,
    int? maxReconnectAttempts,
    int? reconnectDelay,
    bool? useExponentialBackoff,
    int? maxReconnectDelay,
  }) {
    return SyncConnectionConfig(
      connectionTimeout: connectionTimeout ?? this.connectionTimeout,
      handshakeTimeout: handshakeTimeout ?? this.handshakeTimeout,
      dataTransferTimeout: dataTransferTimeout ?? this.dataTransferTimeout,
      pingInterval: pingInterval ?? this.pingInterval,
      pingTimeout: pingTimeout ?? this.pingTimeout,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      maxReconnectAttempts: maxReconnectAttempts ?? this.maxReconnectAttempts,
      reconnectDelay: reconnectDelay ?? this.reconnectDelay,
      useExponentialBackoff:
          useExponentialBackoff ?? this.useExponentialBackoff,
      maxReconnectDelay: maxReconnectDelay ?? this.maxReconnectDelay,
    );
  }
}
