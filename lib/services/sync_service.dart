import 'dart:async';
import 'package:flutter/material.dart';
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
import '../pages/target/target_storage.dart';
import '../pages/target/models.dart';

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

  // 已连接设备管理（包括主动连接和被动连接）
  final Map<String, DeviceInfo> _connectedDevicesMap = {};

  // 当前计时状态
  final Map<String, TimerState> _activeTimers = {};

  // 事件流控制器
  final StreamController<List<DeviceInfo>> _discoveredDevicesController =
      StreamController.broadcast();
  final StreamController<List<DeviceInfo>> _connectedDevicesController =
      StreamController.broadcast();
  final StreamController<List<TimerState>> _activeTimersController =
      StreamController.broadcast();
  final StreamController<SyncDataUpdatedEvent> _dataUpdatedController =
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
  Stream<SyncDataUpdatedEvent> get dataUpdatedStream =>
      _dataUpdatedController.stream;

  List<DeviceInfo> get discoveredDevices => _discoveryService.devices;
  List<DeviceInfo> get connectedDevices => _connectedDevicesMap.values.toList();
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

    // 清空已连接设备列表
    _connectedDevicesMap.clear();
    _notifyConnectedDevicesChanged();
  }

  /// 启动服务器
  Future<void> _startServer() async {
    if (_isServerRunning || _currentDevice == null) return;

    print('🌐 [SyncService] 启动服务器');

    final success = await _serverService.start(_currentDevice!);
    if (success) {
      _isServerRunning = true;

      // 更新当前设备的实际端口（可能使用了备用端口）
      final actualPort = _serverService.port;
      if (actualPort != _currentDevice!.port) {
        print(
            'ℹ️  [SyncService] 更新设备端口: ${_currentDevice!.port} -> $actualPort');
        _currentDevice = _currentDevice!.copyWith(port: actualPort);

        // 更新设备发现服务的广播端口
        _discoveryService.updateSyncPort(actualPort);
      }

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
      syncPort: _currentDevice!.port,
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
    _connectedDevicesMap[deviceId] = device;
    _notifyConnectedDevicesChanged();
  }

  /// 处理设备断开
  void _handleDeviceDisconnected(String deviceId) {
    print('👋 [SyncService] 设备已断开: $deviceId');
    _connectedDevicesMap.remove(deviceId);
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
      case 'targets':
        data = await _getTargetsData();
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
      _sendMessageToDevice(fromDeviceId, response);
    }
  }

  /// 处理数据更新
  void _handleDataUpdate(SyncMessage message) {
    if (message.data == null) return;

    final dataType = message.data!['dataType'] as String?;
    final updateData = message.data!['data'];

    if (dataType == null || updateData == null || message.senderId == null) {
      return;
    }

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
      case 'targets':
        _handleTargetsDataUpdate(
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
    final syncMetadata = await TodoStorage.getSyncMetadata();

    // 将 TodoItemData 转换为 SyncableTodoItem
    final syncableItems = todoItems.entries.map((entry) {
      final itemId = entry.key;
      final item = entry.value;

      // 获取或创建同步元数据
      final metadata = syncMetadata[itemId] ??
          SyncMetadata.create(_currentDevice?.deviceId ?? 'unknown');

      return SyncableTodoItem(
        id: item.id,
        title: item.title,
        description: item.description,
        isCompleted: item.isCompleted,
        createdAt: item.createdAt,
        listId: item.listId,
        syncMetadata: metadata,
      );
    }).toList();

    // 将 TodoListData 转换为 SyncableTodoList
    final syncableLists = todoLists.map((list) {
      // 列表使用 list_ 前缀的ID来存储元数据
      final listMetadataId = 'list_${list.id}';
      final metadata = syncMetadata[listMetadataId] ??
          SyncMetadata.create(_currentDevice?.deviceId ?? 'unknown');

      return SyncableTodoList(
        id: list.id,
        name: list.name,
        isExpanded: list.isExpanded,
        colorValue: list.colorValue,
        itemIds: list.itemIds,
        syncMetadata: metadata,
      );
    }).toList();

    return {
      'items': syncableItems.map((item) => item.toJson()).toList(),
      'lists': syncableLists.map((list) => list.toJson()).toList(),
    };
  }

  /// 获取时间日志数据
  Future<List<Map<String, dynamic>>> _getTimeLogsData() async {
    final logs = await TimeLoggerStorage.getAllRecords();

    // 将 ActivityRecordData 转换为 SyncableTimeLog
    final syncableLogs = logs.map((log) {
      // 使用 startTime 的毫秒数作为唯一 ID
      final id = log.startTime.millisecondsSinceEpoch.toString();

      // 创建简单的同步元数据（时间日志使用简单的时间戳策略）
      final metadata = SyncMetadata(
        lastModifiedAt: log.endTime ?? log.startTime,
        lastModifiedBy: _currentDevice?.deviceId ?? 'unknown',
        version: 1,
        isDeleted: false,
      );

      return SyncableTimeLog(
        id: id,
        name: log.name,
        startTime: log.startTime,
        endTime: log.endTime,
        linkedTodoId: log.linkedTodoId,
        linkedTodoTitle: log.linkedTodoTitle,
        syncMetadata: metadata,
      );
    }).toList();

    return syncableLogs.map((log) => log.toJson()).toList();
  }

  /// 获取目标数据
  Future<List<Map<String, dynamic>>> _getTargetsData() async {
    final storage = TargetStorage();
    final targets = await storage.loadTargets();

    // 将 Target 转换为 SyncableTarget
    final syncableTargets = targets.map((target) {
      // 创建同步元数据
      final metadata = SyncMetadata(
        lastModifiedAt: target.createdAt,
        lastModifiedBy: _currentDevice?.deviceId ?? 'unknown',
        version: 1,
        isDeleted: !target.isActive, // 使用 isActive 标识删除状态
      );

      return SyncableTarget(
        id: target.id,
        name: target.name,
        type: target.type.index,
        period: target.period.index,
        targetSeconds: target.targetSeconds,
        linkedTodoIds: target.linkedTodoIds,
        linkedListIds: target.linkedListIds,
        createdAt: target.createdAt,
        isActive: target.isActive,
        colorValue: target.color.value, // ignore: deprecated_member_use
        syncMetadata: metadata,
      );
    }).toList();

    return syncableTargets.map((target) => target.toJson()).toList();
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

  /// 通知数据已更新
  void _notifyDataUpdated(String dataType, String fromDeviceId, int itemCount) {
    if (!_dataUpdatedController.isClosed) {
      final device = _serverService.getConnectedDevice(fromDeviceId) ??
          _connectedDevicesMap[fromDeviceId];

      final event = SyncDataUpdatedEvent(
        dataType: dataType,
        fromDeviceId: fromDeviceId,
        fromDeviceName: device?.deviceName ?? 'Unknown',
        itemCount: itemCount,
      );

      _dataUpdatedController.add(event);
      print('📢 [SyncService] 数据更新通知已发送: $dataType ($itemCount 项)');
    }
  }

  /// 发送消息到设备（兼容服务器和客户端连接）
  void _sendMessageToDevice(String deviceId, SyncMessage message) {
    // 检查是否是服务器连接（对方连接到我们）
    if (_serverService.getConnectedDevice(deviceId) != null) {
      _serverService.sendMessageToDevice(deviceId, message);
      return;
    }

    // 如果不是服务器连接，尝试通过客户端连接发送（我们连接到对方）
    final client = _clientServices[deviceId];
    if (client != null && client.isConnected) {
      client.sendMessage(message);
      return;
    }

    print('⚠️  [SyncService] 无法发送消息到设备: $deviceId (设备未连接)');
  }

  /// 连接到设备
  Future<bool> connectToDevice(DeviceInfo device) async {
    if (_currentDevice == null) return false;

    print('🔗 [SyncService] 连接到设备: ${device.deviceName}');
    print('🔍 [SyncService] 设备详情: deviceId=${device.deviceId}');
    print(
        '🔍 [SyncService] 设备IP: "${device.ipAddress}" (长度: ${device.ipAddress.length})');
    print('🔍 [SyncService] 设备端口: ${device.port}');

    // 验证IP地址不为空
    if (device.ipAddress.isEmpty) {
      print('❌ [SyncService] IP地址为空，无法连接');
      return false;
    }

    // 创建客户端服务
    final client = SyncClientService();
    final success = await client.connect(_currentDevice!, device);

    if (success) {
      _clientServices[device.deviceId] = client;

      // 将设备添加到已连接设备列表
      _connectedDevicesMap[device.deviceId] = device;
      _notifyConnectedDevicesChanged();

      // 设置回调
      client.onMessageReceived = _handleClientMessage;
      client.onDisconnected = () {
        _clientServices.remove(device.deviceId);
        _connectedDevicesMap.remove(device.deviceId);
        _notifyConnectedDevicesChanged();
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
      _connectedDevicesMap.remove(deviceId);
      _notifyConnectedDevicesChanged();
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

    // 检查设备是否已连接（服务器端连接）
    DeviceInfo? device = _serverService.getConnectedDevice(deviceId);

    // 如果不是服务器端连接，检查是否为客户端连接
    device ??= _connectedDevicesMap[deviceId];

    // 如果设备未连接，尝试自动连接
    if (device == null) {
      print('🔍 [SyncService] 设备未连接，尝试自动连接: $deviceId');

      // 从发现的设备列表中查找
      DeviceInfo? discoveredDevice;
      try {
        discoveredDevice = _discoveryService.devices.firstWhere(
          (d) => d.deviceId == deviceId,
        );
      } catch (e) {
        print('❌ [SyncService] 未找到设备: $deviceId');
        return false;
      }

      // 尝试连接
      print('🔗 [SyncService] 正在连接到设备: ${discoveredDevice.deviceName}');
      final connected = await connectToDevice(discoveredDevice);
      if (!connected) {
        print('❌ [SyncService] 自动连接失败: $deviceId');
        return false;
      }

      device = discoveredDevice;
      print('✅ [SyncService] 自动连接成功');
    }

    print('🔄 [SyncService] 开始全量同步到: ${device.deviceName}');

    try {
      // 同步待办事项
      await _syncTodosToDevice(deviceId);

      // 同步时间日志
      await _syncTimeLogsToDevice(deviceId);

      // 同步目标
      await _syncTargetsToDevice(deviceId);

      // 记录成功
      await _historyService.recordPush(
        deviceId: deviceId,
        deviceName: device.deviceName,
        dataType: 'all',
        itemCount: 0,
        description: '全量同步成功 (包含待办、日志、目标)',
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

    // 检查客户端连接
    SyncClientService? client = _clientServices[deviceId];

    // 如果未连接，尝试自动连接
    if (client == null || !client.isConnected) {
      print('🔍 [SyncService] 设备未连接，尝试自动连接: $deviceId');

      // 从发现的设备列表中查找
      DeviceInfo? discoveredDevice;
      try {
        discoveredDevice = _discoveryService.devices.firstWhere(
          (d) => d.deviceId == deviceId,
        );
      } catch (e) {
        print('❌ [SyncService] 未找到设备: $deviceId');
        return false;
      }

      // 尝试连接
      print('🔗 [SyncService] 正在连接到设备: ${discoveredDevice.deviceName}');
      final connected = await connectToDevice(discoveredDevice);
      if (!connected) {
        print('❌ [SyncService] 自动连接失败: $deviceId');
        return false;
      }

      client = _clientServices[deviceId];
      print('✅ [SyncService] 自动连接成功');
    }

    if (client == null) {
      print('❌ [SyncService] 无法获取客户端连接');
      return false;
    }

    print('🔄 [SyncService] 从设备拉取数据: $deviceId');

    try {
      // 请求待办事项数据
      client.requestData('todos');

      // 请求时间日志数据
      client.requestData('timeLogs');

      // 请求目标数据
      client.requestData('targets');

      // 记录成功
      await _historyService.recordPull(
        deviceId: deviceId,
        deviceName: client.remoteDevice?.deviceName ?? 'Unknown',
        dataType: 'all',
        itemCount: 0,
        description: '请求全量数据 (包含待办、日志、目标)',
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
      _sendMessageToDevice(deviceId, message);

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
      _sendMessageToDevice(deviceId, message);

      final itemCount = logsData.length;
      print('✅ [SyncService] 已发送 $itemCount 个时间日志');
    } catch (e) {
      print('❌ [SyncService] 同步时间日志失败: $e');
      rethrow;
    }
  }

  /// 同步目标到指定设备
  Future<void> _syncTargetsToDevice(String deviceId) async {
    print('📤 [SyncService] 同步目标到: $deviceId');

    try {
      // 获取本地数据
      final targetsData = await _getTargetsData();

      // 转换为可同步格式
      final syncData = _convertTargetsToSyncable(targetsData);

      // 发送数据
      final message = SyncMessage.dataUpdate(
        _currentDevice!.deviceId,
        'targets',
        syncData,
      );
      _sendMessageToDevice(deviceId, message);

      final itemCount = targetsData.length;
      print('✅ [SyncService] 已发送 $itemCount 个目标');
    } catch (e) {
      print('❌ [SyncService] 同步目标失败: $e');
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

  /// 转换目标为可同步格式
  List<Map<String, dynamic>> _convertTargetsToSyncable(
      List<Map<String, dynamic>> targets) {
    return targets.map((target) {
      return {
        ...target,
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
      int mergedItems = 0;
      int updatedItems = 0;

      // 获取本地数据和元数据
      final localTodos = await TodoStorage.getTodoItems();
      final localSyncMetadata = await TodoStorage.getSyncMetadata();
      bool hasChanges = false;

      // 处理待办项
      if (remoteData['items'] != null) {
        final remoteItems = (remoteData['items'] as List)
            .map((json) => SyncableTodoItem.fromJson(json))
            .toList();

        print('📦 [SyncService] 收到 ${remoteItems.length} 个待办事项');

        for (final remoteItem in remoteItems) {
          try {
            // 构建本地的 SyncableTodoItem（如果存在）
            SyncableTodoItem? localSyncableItem;
            final localItem = localTodos[remoteItem.id];
            if (localItem != null) {
              final localMetadata = localSyncMetadata[remoteItem.id] ??
                  SyncMetadata.create(_currentDevice?.deviceId ?? 'unknown');
              localSyncableItem = SyncableTodoItem(
                id: localItem.id,
                title: localItem.title,
                description: localItem.description,
                isCompleted: localItem.isCompleted,
                createdAt: localItem.createdAt,
                listId: localItem.listId,
                syncMetadata: localMetadata,
              );
            }

            // 使用冲突解决器
            final resolution = _conflictResolver.resolveTodoItemConflict(
                localSyncableItem, remoteItem);

            if (resolution.hasConflict) {
              conflictCount++;
              print(
                  '⚠️  [SyncService] 冲突: ${remoteItem.title} - ${resolution.resolution}');
            }

            // 应用解决后的数据
            if (resolution.resolvedData != null) {
              final resolved = resolution.resolvedData!;

              // 保存数据
              localTodos[resolved.id] = TodoItemData(
                id: resolved.id,
                title: resolved.title,
                description: resolved.description,
                isCompleted: resolved.isCompleted,
                createdAt: resolved.createdAt,
                listId: resolved.listId,
              );

              // 保存元数据
              localSyncMetadata[resolved.id] = resolved.syncMetadata;

              if (localSyncableItem == null) {
                mergedItems++;
                print('➕ [SyncService] 新增待办: ${resolved.title}');
              } else {
                updatedItems++;
                print('🔄 [SyncService] 更新待办: ${resolved.title}');
              }
              hasChanges = true;
            }
          } catch (e) {
            print('❌ [SyncService] 处理待办项失败: ${remoteItem.id}, $e');
          }
        }

        // 保存所有更新
        if (hasChanges) {
          await TodoStorage.saveTodoItems(localTodos);
          await TodoStorage.saveSyncMetadata(localSyncMetadata);
          print('💾 [SyncService] 保存了 $mergedItems 个新待办项, $updatedItems 个更新项');
          print('⚠️  [SyncService] 解决了 $conflictCount 个冲突');
        }
      }

      // 处理待办列表
      if (remoteData['lists'] != null) {
        final remoteLists = (remoteData['lists'] as List)
            .map((json) => SyncableTodoList.fromJson(json))
            .toList();

        print('📦 [SyncService] 收到 ${remoteLists.length} 个待办列表');

        final localLists = await TodoStorage.getTodoLists();
        final localListMap = {for (var list in localLists) list.id: list};
        bool listHasChanges = false;

        for (final remoteList in remoteLists) {
          try {
            // 构建本地的 SyncableTodoList（如果存在）
            SyncableTodoList? localSyncableList;
            final localList = localListMap[remoteList.id];
            if (localList != null) {
              final listMetadataId = 'list_${localList.id}';
              final localMetadata = localSyncMetadata[listMetadataId] ??
                  SyncMetadata.create(_currentDevice?.deviceId ?? 'unknown');
              localSyncableList = SyncableTodoList(
                id: localList.id,
                name: localList.name,
                isExpanded: localList.isExpanded,
                colorValue: localList.colorValue,
                itemIds: localList.itemIds,
                syncMetadata: localMetadata,
              );
            }

            // 使用冲突解决器
            final resolution = _conflictResolver.resolveTodoListConflict(
                localSyncableList, remoteList);

            if (resolution.hasConflict) {
              conflictCount++;
              print(
                  '⚠️  [SyncService] 列表冲突: ${remoteList.name} - ${resolution.resolution}');
            }

            // 应用解决后的数据
            if (resolution.resolvedData != null) {
              final resolved = resolution.resolvedData!;

              // 更新列表数据
              localListMap[resolved.id] = TodoListData(
                id: resolved.id,
                name: resolved.name,
                isExpanded: resolved.isExpanded,
                colorValue: resolved.colorValue,
                itemIds: resolved.itemIds,
              );

              // 保存列表的元数据
              final listMetadataId = 'list_${resolved.id}';
              localSyncMetadata[listMetadataId] = resolved.syncMetadata;

              if (localSyncableList == null) {
                print('➕ [SyncService] 新增列表: ${resolved.name}');
              } else {
                print('🔄 [SyncService] 更新列表: ${resolved.name}');
              }
              listHasChanges = true;
            }
          } catch (e) {
            print('❌ [SyncService] 处理列表失败: ${remoteList.id}, $e');
          }
        }

        // 保存列表更新
        if (listHasChanges) {
          await TodoStorage.saveTodoLists(localListMap.values.toList());
          await TodoStorage.saveSyncMetadata(localSyncMetadata);
          print('💾 [SyncService] 保存了列表更新');
        }
      }

      // 通知UI更新
      final totalItems = mergedItems + updatedItems;
      if (totalItems > 0) {
        _notifyDataUpdated('todos', fromDeviceId, totalItems);
      }
    } catch (e, stack) {
      print('❌ [SyncService] 处理待办数据失败: $e');
      print('Stack: $stack');
    }
  }

  /// 处理接收到的时间日志数据
  Future<void> _handleTimeLogsDataUpdate(
      List<dynamic> remoteLogs, String fromDeviceId) async {
    print('🔄 [SyncService] 处理时间日志更新: 来自 $fromDeviceId');

    try {
      final syncableLogs =
          remoteLogs.map((json) => SyncableTimeLog.fromJson(json)).toList();

      print('📦 [SyncService] 收到 ${syncableLogs.length} 个时间日志');

      int mergedLogs = 0;

      // 获取本地所有记录
      final existingLogs =
          await TimeLoggerStorage.getAllRecords(forceRefresh: true);

      for (final remoteLog in syncableLogs) {
        try {
          // 检查是否已存在（使用startTime作为唯一标识）
          final exists = existingLogs.any((log) =>
              log.startTime.millisecondsSinceEpoch ==
              remoteLog.startTime.millisecondsSinceEpoch);

          if (!exists) {
            // 保存时间日志
            await TimeLoggerStorage.addRecord(ActivityRecordData(
              name: remoteLog.name,
              startTime: remoteLog.startTime,
              endTime: remoteLog.endTime,
              linkedTodoId: remoteLog.linkedTodoId,
              linkedTodoTitle: null, // 可以后续从todos中查找
            ));
            mergedLogs++;
            print('➕ [SyncService] 新增时间日志: ${remoteLog.name}');
          } else {
            print('⏭️  [SyncService] 跳过已存在的日志: ${remoteLog.name}');
          }
        } catch (e) {
          print('❌ [SyncService] 处理时间日志失败: ${remoteLog.id}, $e');
        }
      }

      // 记录历史
      final device = _serverService.getConnectedDevice(fromDeviceId);
      if (device != null) {
        await _historyService.recordMerge(
          deviceId: fromDeviceId,
          deviceName: device.deviceName,
          dataType: 'timeLogs',
          itemCount: mergedLogs,
          description: '成功合并 $mergedLogs 个时间日志',
          success: true,
        );
      }

      print('✅ [SyncService] 时间日志更新完成: 合并 $mergedLogs 条');

      // 发送数据更新事件
      _notifyDataUpdated('timeLogs', fromDeviceId, mergedLogs);
    } catch (e) {
      print('❌ [SyncService] 处理时间日志更新失败: $e');
    }
  }

  /// 处理接收到的目标数据
  Future<void> _handleTargetsDataUpdate(
      List<dynamic> remoteTargets, String fromDeviceId) async {
    print('🔄 [SyncService] 处理目标更新: 来自 $fromDeviceId');

    try {
      final storage = TargetStorage();
      final localTargets = await storage.loadTargets();

      print('📦 [SyncService] 收到 ${remoteTargets.length} 个目标');

      int mergedCount = 0;
      bool hasChanges = false;

      for (final remoteTargetJson in remoteTargets) {
        try {
          final remoteSyncable = SyncableTarget.fromJson(remoteTargetJson);

          // 检查本地是否已存在该目标
          final existingIndex =
              localTargets.indexWhere((t) => t.id == remoteSyncable.id);

          if (existingIndex == -1) {
            // 本地不存在，直接添加
            localTargets.add(Target(
              id: remoteSyncable.id,
              name: remoteSyncable.name,
              type: TargetType.values[remoteSyncable.type],
              period: TimePeriod.values[remoteSyncable.period],
              targetSeconds: remoteSyncable.targetSeconds,
              linkedTodoIds: remoteSyncable.linkedTodoIds,
              linkedListIds: remoteSyncable.linkedListIds,
              createdAt: remoteSyncable.createdAt,
              isActive: remoteSyncable.isActive,
              color: Color(remoteSyncable.colorValue),
            ));
            mergedCount++;
            hasChanges = true;
            print('➕ [SyncService] 新增目标: ${remoteSyncable.name}');
          } else {
            // 本地存在，检查是否需要更新（使用元数据时间戳）
            final localTarget = localTargets[existingIndex];
            if (remoteSyncable.syncMetadata.lastModifiedAt
                .isAfter(localTarget.createdAt)) {
              localTargets[existingIndex] = Target(
                id: remoteSyncable.id,
                name: remoteSyncable.name,
                type: TargetType.values[remoteSyncable.type],
                period: TimePeriod.values[remoteSyncable.period],
                targetSeconds: remoteSyncable.targetSeconds,
                linkedTodoIds: remoteSyncable.linkedTodoIds,
                linkedListIds: remoteSyncable.linkedListIds,
                createdAt: remoteSyncable.createdAt,
                isActive: remoteSyncable.isActive,
                color: Color(remoteSyncable.colorValue),
              );
              hasChanges = true;
              print('🔄 [SyncService] 更新目标: ${remoteSyncable.name}');
            } else {
              print('⏭️  [SyncService] 跳过旧版本目标: ${remoteSyncable.name}');
            }
          }
        } catch (e) {
          print('❌ [SyncService] 处理目标失败: $e');
        }
      }

      // 保存更新后的目标列表
      if (hasChanges) {
        await storage.saveTargets(localTargets);
        print('💾 [SyncService] 目标数据已保存');
      }

      // 记录历史
      final device = _serverService.getConnectedDevice(fromDeviceId);
      if (device != null) {
        await _historyService.recordMerge(
          deviceId: fromDeviceId,
          deviceName: device.deviceName,
          dataType: 'targets',
          itemCount: mergedCount,
          description: '成功合并 $mergedCount 个目标',
          success: true,
        );
      }

      print('✅ [SyncService] 目标更新完成: 合并 $mergedCount 个');

      // 发送数据更新事件
      _notifyDataUpdated('targets', fromDeviceId, mergedCount);
    } catch (e) {
      print('❌ [SyncService] 处理目标更新失败: $e');
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
    _dataUpdatedController.close();
  }
}
