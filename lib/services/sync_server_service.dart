import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/sync_models.dart';

/// 同步服务器 - 接收来自其他设备的连接和数据
class SyncServerService {
  HttpServer? _server;
  int _port = 8765;
  DeviceInfo? _currentDevice;

  // WebSocket 连接管理
  final Map<String, WebSocketChannel> _connections = {};
  final Map<String, DeviceInfo> _connectedDevices = {};

  // 消息处理回调
  Function(SyncMessage message, String fromDeviceId)? onMessageReceived;
  Function(String deviceId, DeviceInfo device)? onDeviceConnected;
  Function(String deviceId)? onDeviceDisconnected;

  bool get isRunning => _server != null;
  int get port => _port;
  List<DeviceInfo> get connectedDevices => _connectedDevices.values.toList();

  /// 启动服务器
  Future<bool> start(DeviceInfo currentDevice, {int port = 8765}) async {
    if (_server != null) {
      print('⚠️  [SyncServer] 服务器已在运行');
      return false;
    }

    _currentDevice = currentDevice;
    _port = port;

    // 尝试多个端口（如果原端口被占用）
    final portsToTry = [_port, _port + 1, _port + 2, _port + 3, _port + 4];

    for (final tryPort in portsToTry) {
      try {
        // 创建路由处理器
        final handler = Cascade()
            .add(_createWebSocketHandler())
            .add(_createHttpHandler())
            .handler;

        // 启动服务器
        _server = await shelf_io.serve(
          handler,
          InternetAddress.anyIPv4,
          tryPort,
        );

        _port = tryPort; // 更新实际使用的端口
        print(
            '✅ [SyncServer] 服务器启动成功: ${_server!.address.host}:${_server!.port}');

        // 如果使用了备用端口，给出提示
        if (tryPort != port) {
          print('ℹ️  [SyncServer] 原端口 $port 被占用，使用备用端口 $tryPort');
        }

        return true;
      } catch (e) {
        if (tryPort == portsToTry.last) {
          // 所有端口都失败了
          print('❌ [SyncServer] 启动失败: $e');
          print('❌ [SyncServer] 已尝试端口: ${portsToTry.join(", ")}');
          return false;
        } else {
          // 尝试下一个端口
          print('⚠️  [SyncServer] 端口 $tryPort 不可用，尝试下一个端口...');
        }
      }
    }

    return false;
  }

  /// 停止服务器
  Future<void> stop() async {
    if (_server == null) return;

    print('🛑 [SyncServer] 停止服务器');

    // 关闭所有连接
    for (final connection in _connections.values) {
      await connection.sink.close();
    }
    _connections.clear();
    _connectedDevices.clear();

    // 关闭服务器
    await _server?.close(force: true);
    _server = null;
  }

  /// 创建 WebSocket 处理器
  Handler _createWebSocketHandler() {
    return webSocketHandler((WebSocketChannel webSocket) {
      print('🔌 [SyncServer] 新的 WebSocket 连接');

      String? deviceId;
      Timer? pingTimer;

      // 监听消息
      webSocket.stream.listen(
        (dynamic data) {
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            final message = SyncMessage.fromJson(json);

            print('📨 [SyncServer] 收到消息: ${message.type}');

            // 处理握手
            if (message.type == SyncMessageType.handshake) {
              deviceId = message.senderId;
              if (deviceId != null) {
                _connections[deviceId!] = webSocket;

                // 解析设备信息
                final deviceInfo = DeviceInfo.fromJson(message.data!);
                _connectedDevices[deviceId!] = deviceInfo;

                print('🤝 [SyncServer] 设备已连接: ${deviceInfo.deviceName}');

                // 通知外部
                onDeviceConnected?.call(deviceId!, deviceInfo);

                // 发送握手响应
                final response = SyncMessage.handshake(_currentDevice!);
                _sendMessage(deviceId!, response);

                // 启动心跳
                pingTimer =
                    Timer.periodic(const Duration(seconds: 30), (timer) {
                  if (_connections.containsKey(deviceId)) {
                    _sendMessage(
                        deviceId!, SyncMessage.ping(_currentDevice!.deviceId));
                  } else {
                    timer.cancel();
                  }
                });
              }
            }
            // 处理心跳
            else if (message.type == SyncMessageType.ping) {
              _sendMessage(message.senderId!,
                  SyncMessage.pong(_currentDevice!.deviceId));
            }
            // 其他消息转发给外部处理
            else {
              if (message.senderId != null) {
                onMessageReceived?.call(message, message.senderId!);
              }
            }
          } catch (e) {
            print('❌ [SyncServer] 处理消息失败: $e');
          }
        },
        onDone: () {
          print('👋 [SyncServer] 连接关闭: $deviceId');
          if (deviceId != null) {
            _connections.remove(deviceId);
            _connectedDevices.remove(deviceId);
            onDeviceDisconnected?.call(deviceId!);
          }
          pingTimer?.cancel();
        },
        onError: (error) {
          print('❌ [SyncServer] 连接错误: $error');
          if (deviceId != null) {
            _connections.remove(deviceId);
            _connectedDevices.remove(deviceId);
            onDeviceDisconnected?.call(deviceId!);
          }
          pingTimer?.cancel();
        },
      );
    });
  }

  /// 创建 HTTP 处理器
  Handler _createHttpHandler() {
    return (Request request) async {
      // 健康检查
      if (request.url.path == 'health') {
        return Response.ok('OK');
      }

      // 设备信息
      if (request.url.path == 'info') {
        return Response.ok(
          jsonEncode(_currentDevice!.toJson()),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // 404
      return Response.notFound('Not Found');
    };
  }

  /// 发送消息给指定设备
  void _sendMessage(String deviceId, SyncMessage message) {
    final connection = _connections[deviceId];
    if (connection != null) {
      try {
        connection.sink.add(jsonEncode(message.toJson()));
        print('📤 [SyncServer] 发送消息到 $deviceId: ${message.type}');
      } catch (e) {
        print('❌ [SyncServer] 发送消息失败: $e');
      }
    }
  }

  /// 广播消息给所有连接的设备
  void broadcastMessage(SyncMessage message) {
    print('📡 [SyncServer] 开始广播消息');
    print('   消息类型: ${message.type}');
    print('   发送者ID: ${message.senderId}');
    print('   当前设备ID: ${_currentDevice?.deviceId}');
    print('   已连接设备数: ${_connections.length}');

    if (_connections.isEmpty) {
      print('⚠️  [SyncServer] 没有连接的设备，无法广播');
      return;
    }

    int successCount = 0;
    for (final deviceId in _connections.keys) {
      print('   → 发送到设备: $deviceId');
      print('      是发送者本身? ${deviceId == message.senderId}');
      _sendMessage(deviceId, message);
      successCount++;
    }
    print('📢 [SyncServer] 广播消息完成: ${message.type} (成功发送到 $successCount 个设备)');
  }

  /// 发送消息给指定设备 (公开接口)
  void sendMessageToDevice(String deviceId, SyncMessage message) {
    _sendMessage(deviceId, message);
  }

  /// 获取已连接设备信息
  DeviceInfo? getConnectedDevice(String deviceId) {
    return _connectedDevices[deviceId];
  }

  /// 是否有设备连接
  bool get hasConnections => _connections.isNotEmpty;

  /// 连接数量
  int get connectionCount => _connections.length;
}
