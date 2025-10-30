import 'dart:async';
import 'dart:io';
import 'dart:convert';
import '../models/sync_models.dart';

/// 设备发现服务 - 使用 UDP 广播在局域网内发现其他设备
class DeviceDiscoveryService {
  static const int broadcastPort = 8766; // UDP广播端口
  static const String broadcastAddress = '255.255.255.255'; // 广播地址

  RawDatagramSocket? _socket;
  final Map<String, DeviceInfo> _discoveredDevices = {};
  final StreamController<List<DeviceInfo>> _devicesController =
      StreamController.broadcast();

  Timer? _broadcastTimer;
  Timer? _cleanupTimer;

  String? _currentDeviceId;
  String? _currentDeviceName;
  int _syncPort = 8765; // 同步服务端口（可动态更新）

  /// 获取已发现的设备列表
  Stream<List<DeviceInfo>> get devicesStream => _devicesController.stream;
  List<DeviceInfo> get devices => _discoveredDevices.values.toList();

  /// 开始服务发现
  Future<void> startDiscovery(String deviceId, String deviceName,
      {int syncPort = 8765}) async {
    _currentDeviceId = deviceId;
    _currentDeviceName = deviceName;
    _syncPort = syncPort;
    print(
        '🟢 [DeviceDiscovery] 初始化UDP广播设备发现: deviceId=$deviceId, deviceName=$deviceName, port=$syncPort');

    try {
      // 绑定UDP socket到广播端口
      _socket =
          await RawDatagramSocket.bind(InternetAddress.anyIPv4, broadcastPort);
      _socket!.broadcastEnabled = true;
      print('🔍 [DeviceDiscovery] UDP Socket已绑定到端口 $broadcastPort');

      // 开始监听UDP消息
      _startListening();

      // 开始广播自己的设备信息
      _startBroadcasting();

      // 定期清理过期设备
      _startCleanup();
    } catch (e, stack) {
      print('❌ [DeviceDiscovery] 启动失败: $e');
      print('❌ [DeviceDiscovery] 启动异常堆栈: $stack');
    }
  }

  /// 停止服务发现
  Future<void> stopDiscovery() async {
    print('🛑 [DeviceDiscovery] 停止发现设备');

    // 先取消定时器，避免并发修改
    _broadcastTimer?.cancel();
    _broadcastTimer = null;

    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    // 关闭Socket
    _socket?.close();
    _socket = null;

    // 清空设备列表（创建新Map避免并发修改异常）
    final oldDevices = _discoveredDevices;
    _discoveredDevices.clear();

    // 通知变化
    _notifyDevicesChanged();

    print('✅ [DeviceDiscovery] 设备发现已停止，清理了 ${oldDevices.length} 台设备');
  }

  /// 更新同步端口（当服务器使用备用端口时）
  void updateSyncPort(int newPort) {
    if (_syncPort != newPort) {
      print('ℹ️  [DeviceDiscovery] 更新同步端口: $_syncPort -> $newPort');
      _syncPort = newPort;
      // 立即广播更新后的信息
      _broadcastService();
    }
  }

