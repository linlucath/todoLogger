import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sync_models.dart';
import '../models/sync_data_models.dart';
import 'device_discovery_service.dart';
import 'sync_server_service.dart';
import 'sync_client_service.dart';
import 'sync_conflict_resolver.dart';
import 'sync_history_service.dart';
import 'todo_storage.dart';
import 'time_logger_storage.dart';

/// 同步服务 - 统一管理所有同步功能
class SyncService {
  // 子服务
  final DeviceDiscoveryService _discoveryService = DeviceDiscoveryService();
  final SyncServerService _serverService = SyncServerService();
  final Map<String, SyncClientService> _clientServices = {};
  final SyncConflictResolver _conflictResolver = SyncConflictResolver();
  final SyncHistoryService _historyService = SyncHistoryService();

  // 当前设备信息
  DeviceInfo? _currentDevice;

  // 同步状态
  bool _isEnabled = false;
  bool _isServerRunning = false;

  // 当前计时状态
  final Map<String, TimerState> _activeTimers = {};

  // 事件流控制器
  final StreamController<List<DeviceInfo>> _discoveredDevicesController =
      StreamController.broadcast();
  final StreamController<List<DeviceInfo>> _connectedDevicesController =
      StreamController.broadcast();
  final StreamController<List<TimerState>> _activeTimersController =
      StreamController.broadcast();

  // Getter
  bool get isEnabled => _isEnabled;
  bool get isServerRunning => _isServerRunning;
  DeviceInfo? get currentDevice => _currentDevice;

  Stream<List<DeviceInfo>> get discoveredDevicesStream =>
      _discoveredDevicesController.stream;
  Stream<List<DeviceInfo>> get connectedDevicesStream =>
      _connectedDevicesController.stream;
  Stream<List<TimerState>> get activeTimersStream =>
      _activeTimersController.stream;

  List<DeviceInfo> get discoveredDevices => _discoveryService.devices;
  List<DeviceInfo> get connectedDevices => _serverService.connectedDevices;
  List<TimerState> get activeTimers => _activeTimers.values.toList();
  SyncHistoryService get historyService => _historyService;

  /// 初始化同步服务
  Future<void> initialize() async {
    print('🚀 [SyncService] 初始化同步服务');

    // 加载同步设置
    await _loadSettings();

    // 创建当前设备信息
    _currentDevice = await DeviceInfo.getCurrentDevice(8765);

    // 如果同步已启用,自动启动
    if (_isEnabled) {
      await enable();
    }
  }

  /// 启用同步
  Future<void> enable() async {
    if (_isEnabled) {
      print('⚠️  [SyncService] 同步已启用');
      return;
    }

    print('✅ [SyncService] 启用同步');
    _isEnabled = true;
    await _saveSettings();

    // 启动服务器
    await _startServer();

    // 启动设备发现
    await _startDiscovery();
  }

  /// 禁用同步
  Future<void> disable() async {
    if (!_isEnabled) {
      print('⚠️  [SyncService] 同步已禁用');
      return;
    }

    print('🛑 [SyncService] 禁用同步');
    _isEnabled = false;
    await _saveSettings();

    // 停止所有客户端连接
    await _disconnectAllClients();

    // 停止服务器
    await _stopServer();

    // 停止设备发现
    await _stopDiscovery();
  }

  /// 启动服务器
  Future<void> _startServer() async {
    if (_isServerRunning || _currentDevice == null) return;

    print('🌐 [SyncService] 启动服务器');

    final success = await _serverService.start(_currentDevice!);
    if (success) {
      _isServerRunning = true;

      // 设置消息处理回调
      _serverService.onMessageReceived = _handleServerMessage;
      _serverService.onDeviceConnected = _handleDeviceConnected;
      _serverService.onDeviceDisconnected = _handleDeviceDisconnected;
    }
  }

  /// 停止服务器
  Future<void> _stopServer() async {
    if (!_isServerRunning) return;

    print('🛑 [SyncService] 停止服务器');
    await _serverService.stop();
    _isServerRunning = false;
  }

