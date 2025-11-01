import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/sync_models.dart';

/// 同步客户端 - 连接到其他设备
class SyncClientService {
  WebSocketChannel? _channel;
  DeviceInfo? _currentDevice;
  DeviceInfo? _remoteDevice;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

  bool _isConnected = false;
  bool _shouldReconnect = false;

  // 重连配置 - 指数退避策略
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 10;
  static const Duration _minReconnectDelay = Duration(seconds: 1);
  static const Duration _maxReconnectDelay = Duration(seconds: 60);

  // 消息处理回调
  Function(SyncMessage message)? onMessageReceived;
  Function()? onConnected;
  Function()? onDisconnected;

  bool get isConnected => _isConnected;
  DeviceInfo? get remoteDevice => _remoteDevice;
  int get reconnectAttempts => _reconnectAttempts;

  /// 连接到远程设备
  Future<bool> connect(
      DeviceInfo currentDevice, DeviceInfo targetDevice) async {
    if (_isConnected) {
      print('⚠️  [SyncClient] 已经连接到设备');
      return false;
    }

    _currentDevice = currentDevice;
    _remoteDevice = targetDevice;
    _shouldReconnect = true;

    return await _doConnect();
  }

  /// 执行连接
  Future<bool> _doConnect() async {
    if (_remoteDevice == null || _currentDevice == null) {
      print('❌ [SyncClient] 设备信息不完整');
      return false;
    }

    try {
      final wsUrl =
          'ws://${_remoteDevice!.ipAddress}:${_remoteDevice!.port}/ws';
      print('🔗 [SyncClient] 尝试连接: $wsUrl (尝试 ${_reconnectAttempts + 1})');
      print('🔍 [SyncClient] 目标设备: ${_remoteDevice!.deviceName}');
      print('🔍 [SyncClient] 目标IP: ${_remoteDevice!.ipAddress}');
      print('🔍 [SyncClient] 目标端口: ${_remoteDevice!.port}');

      print('⏳ [SyncClient] 创建WebSocket连接...');
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));

      // 等待连接建立
      print('⏳ [SyncClient] 等待连接就绪...');
      await _channel!.ready;

      _isConnected = true;
      _reconnectAttempts = 0; // 重置重连计数
      print('✅ [SyncClient] WebSocket连接就绪');

      // 发送握手
      _sendHandshake();

      // 监听消息
      _startListening();

      // 启动心跳
      _startPingTimer();

      // 通知连接成功
      onConnected?.call();
      print('🎉 [SyncClient] 连接成功: ${_remoteDevice!.deviceName}');

