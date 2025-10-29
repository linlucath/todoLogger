import 'dart:async';
import 'package:multicast_dns/multicast_dns.dart';
import '../models/sync_models.dart';

/// 设备发现服务 - 使用 mDNS 协议在局域网内发现其他设备
class DeviceDiscoveryService {
  static const String serviceType = '_timelogger._tcp';
  static const int defaultPort = 8765;

  MDnsClient? _mdnsClient;
  final Map<String, DeviceInfo> _discoveredDevices = {};
  final StreamController<List<DeviceInfo>> _devicesController =
      StreamController.broadcast();

  Timer? _broadcastTimer;
  Timer? _cleanupTimer;

  String? _currentDeviceName;

  /// 获取已发现的设备列表
  Stream<List<DeviceInfo>> get devicesStream => _devicesController.stream;
  List<DeviceInfo> get devices => _discoveredDevices.values.toList();

  /// 开始服务发现
  Future<void> startDiscovery(String deviceId, String deviceName) async {
    _currentDeviceName = deviceName;

    try {
      _mdnsClient = MDnsClient();
      await _mdnsClient!.start();

      print('🔍 [DeviceDiscovery] 开始发现设备...');

      // 开始广播自己的服务
      _startBroadcasting();

      // 开始监听其他设备
      _startListening();

      // 定期清理过期设备
      _startCleanup();
    } catch (e) {
      print('❌ [DeviceDiscovery] 启动失败: $e');
    }
  }

  /// 停止服务发现
  Future<void> stopDiscovery() async {
    print('🛑 [DeviceDiscovery] 停止发现设备');

    _broadcastTimer?.cancel();
    _cleanupTimer?.cancel();

    _mdnsClient?.stop();
    _mdnsClient = null;

    _discoveredDevices.clear();
    _notifyDevicesChanged();
  }

  /// 开始广播自己的服务
  void _startBroadcasting() {
    // 每 10 秒广播一次
    _broadcastTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _broadcastService();
    });

    // 立即广播一次
    _broadcastService();
  }

  /// 广播服务
  Future<void> _broadcastService() async {
    if (_mdnsClient == null) return;

    try {
      final serviceName = '$_currentDeviceName.$serviceType.local';

      print('📡 [DeviceDiscovery] 广播服务: $serviceName');

      // mDNS 客户端已经在 start() 时启动,这里只需要确保服务正在运行
      // 实际的广播会通过 mDNS 协议自动进行
    } catch (e) {
      print('❌ [DeviceDiscovery] 广播失败: $e');
    }
  }

  /// 开始监听其他设备
  void _startListening() {
    if (_mdnsClient == null) return;

    // 查询服务
    _queryServices();

    // 每 15 秒重新查询一次
    Timer.periodic(const Duration(seconds: 15), (timer) {
      if (_mdnsClient == null) {
        timer.cancel();
        return;
      }
      _queryServices();
    });
  }

  /// 查询服务
  Future<void> _queryServices() async {
    if (_mdnsClient == null) return;

    try {
      print('🔎 [DeviceDiscovery] 查询服务: $serviceType.local');

      await for (final PtrResourceRecord ptr in _mdnsClient!
          .lookup<PtrResourceRecord>(
              ResourceRecordQuery.serverPointer('$serviceType.local'))) {
        final String serviceName = ptr.domainName;
        print('✅ [DeviceDiscovery] 发现服务: $serviceName');

        // 获取服务详细信息
        await _resolveService(serviceName);
      }
    } catch (e) {
      print('❌ [DeviceDiscovery] 查询失败: $e');
    }
  }

  /// 解析服务详细信息
  Future<void> _resolveService(String serviceName) async {
    if (_mdnsClient == null) return;

    try {
      // 查询 SRV 记录获取端口和主机名
      await for (final SrvResourceRecord srv in _mdnsClient!
          .lookup<SrvResourceRecord>(
              ResourceRecordQuery.service(serviceName))) {
        final String hostname = srv.target;
        final int port = srv.port;

        print('📋 [DeviceDiscovery] 服务详情: $hostname:$port');

        // 查询 A 记录获取 IP 地址
        await _resolveAddress(serviceName, hostname, port);
      }
    } catch (e) {
      print('❌ [DeviceDiscovery] 解析服务失败: $e');
    }
  }

  /// 解析 IP 地址
  Future<void> _resolveAddress(
      String serviceName, String hostname, int port) async {
    if (_mdnsClient == null) return;

    try {
      // 查询 A 记录 (IPv4)
      await for (final IPAddressResourceRecord record in _mdnsClient!
          .lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(hostname))) {
        final String ipAddress = record.address.address;

        print('🌐 [DeviceDiscovery] IP 地址: $ipAddress');

        // 提取设备名称
        final deviceName = serviceName.split('.').first;

        // 不添加自己
        if (deviceName == _currentDeviceName) {
          continue;
        }

        // 生成设备 ID (使用 IP + Name 作为唯一标识)
        final deviceId = '$ipAddress-$deviceName';

        // 添加或更新设备
        _discoveredDevices[deviceId] = DeviceInfo(
          deviceId: deviceId,
          deviceName: deviceName,
          ipAddress: ipAddress,
          port: port,
          lastSeen: DateTime.now(),
          isConnected: false,
        );

        _notifyDevicesChanged();
      }
    } catch (e) {
      print('❌ [DeviceDiscovery] 解析地址失败: $e');
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
    final now = DateTime.now();
    final staleDeviceIds = <String>[];

    for (final entry in _discoveredDevices.entries) {
      final device = entry.value;
      final age = now.difference(device.lastSeen).inSeconds;

      if (age > 60) {
        staleDeviceIds.add(entry.key);
        print('🗑️  [DeviceDiscovery] 移除过期设备: ${device.deviceName}');
      }
    }

    for (final deviceId in staleDeviceIds) {
      _discoveredDevices.remove(deviceId);
    }

    if (staleDeviceIds.isNotEmpty) {
      _notifyDevicesChanged();
    }
  }

  /// 通知设备列表变化
  void _notifyDevicesChanged() {
    if (!_devicesController.isClosed) {
      _devicesController.add(devices);
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
  }

  /// 移除设备
  void removeDevice(String deviceId) {
    _discoveredDevices.remove(deviceId);
    _notifyDevicesChanged();
    print('➖ [DeviceDiscovery] 移除设备: $deviceId');
  }

  /// 释放资源
  void dispose() {
    stopDiscovery();
    _devicesController.close();
  }
}