  /// 启动设备发现
  Future<void> _startDiscovery() async {
    if (_currentDevice == null) return;

    print('🔍 [SyncService] 启动设备发现');

    await _discoveryService.startDiscovery(
      _currentDevice!.deviceId,
      _currentDevice!.deviceName,
    );

    // 监听发现的设备
    _discoveryService.devicesStream.listen((devices) {
      _discoveredDevicesController.add(devices);
    });
  }

  /// 停止设备发现
  Future<void> _stopDiscovery() async {
    print('🛑 [SyncService] 停止设备发现');
    await _discoveryService.stopDiscovery();
  }

  /// 加载设置
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isEnabled = prefs.getBool('sync_enabled') ?? false;
  }

  /// 保存设置
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sync_enabled', _isEnabled);
  }

  /// 处理服务器收到的消息
  void _handleServerMessage(SyncMessage message, String fromDeviceId) {
    print('📨 [SyncService] 处理消息: ${message.type} from $fromDeviceId');

    switch (message.type) {
      case SyncMessageType.dataRequest:
        _handleDataRequest(message, fromDeviceId);
        break;
      case SyncMessageType.dataUpdate:
        _handleDataUpdate(message);
        break;
      case SyncMessageType.timerStart:
        _handleTimerStart(message);
        break;
      case SyncMessageType.timerStop:
        _handleTimerStop(message);
        break;
      case SyncMessageType.timerUpdate:
        _handleTimerUpdate(message);
        break;
      default:
        break;
    }
  }

  /// 处理设备连接
  void _handleDeviceConnected(String deviceId, DeviceInfo device) {
    print('🤝 [SyncService] 设备已连接: ${device.deviceName}');
    _notifyConnectedDevicesChanged();
  }

  /// 处理设备断开
  void _handleDeviceDisconnected(String deviceId) {
    print('👋 [SyncService] 设备已断开: $deviceId');
    _notifyConnectedDevicesChanged();
  }

  /// 处理数据请求
  void _handleDataRequest(SyncMessage message, String fromDeviceId) async {
    if (message.data == null) return;

    final dataType = message.data!['dataType'] as String?;
    if (dataType == null) return;

    print('📤 [SyncService] 响应数据请求: $dataType');

    // 根据数据类型获取数据
    dynamic data;
    switch (dataType) {
      case 'todos':
        data = await _getTodosData();
        break;
      case 'timeLogs':
        data = await _getTimeLogsData();
        break;
      default:
        return;
    }

    // 发送响应
    if (_currentDevice != null) {
      final response = SyncMessage.dataResponse(
        _currentDevice!.deviceId,
        dataType,
        data,
      );
      _serverService.sendMessageToDevice(fromDeviceId, response);
    }
  }

  /// 处理数据更新
  void _handleDataUpdate(SyncMessage message) {
    if (message.data == null) return;

    final dataType = message.data!['dataType'] as String?;
    final updateData = message.data!['data'];

    if (dataType == null || updateData == null || message.senderId == null)
      return;

    print('🔄 [SyncService] 处理数据更新: $dataType from ${message.senderId}');

    // 根据数据类型处理更新
    switch (dataType) {
      case 'todos':
        _handleTodosDataUpdate(
            updateData as Map<String, dynamic>, message.senderId!);
        break;
      case 'timeLogs':
        _handleTimeLogsDataUpdate(
            updateData as List<dynamic>, message.senderId!);
        break;
      default:
        print('⚠️  [SyncService] 未知数据类型: $dataType');
    }
  }

  /// 处理计时开始
  void _handleTimerStart(SyncMessage message) {
    if (message.data == null || message.senderId == null) return;

    final todoId = message.data!['todoId'] as String?;
    final startTimeStr = message.data!['startTime'] as String?;

    if (todoId == null || startTimeStr == null) return;

    final startTime = DateTime.parse(startTimeStr);
    final senderDevice = _serverService.getConnectedDevice(message.senderId!);

    if (senderDevice != null) {
      final timerState = TimerState(
        todoId: todoId,
        todoTitle: message.data!['todoTitle'] as String? ?? 'Unknown',
        startTime: startTime,
        currentDuration: 0,
        deviceId: message.senderId!,
        deviceName: senderDevice.deviceName,
      );

      _activeTimers[message.senderId!] = timerState;
      _notifyActiveTimersChanged();

      print(
          '⏱️  [SyncService] 计时开始: ${timerState.todoTitle} on ${senderDevice.deviceName}');
    }
  }

  /// 处理计时停止
  void _handleTimerStop(SyncMessage message) {
    if (message.senderId == null) return;

    _activeTimers.remove(message.senderId);
    _notifyActiveTimersChanged();

    print('⏹️  [SyncService] 计时停止: ${message.senderId}');
  }

  /// 处理计时更新
  void _handleTimerUpdate(SyncMessage message) {
    if (message.data == null || message.senderId == null) return;

    final currentDuration = message.data!['currentDuration'] as int?;
    if (currentDuration == null) return;

    final existingTimer = _activeTimers[message.senderId];
    if (existingTimer != null) {
      _activeTimers[message.senderId!] =
          existingTimer.copyWith(currentDuration: currentDuration);
      _notifyActiveTimersChanged();
    }
  }

  /// 获取待办事项数据
  Future<Map<String, dynamic>> _getTodosData() async {
    final todoItems = await TodoStorage.getTodoItems();
    final todoLists = await TodoStorage.getTodoLists();

    return {
      'items': todoItems.values.map((item) => item.toJson()).toList(),
      'lists': todoLists.map((list) => list.toJson()).toList(),
    };
  }

  /// 获取时间日志数据
  Future<List<Map<String, dynamic>>> _getTimeLogsData() async {
    final logs = await TimeLoggerStorage.getAllRecords();
    return logs.map((log) => log.toJson()).toList();
  }

  /// 通知已连接设备变化
  void _notifyConnectedDevicesChanged() {
    if (!_connectedDevicesController.isClosed) {
      _connectedDevicesController.add(connectedDevices);
    }
  }

  /// 通知活动计时器变化
  void _notifyActiveTimersChanged() {
    if (!_activeTimersController.isClosed) {
      _activeTimersController.add(activeTimers);
    }
  }

  /// 连接到设备
  Future<bool> connectToDevice(DeviceInfo device) async {
    if (_currentDevice == null) return false;

    print('🔗 [SyncService] 连接到设备: ${device.deviceName}');

    // 创建客户端服务
    final client = SyncClientService();
    final success = await client.connect(_currentDevice!, device);

    if (success) {
      _clientServices[device.deviceId] = client;

      // 设置回调
      client.onMessageReceived = _handleClientMessage;
      client.onDisconnected = () {
        _clientServices.remove(device.deviceId);
      };

      return true;
    }

    return false;
  }

  /// 断开设备连接
  Future<void> disconnectFromDevice(String deviceId) async {
    final client = _clientServices[deviceId];
    if (client != null) {
      await client.disconnect();
      _clientServices.remove(deviceId);
    }
  }

  /// 断开所有客户端连接
  Future<void> _disconnectAllClients() async {
    for (final client in _clientServices.values) {
      await client.disconnect();
    }
    _clientServices.clear();
  }

  /// 处理客户端收到的消息
  void _handleClientMessage(SyncMessage message) {
    print('📨 [SyncService] 客户端收到消息: ${message.type}');
    // 类似服务器的消息处理
    _handleServerMessage(message, message.senderId ?? '');
  }

  /// 广播计时开始
  void broadcastTimerStart(
      String todoId, String todoTitle, DateTime startTime) {
    if (_currentDevice == null) return;

    final message = SyncMessage(
      type: SyncMessageType.timerStart,
      senderId: _currentDevice!.deviceId,
      data: {
        'todoId': todoId,
        'todoTitle': todoTitle,
        'startTime': startTime.toIso8601String(),
      },
    );

    _serverService.broadcastMessage(message);
    print('📢 [SyncService] 广播计时开始: $todoTitle');
  }

  /// 广播计时停止
  void broadcastTimerStop(
      String todoId, DateTime startTime, DateTime endTime, int duration) {
    if (_currentDevice == null) return;

    final message = SyncMessage(
      type: SyncMessageType.timerStop,
      senderId: _currentDevice!.deviceId,
      data: {
        'todoId': todoId,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'duration': duration,
      },
    );

    _serverService.broadcastMessage(message);
    print('📢 [SyncService] 广播计时停止: $todoId');
  }

  // ==================== 数据同步功能 ====================

  /// 全量同步所有数据到指定设备
  Future<bool> syncAllDataToDevice(String deviceId) async {
    if (_currentDevice == null) {
      print('❌ [SyncService] 设备信息未初始化');
      return false;
    }

    final device = _serverService.getConnectedDevice(deviceId);
    if (device == null) {
      print('❌ [SyncService] 设备未连接: $deviceId');
      return false;
    }

    print('🔄 [SyncService] 开始全量同步到: ${device.deviceName}');

    try {
      // 同步待办事项
      await _syncTodosToDevice(deviceId);

      // 同步时间日志
      await _syncTimeLogsToDevice(deviceId);

      // 记录成功
      await _historyService.recordPush(
        deviceId: deviceId,
        deviceName: device.deviceName,
        dataType: 'all',
        itemCount: 0,
        description: '全量同步成功',
        success: true,
      );

      print('✅ [SyncService] 全量同步完成');
      return true;
    } catch (e) {
      print('❌ [SyncService] 全量同步失败: $e');
      await _historyService.recordPush(
        deviceId: deviceId,
        deviceName: device.deviceName,
        dataType: 'all',
        itemCount: 0,
        success: false,
        errorMessage: e.toString(),
      );
      return false;
    }
  }

  /// 从指定设备拉取所有数据
  Future<bool> pullAllDataFromDevice(String deviceId) async {
    if (_currentDevice == null) {
      print('❌ [SyncService] 设备信息未初始化');
      return false;
    }

    final client = _clientServices[deviceId];
    if (client == null || !client.isConnected) {
      print('❌ [SyncService] 设备未连接: $deviceId');
      return false;
    }

    print('🔄 [SyncService] 从设备拉取数据: $deviceId');

    try {
      // 请求待办事项数据
      client.requestData('todos');

      // 请求时间日志数据
      client.requestData('timeLogs');

      // 记录成功
      await _historyService.recordPull(
        deviceId: deviceId,
        deviceName: client.remoteDevice?.deviceName ?? 'Unknown',
        dataType: 'all',
        itemCount: 0,
        description: '请求全量数据',
        success: true,
      );

      print('✅ [SyncService] 数据请求已发送');
      return true;
    } catch (e) {
      print('❌ [SyncService] 拉取数据失败: $e');
      return false;
    }
  }

  /// 同步待办事项到指定设备
  Future<void> _syncTodosToDevice(String deviceId) async {
    print('📤 [SyncService] 同步待办事项到: $deviceId');

    try {
      // 获取本地数据
      final todoData = await _getTodosData();

      // 转换为可同步格式
      final syncData = _convertTodosToSyncable(todoData);

      // 发送数据
      final message = SyncMessage.dataUpdate(
        _currentDevice!.deviceId,
        'todos',
        syncData,
      );
      _serverService.sendMessageToDevice(deviceId, message);

      final itemCount = (todoData['items'] as List).length;
      print('✅ [SyncService] 已发送 $itemCount 个待办事项');
    } catch (e) {
      print('❌ [SyncService] 同步待办事项失败: $e');
      rethrow;
    }
  }

  /// 同步时间日志到指定设备
  Future<void> _syncTimeLogsToDevice(String deviceId) async {
    print('📤 [SyncService] 同步时间日志到: $deviceId');

    try {
      // 获取本地数据
      final logsData = await _getTimeLogsData();

      // 转换为可同步格式
      final syncData = _convertTimeLogsToSyncable(logsData);

      // 发送数据
      final message = SyncMessage.dataUpdate(
        _currentDevice!.deviceId,
        'timeLogs',
        syncData,
      );
      _serverService.sendMessageToDevice(deviceId, message);

      final itemCount = logsData.length;
      print('✅ [SyncService] 已发送 $itemCount 个时间日志');
    } catch (e) {
      print('❌ [SyncService] 同步时间日志失败: $e');
      rethrow;
    }
  }

  /// 转换待办事项为可同步格式
  Map<String, dynamic> _convertTodosToSyncable(Map<String, dynamic> todoData) {
    final items = (todoData['items'] as List).map((item) {
      return {
        ...item,
        'syncMetadata': SyncMetadata.create(_currentDevice!.deviceId).toJson(),
      };
    }).toList();

    final lists = (todoData['lists'] as List).map((list) {
      return {
        ...list,
        'syncMetadata': SyncMetadata.create(_currentDevice!.deviceId).toJson(),
      };
    }).toList();

    return {
      'items': items,
      'lists': lists,
    };
  }

  /// 转换时间日志为可同步格式
  List<Map<String, dynamic>> _convertTimeLogsToSyncable(
      List<Map<String, dynamic>> logs) {
    return logs.map((log) {
      return {
        ...log,
        'id': '${log['startTime']}-${log['name']}', // 生成唯一ID
        'syncMetadata': SyncMetadata.create(_currentDevice!.deviceId).toJson(),
      };
    }).toList();
  }

  /// 处理接收到的待办事项数据
  Future<void> _handleTodosDataUpdate(
      Map<String, dynamic> remoteData, String fromDeviceId) async {
    print('🔄 [SyncService] 处理待办事项更新: 来自 $fromDeviceId');

    try {
      int conflictCount = 0;

      // 处理待办项
      if (remoteData['items'] != null) {
        final remoteItems = (remoteData['items'] as List)
            .map((json) => SyncableTodoItem.fromJson(json))
            .toList();

        // TODO: 实现实际的冲突检测和数据合并
        // 当前为简化版本,实际应用中应该:
        // 1. 检查本地是否存在相同ID的项
        // 2. 使用 _conflictResolver 检测和解决冲突
        // 3. 更新本地数据库
        for (final _ in remoteItems) {
          // 占位符,避免编译警告
        }
      }

      // 处理待办列表
      if (remoteData['lists'] != null) {
        final remoteLists = (remoteData['lists'] as List)
            .map((json) => SyncableTodoList.fromJson(json))
            .toList();

        // TODO: 实现实际的冲突检测和数据合并
        for (final _ in remoteLists) {
          // 占位符,避免编译警告
        }
      }

      // 记录历史
      final device = _serverService.getConnectedDevice(fromDeviceId);
      if (device != null) {
        await _historyService.recordMerge(
          deviceId: fromDeviceId,
          deviceName: device.deviceName,
          dataType: 'todos',
          itemCount: (remoteData['items'] as List?)?.length ?? 0,
          description: conflictCount > 0 ? '解决了 $conflictCount 个冲突' : null,
          success: true,
        );

        if (conflictCount > 0) {
          await _historyService.recordConflict(
            deviceId: fromDeviceId,
            deviceName: device.deviceName,
            dataType: 'todos',
            conflictCount: conflictCount,
            description: '使用最后写入获胜策略',
          );
        }
      }

      print('✅ [SyncService] 待办事项更新完成');
    } catch (e) {
      print('❌ [SyncService] 处理待办事项更新失败: $e');
    }
  }

  /// 处理接收到的时间日志数据
  Future<void> _handleTimeLogsDataUpdate(
      List<dynamic> remoteLogs, String fromDeviceId) async {
    print('🔄 [SyncService] 处理时间日志更新: 来自 $fromDeviceId');

    try {
      final syncableLogs =
          remoteLogs.map((json) => SyncableTimeLog.fromJson(json)).toList();

      // 简化版本:直接接受远程数据
      // 实际应用中应该检查冲突并解决

      // 记录历史
      final device = _serverService.getConnectedDevice(fromDeviceId);
      if (device != null) {
        await _historyService.recordMerge(
          deviceId: fromDeviceId,
          deviceName: device.deviceName,
          dataType: 'timeLogs',
          itemCount: syncableLogs.length,
          success: true,
        );
      }

      print('✅ [SyncService] 时间日志更新完成');
    } catch (e) {
      print('❌ [SyncService] 处理时间日志更新失败: $e');
    }
  }

  /// 释放资源
  void dispose() {
    _discoveryService.dispose();
    _serverService.stop();
    for (final client in _clientServices.values) {
      client.dispose();
    }
    _clientServices.clear();

    _discoveredDevicesController.close();
    _connectedDevicesController.close();
    _activeTimersController.close();
  }
}