      return true;
    } catch (e, stack) {
      print('❌ [SyncClient] 连接失败: $e');
      print('❌ [SyncClient] 错误类型: ${e.runtimeType}');
      print('❌ [SyncClient] 堆栈: $stack');
      print(
          '🔍 [SyncClient] 目标信息: ${_remoteDevice!.ipAddress}:${_remoteDevice!.port}');
      _isConnected = false;

      // 尝试重连
      if (_shouldReconnect) {
        _scheduleReconnect();
      }

      return false;
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    print('👋 [SyncClient] 断开连接');

    _shouldReconnect = false;
    _isConnected = false;

    _pingTimer?.cancel();
    _pingTimer = null;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    await _channel?.sink.close();
    _channel = null;

    onDisconnected?.call();
  }

  /// 发送握手消息
  void _sendHandshake() {
    if (_currentDevice == null) return;

    final message = SyncMessage.handshake(_currentDevice!);
    sendMessage(message);
    print('🤝 [SyncClient] 发送握手');
  }

  /// 开始监听消息
  void _startListening() {
    _channel?.stream.listen(
      (dynamic data) {
        try {
          final json = jsonDecode(data as String) as Map<String, dynamic>;
          final message = SyncMessage.fromJson(json);

          print('📨 [SyncClient] 收到消息: ${message.type}');

          // 处理心跳
          if (message.type == SyncMessageType.ping) {
            sendMessage(SyncMessage.pong(_currentDevice!.deviceId));
          }
          // 处理握手响应
          else if (message.type == SyncMessageType.handshake) {
            _remoteDevice = DeviceInfo.fromJson(message.data!);
            print('🤝 [SyncClient] 握手完成: ${_remoteDevice!.deviceName}');
          }
          // 其他消息转发给外部处理
          else {
            onMessageReceived?.call(message);
          }
        } catch (e) {
          print('❌ [SyncClient] 处理消息失败: $e');
        }
      },
      onDone: () {
        print('👋 [SyncClient] 连接关闭');
        _handleDisconnect();
      },
      onError: (error) {
        print('❌ [SyncClient] 连接错误: $error');
        _handleDisconnect();
      },
    );
  }

  /// 处理断开连接
  void _handleDisconnect() {
    _isConnected = false;
    _pingTimer?.cancel();
    _pingTimer = null;

    onDisconnected?.call();

    // 尝试重连
    if (_shouldReconnect) {
      _scheduleReconnect();
    }
  }

  /// 启动心跳定时器
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_isConnected && _currentDevice != null) {
        sendMessage(SyncMessage.ping(_currentDevice!.deviceId));
      }
    });
  }

  /// 计划重连（指数退避策略）
  void _scheduleReconnect() {
    _reconnectTimer?.cancel();

    // 检查是否超过最大重连次数
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('❌ [SyncClient] 已达到最大重连次数 ($_maxReconnectAttempts)，停止重连');
      _shouldReconnect = false;
      return;
    }

    // 计算指数退避延迟: min(minDelay * 2^attempts, maxDelay)
    final delaySeconds =
        (_minReconnectDelay.inSeconds * (1 << _reconnectAttempts))
            .clamp(_minReconnectDelay.inSeconds, _maxReconnectDelay.inSeconds);
    final delay = Duration(seconds: delaySeconds);

    _reconnectAttempts++;
    print(
        '⏱️  [SyncClient] ${delay.inSeconds}秒后尝试重连... (尝试 $_reconnectAttempts/$_maxReconnectAttempts)');

    _reconnectTimer = Timer(delay, () {
      if (_shouldReconnect && !_isConnected) {
        print('🔄 [SyncClient] 尝试重连...');
        _doConnect();
      }
    });
  }

  /// 发送消息
  void sendMessage(SyncMessage message) {
    if (!_isConnected || _channel == null) {
      print('⚠️  [SyncClient] 未连接,无法发送消息');
      return;
    }

    try {
      _channel!.sink.add(jsonEncode(message.toJson()));
      print('📤 [SyncClient] 发送消息: ${message.type}');
    } catch (e) {
      print('❌ [SyncClient] 发送消息失败: $e');
    }
  }

  /// 请求数据
  void requestData(String dataType) {
    if (_currentDevice == null) return;
    sendMessage(SyncMessage.dataRequest(_currentDevice!.deviceId, dataType));
  }

  /// 发送数据响应
  void sendDataResponse(String dataType, dynamic data) {
    if (_currentDevice == null) return;
    sendMessage(
        SyncMessage.dataResponse(_currentDevice!.deviceId, dataType, data));
  }

  /// 发送数据更新
  void sendDataUpdate(String dataType, dynamic data) {
    if (_currentDevice == null) return;
    sendMessage(
        SyncMessage.dataUpdate(_currentDevice!.deviceId, dataType, data));
  }

  /// 发送计时开始
  void sendTimerStart(String todoId, DateTime startTime) {
    if (_currentDevice == null) return;
    sendMessage(
        SyncMessage.timerStart(_currentDevice!.deviceId, todoId, startTime));
  }

  /// 发送计时停止
  void sendTimerStop(
      String todoId, DateTime startTime, DateTime endTime, int duration) {
    if (_currentDevice == null) return;
    sendMessage(SyncMessage.timerStop(
        _currentDevice!.deviceId, todoId, startTime, endTime, duration));
  }

  /// 发送计时更新
  void sendTimerUpdate(String todoId, int currentDuration) {
    if (_currentDevice == null) return;
    sendMessage(SyncMessage.timerUpdate(
        _currentDevice!.deviceId, todoId, currentDuration));
  }

  /// 释放资源
  void dispose() {
    disconnect();
  }
}