  /// 开始广播自己的服务
  void _startBroadcasting() {
    // 每 3 秒广播一次
    _broadcastTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _broadcastService();
    });

    // 立即广播一次
    _broadcastService();
  }

  /// 广播服务
  Future<void> _broadcastService() async {
    if (_socket == null) {
      print('⚠️ [DeviceDiscovery] Socket未初始化,无法广播');
      return;
    }

    try {
      // 获取本机IP地址
      String? localIp = await _getLocalIpAddress();
      if (localIp == null) {
        print('⚠️ [DeviceDiscovery] 无法获取本机IP地址');
        return;
      }

      // 构建广播消息
      final message = {
        'type': 'device_announcement',
        'deviceId': _currentDeviceId,
        'deviceName': _currentDeviceName,
        'ipAddress': localIp,
        'port': _syncPort,
        'timestamp': DateTime.now().toIso8601String(),
      };

      final jsonString = jsonEncode(message);
      final data = utf8.encode(jsonString);
      final address = InternetAddress(broadcastAddress);

      final bytesSent = _socket!.send(data, address, broadcastPort);
      print(
          '📡 [DeviceDiscovery] 广播设备信息: $_currentDeviceName ($localIp:$_syncPort) - 发送 $bytesSent bytes');
      print('📤 [DeviceDiscovery] 广播内容: $jsonString');
    } catch (e, stack) {
      print('❌ [DeviceDiscovery] 广播失败: $e');
      print('❌ [DeviceDiscovery] 广播异常堆栈: $stack');
    }
  }

  /// 获取本机IP地址
  Future<String?> _getLocalIpAddress() async {
    try {
      print('🔍 [DeviceDiscovery] 查找本机IP地址...');
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      print('📋 [DeviceDiscovery] 发现 ${interfaces.length} 个网络接口');

      String? fallbackIp;
      String? wifiIp;

      for (var interface in interfaces) {
        print('   接口: ${interface.name}');
        for (var addr in interface.addresses) {
          print('      地址: ${addr.address} (回环: ${addr.isLoopback})');

          // 排除回环地址
          if (addr.isLoopback) {
            continue;
          }

          final ip = addr.address;

          // 优先选择192.168.x.x或10.x.x.x网段的IP（通常是WiFi）
          if (ip.startsWith('192.168.') || ip.startsWith('10.')) {
            wifiIp = ip;
            print('      ✅ WiFi地址，优先选择');
            break;
          }

          // 排除虚拟网卡（常见前缀）
          if (ip.startsWith('172.') &&
              (interface.name.toLowerCase().contains('hyper-v') ||
                  interface.name.toLowerCase().contains('wsl') ||
                  interface.name.toLowerCase().contains('vethernet') ||
                  interface.name.toLowerCase().contains('virtualbox') ||
                  interface.name.toLowerCase().contains('vmware'))) {
            print('      ⚠️  虚拟网卡，跳过');
            continue;
          }

          // 作为备选
          if (fallbackIp == null) {
            fallbackIp = ip;
            print('      📝 备选地址');
          }
        }

        // 如果找到WiFi地址，立即使用
        if (wifiIp != null) {
          break;
        }
      }

      final selectedIp = wifiIp ?? fallbackIp;

      if (selectedIp != null) {
        print('✅ [DeviceDiscovery] 使用IP地址: $selectedIp');
        return selectedIp;
      }

      print('⚠️ [DeviceDiscovery] 未找到可用的非回环IP地址');
    } catch (e, stack) {
      print('❌ [DeviceDiscovery] 获取IP失败: $e');
      print('❌ [DeviceDiscovery] 堆栈: $stack');
    }
    return null;
  }

  /// 开始监听其他设备
  void _startListening() {
    if (_socket == null) return;

    _socket!.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = _socket!.receive();
        if (datagram != null) {
          print(
              '📥 [DeviceDiscovery] 收到UDP消息 from ${datagram.address.address}:${datagram.port}, 大小: ${datagram.data.length} bytes');
          _handleIncomingMessage(datagram);
        }
      }
    });

    print('👂 [DeviceDiscovery] 开始监听UDP广播消息 (端口 $broadcastPort)');
  }

  /// 处理接收到的UDP消息
  void _handleIncomingMessage(Datagram datagram) {
    try {
      final rawData = utf8.decode(datagram.data);
      print('📋 [DeviceDiscovery] 原始消息: $rawData');

      final message = jsonDecode(rawData) as Map<String, dynamic>;
      print('📦 [DeviceDiscovery] 解析消息: $message');

      // 验证消息类型
      if (message['type'] != 'device_announcement') {
        print('⚠️ [DeviceDiscovery] 未知消息类型: ${message['type']}');
        return;
      }

      final deviceId = message['deviceId'] as String?;
      final deviceName = message['deviceName'] as String?;
      final ipAddress = message['ipAddress'] as String?;
      final port = message['port'] as int?;
      final timestamp = message['timestamp'] as String?;

      print(
          '🔍 [DeviceDiscovery] 提取字段 - ID: $deviceId, Name: $deviceName, IP: $ipAddress, Port: $port, Time: $timestamp');

      if (deviceId == null ||
          deviceName == null ||
          ipAddress == null ||
          port == null) {
        print('⚠️ [DeviceDiscovery] 消息格式不完整 - 缺少必需字段');
        print('   deviceId: ${deviceId != null ? "✓" : "✗"}');
        print('   deviceName: ${deviceName != null ? "✓" : "✗"}');
        print('   ipAddress: ${ipAddress != null ? "✓" : "✗"}');
        print('   port: ${port != null ? "✓" : "✗"}');
        return;
      }

      // 不添加自己
      if (deviceId == _currentDeviceId) {
        print('🔄 [DeviceDiscovery] 忽略本机设备: $deviceName');
        return;
      }

      // 检查是否是新设备或更新
      final isNewDevice = !_discoveredDevices.containsKey(deviceId);

      // 添加或更新设备
      final deviceInfo = DeviceInfo(
        deviceId: deviceId,
        deviceName: deviceName,
        ipAddress: ipAddress,
        port: port,
        lastSeen: DateTime.now(),
        isConnected: false,
      );

      _discoveredDevices[deviceId] = deviceInfo;

      if (isNewDevice) {
        print('✨ [DeviceDiscovery] 发现新设备: $deviceName ($ipAddress:$port)');
        print('   - deviceId: $deviceId');
        print('   - ipAddress 长度: ${ipAddress.length}');
        print('   - 完整对象: ${deviceInfo.toJson()}');
      } else {
        print('🔄 [DeviceDiscovery] 更新设备信息: $deviceName ($ipAddress:$port)');
      }

      print('📊 [DeviceDiscovery] 当前设备列表数量: ${_discoveredDevices.length}');
      _notifyDevicesChanged();
    } catch (e, stack) {
      print('❌ [DeviceDiscovery] 处理消息失败: $e');
      print('❌ [DeviceDiscovery] 堆栈: $stack');
      print('❌ [DeviceDiscovery] 原始数据: ${datagram.data}');
    }
  }

  /// 开始定期清理过期设备
  void _startCleanup() {
    // 每 30 秒清理一次
    _cleanupTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _cleanupStaleDevices();
    });
  }

  /// 清理过期设备 (超过 60 秒未见)
  void _cleanupStaleDevices() {
    // 检查定时器是否已取消
    if (_cleanupTimer == null || !_cleanupTimer!.isActive) {
      print('⚠️  [DeviceDiscovery] 清理定时器已停止，跳过清理');
      return;
    }

    final now = DateTime.now();
    final staleDeviceIds = <String>[];

    // 先收集需要删除的设备ID
    try {
      for (final entry in _discoveredDevices.entries) {
        final device = entry.value;
        final age = now.difference(device.lastSeen).inSeconds;

        if (age > 60) {
          staleDeviceIds.add(entry.key);
          print(
              '🗑️  [DeviceDiscovery] 标记过期设备: ${device.deviceName} (${age}秒未响应)');
        }
      }

      // 批量删除
      if (staleDeviceIds.isNotEmpty) {
        for (final deviceId in staleDeviceIds) {
          _discoveredDevices.remove(deviceId);
        }
        print('🧹 [DeviceDiscovery] 清理了 ${staleDeviceIds.length} 台过期设备');
        _notifyDevicesChanged();
      }
    } catch (e, stack) {
      print('❌ [DeviceDiscovery] 清理设备时出错: $e');
      print('❌ [DeviceDiscovery] 堆栈: $stack');
    }
  }

  /// 通知设备列表变化
  void _notifyDevicesChanged() {
    if (!_devicesController.isClosed) {
      // 创建列表副本，避免并发修改
      final deviceList = _discoveredDevices.values.toList();
      _devicesController.add(deviceList);
    }
  }

  /// 更新设备连接状态
  void updateDeviceConnectionStatus(String deviceId, bool isConnected) {
    final device = _discoveredDevices[deviceId];
    if (device != null) {
      _discoveredDevices[deviceId] =
          device.copyWith(isConnected: isConnected, lastSeen: DateTime.now());
      _notifyDevicesChanged();
    }
  }

  /// 手动添加设备 (用于直接 IP 连接)
  void addManualDevice(String ipAddress, int port, String deviceName) {
    try {
      final deviceId = '$ipAddress-$deviceName';

      _discoveredDevices[deviceId] = DeviceInfo(
        deviceId: deviceId,
        deviceName: deviceName,
        ipAddress: ipAddress,
        port: port,
        lastSeen: DateTime.now(),
        isConnected: false,
      );

      _notifyDevicesChanged();
      print('➕ [DeviceDiscovery] 手动添加设备: $deviceName ($ipAddress:$port)');
    } catch (e) {
      print('❌ [DeviceDiscovery] 添加设备失败: $e');
    }
  }

  /// 移除设备
  void removeDevice(String deviceId) {
    try {
      final device = _discoveredDevices.remove(deviceId);
      if (device != null) {
        _notifyDevicesChanged();
        print('➖ [DeviceDiscovery] 移除设备: ${device.deviceName}');
      }
    } catch (e) {
      print('❌ [DeviceDiscovery] 移除设备失败: $e');
    }
  }

  /// 释放资源
  void dispose() {
    print('🗑️  [DeviceDiscovery] 释放资源');
    stopDiscovery();
    _devicesController.close();
  }
}
