import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sync_models.dart';
import '../models/sync_data_models.dart';
import '../models/sync_error.dart';
import '../utils/sync_compression.dart';
import '../utils/sync_lock.dart';
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
  // 🆕 使用同步锁替代简单的布尔标志
  final SyncLock _syncLock = SyncLock();

  // 上次同步时间跟踪（按设备ID存储）
  final Map<String, DateTime> _lastSyncTimes = {};

  // 同步模式
  SyncMode _syncMode = SyncMode.incremental; // 默认增量同步

  // 已连接设备管理（包括主动连接和被动连接）
  final Map<String, DeviceInfo> _connectedDevicesMap = {};

  // 🆕 同步队列和重试机制
  final List<_SyncTask> _syncQueue = [];
  final Map<String, int> _syncRetryCount = {}; // 按设备ID记录重试次数
  final Map<String, DateTime> _lastSyncAttempt = {}; // 上次同步尝试时间
  static const int _maxSyncRetries = 3; // 最大重试次数
  static const Duration _minRetryDelay = Duration(seconds: 2); // 最小重试延迟
  static const Duration _maxRetryDelay = Duration(seconds: 30); // 最大重试延迟
  bool _isProcessingQueue = false; // 队列处理中标志

  // 🆕 同步性能监控
  final Map<String, _SyncPerformanceMetrics> _performanceMetrics = {};

  // 🆕 连接健康检查
  Timer? _connectionHealthCheckTimer;
  static const Duration _healthCheckInterval = Duration(minutes: 1);

  // 🆕 内存清理定时器
  Timer? _memoryCleanupTimer;
  static const Duration _memoryCleanupInterval = Duration(hours: 1);
  static const int _maxPerformanceMetricsAge = 7; // 保留最近7天的性能指标
  static const int _maxSyncQueueSize = 50; // 最大队列大小

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
  final StreamController<SyncError> _errorController =
      StreamController.broadcast();
  final StreamController<SyncProgressEvent> _syncProgressController =
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
  Stream<SyncError> get errorStream => _errorController.stream;
  Stream<SyncProgressEvent> get syncProgressStream =>
      _syncProgressController.stream;

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

    // 🆕 启动连接健康检查
    _startConnectionHealthCheck();

    // 🆕 启动内存清理
    _startMemoryCleanup();
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

    // 🆕 停止连接健康检查
    _stopConnectionHealthCheck();

    // 🆕 停止内存清理
    _stopMemoryCleanup();

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
      case SyncMessageType.timerForceStop:
        _handleTimerForceStop(message);
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
    if (message.data == null) {
      print('⚠️  [SyncService] 数据请求消息缺少data字段');
      return;
    }

    final dataType = message.data!['dataType'];
    if (dataType == null || dataType is! String) {
      print('⚠️  [SyncService] 数据请求消息缺少或无效的dataType字段');
      return;
    }

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
    if (message.data == null) {
      print('⚠️  [SyncService] 数据更新消息缺少data字段');
      return;
    }

    final dataType = message.data!['dataType'];
    final updateData = message.data!['data'];

    if (dataType == null || dataType is! String) {
      print('⚠️  [SyncService] 数据更新消息dataType无效');
      return;
    }

    if (updateData == null || message.senderId == null) {
      print('⚠️  [SyncService] 数据更新消息缺少必要字段');
      return;
    }

    print('🔄 [SyncService] 处理数据更新: $dataType from ${message.senderId}');

    // 验证数据完整性
    if (!_validateSyncData(updateData, dataType)) {
      print('❌ [SyncService] 数据校验失败，拒绝更新');
      _handleError(SyncError(
        type: SyncErrorType.unknown,
        message: '接收到的数据格式不正确',
        details: '数据类型: $dataType, 来源: ${message.senderId}',
        isRecoverable: false,
      ));
      return;
    }

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
    if (message.data == null || message.senderId == null) {
      print('⚠️  [SyncService] 计时开始消息缺少必要字段');
      return;
    }

    final todoId = message.data!['todoId'];
    final startTimeStr = message.data!['startTime'];

    if (todoId == null || todoId is! String) {
      print('⚠️  [SyncService] 计时开始消息todoId无效');
      return;
    }

    if (startTimeStr == null || startTimeStr is! String) {
      print('⚠️  [SyncService] 计时开始消息startTime无效');
      return;
    }

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

  /// 处理强制停止计时（冲突解决）
  void _handleTimerForceStop(SyncMessage message) async {
    if (message.data == null) return;

    print('⚠️  [SyncService] 收到强制停止计时消息');
    print('   原因: ${message.data!['reason']}');
    print('   消息: ${message.data!['message']}');

    try {
      // 获取本地当前活动
      final localActivity = await TimeLoggerStorage.getCurrentActivity();
      if (localActivity == null) {
        print('ℹ️  [SyncService] 本地无活动，无需停止');
        return;
      }

      // 解析结束时间
      final newerActivityStartTimeStr =
          message.data!['newerActivityStartTime'] as String?;
      final endTime = newerActivityStartTimeStr != null
          ? DateTime.parse(newerActivityStartTimeStr)
          : DateTime.now();

      // 结束本地活动
      final endedActivity = ActivityRecordData(
        name: localActivity.name,
        startTime: localActivity.startTime,
        endTime: endTime,
        linkedTodoId: localActivity.linkedTodoId,
        linkedTodoTitle: localActivity.linkedTodoTitle,
      );

      // 保存为完成的记录
      await TimeLoggerStorage.addRecord(endedActivity);
      print('💾 [SyncService] 本地活动已保存为完成记录（被强制停止）');

      // 清除当前活动
      await TimeLoggerStorage.saveCurrentActivity(null);
      print('🗑️  [SyncService] 本地当前活动已清除');

      // 通知UI更新
      _notifyActiveTimersChanged();
    } catch (e) {
      print('❌ [SyncService] 处理强制停止失败: $e');
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
      // 🆕 使用设备ID + 时间戳 + 哈希值生成唯一ID，避免冲突
      final deviceId = _currentDevice?.deviceId ?? 'unknown';
      final timestamp = log.startTime.millisecondsSinceEpoch;
      final hash = log.name.hashCode.abs();
      final id = '$deviceId-$timestamp-$hash';

      // 创建简单的同步元数据（时间日志使用简单的时间戳策略）
      final metadata = SyncMetadata(
        lastModifiedAt: log.endTime ?? log.startTime,
        lastModifiedBy: deviceId,
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

  /// 通知同步进度
  void _notifySyncProgress(SyncProgressEvent event) {
    if (!_syncProgressController.isClosed) {
      _syncProgressController.add(event);
      print(
          '📊 [SyncService] 同步进度: ${event.phase} - ${event.dataType} (${(event.progress * 100).toInt()}%)');
    }
  }

  /// 获取指定设备的上次同步时间
  DateTime? getLastSyncTime(String deviceId) {
    return _lastSyncTimes[deviceId];
  }

  /// 设置同步模式（增量/全量）
  void setSyncMode(SyncMode mode) {
    _syncMode = mode;
    print(
        '🔄 [SyncService] 同步模式已设置为: ${mode == SyncMode.incremental ? "增量" : "全量"}');
  }

  /// 检查数据是否需要同步（基于最后修改时间）
  bool _shouldSyncData(DateTime lastModified, String deviceId) {
    // 如果是全量同步模式，总是返回 true
    if (_syncMode == SyncMode.full) {
      return true;
    }

    // 增量同步模式：检查数据是否在上次同步后被修改
    final lastSync = _lastSyncTimes[deviceId];
    if (lastSync == null) {
      // 从未同步过，需要同步
      return true;
    }
    // 如果数据在上次同步后被修改，需要同步
    return lastModified.isAfter(lastSync);
  }

  /// 过滤需要同步的数据（增量同步优化）
  List<T> _filterSyncableData<T extends SyncableData>(
    List<T> allData,
    String deviceId,
  ) {
    if (_syncMode == SyncMode.full) {
      print('📦 [SyncService] 全量同步模式，发送所有 ${allData.length} 项数据');
      return allData;
    }

    // 增量同步：只发送修改过的数据
    final filtered = allData.where((item) {
      return _shouldSyncData(item.syncMetadata.lastModifiedAt, deviceId);
    }).toList();

    print(
        '📦 [SyncService] 增量同步模式，从 ${allData.length} 项中筛选出 ${filtered.length} 项需要同步');
    return filtered;
  }

  /// 🆕 验证同步数据的完整性（增强版）
  bool _validateSyncData(dynamic data, String dataType) {
    try {
      switch (dataType) {
        case 'todos':
          // 验证待办数据结构
          if (data is! Map<String, dynamic>) {
            print('❌ [SyncService] 待办数据类型错误: 期望 Map，实际 ${data.runtimeType}');
            return false;
          }
          if (!data.containsKey('items') || !data.containsKey('lists')) {
            print('❌ [SyncService] 待办数据缺少必需字段: items或lists');
            return false;
          }
          final items = data['items'];
          final lists = data['lists'];
          if (items is! List || lists is! List) {
            print(
                '❌ [SyncService] 待办数据类型错误: items=${items.runtimeType}, lists=${lists.runtimeType}');
            return false;
          }
          // 🆕 验证每个待办项有必需字段和有效值
          for (var i = 0; i < items.length; i++) {
            final item = items[i];
            if (item is! Map) {
              print('❌ [SyncService] 待办项[$i]类型错误: ${item.runtimeType}');
              return false;
            }
            if (!item.containsKey('id') ||
                item['id'] == null ||
                item['id'].toString().isEmpty) {
              print('❌ [SyncService] 待办项[$i]缺少或无效的id');
              return false;
            }
            if (!item.containsKey('title') || item['title'] == null) {
              print('❌ [SyncService] 待办项[$i]缺少title');
              return false;
            }
            if (!item.containsKey('syncMetadata')) {
              print('❌ [SyncService] 待办项[$i]缺少syncMetadata');
              return false;
            }
            // 🆕 验证同步元数据
            final metadata = item['syncMetadata'];
            if (metadata is! Map ||
                !metadata.containsKey('lastModifiedAt') ||
                !metadata.containsKey('version')) {
              print('❌ [SyncService] 待办项[$i]的syncMetadata格式无效');
              return false;
            }
          }
          // 🆕 验证列表
          for (var i = 0; i < lists.length; i++) {
            final list = lists[i];
            if (list is! Map ||
                !list.containsKey('id') ||
                !list.containsKey('name')) {
              print('❌ [SyncService] 待办列表[$i]格式无效');
              return false;
            }
          }
          print(
              '✅ [SyncService] 待办数据验证通过: ${items.length}项, ${lists.length}列表');
          return true;

        case 'timeLogs':
          // 验证时间日志数据
          if (data is! List) {
            print('❌ [SyncService] 时间日志数据类型错误: 期望 List，实际 ${data.runtimeType}');
            return false;
          }
          for (var i = 0; i < data.length; i++) {
            final log = data[i];
            if (log is! Map) {
              print('❌ [SyncService] 时间日志[$i]类型错误');
              return false;
            }
            if (!log.containsKey('id') ||
                !log.containsKey('startTime') ||
                !log.containsKey('name')) {
              print('❌ [SyncService] 时间日志[$i]缺少必需字段');
              return false;
            }
            // 🆕 验证时间格式
            try {
              DateTime.parse(log['startTime'].toString());
              if (log.containsKey('endTime') && log['endTime'] != null) {
                DateTime.parse(log['endTime'].toString());
              }
            } catch (e) {
              print('❌ [SyncService] 时间日志[$i]时间格式无效: $e');
              return false;
            }
          }
          print('✅ [SyncService] 时间日志验证通过: ${data.length}条');
          return true;

        case 'targets':
          // 验证目标数据
          if (data is! List) {
            print('❌ [SyncService] 目标数据类型错误: 期望 List，实际 ${data.runtimeType}');
            return false;
          }
          for (var i = 0; i < data.length; i++) {
            final target = data[i];
            if (target is! Map) {
              print('❌ [SyncService] 目标[$i]类型错误');
              return false;
            }
            if (!target.containsKey('id') ||
                !target.containsKey('name') ||
                !target.containsKey('type')) {
              print('❌ [SyncService] 目标[$i]缺少必需字段');
              return false;
            }
            // 🆕 验证类型和周期值
            if (target.containsKey('type') && target['type'] is! int) {
              print('❌ [SyncService] 目标[$i]type类型无效');
              return false;
            }
            if (target.containsKey('period') && target['period'] is! int) {
              print('❌ [SyncService] 目标[$i]period类型无效');
              return false;
            }
            if (target.containsKey('targetSeconds') &&
                target['targetSeconds'] is! int) {
              print('❌ [SyncService] 目标[$i]targetSeconds类型无效');
              return false;
            }
          }
          print('✅ [SyncService] 目标数据验证通过: ${data.length}个');
          return true;

        default:
          print('⚠️  [SyncService] 未知数据类型: $dataType');
          return false;
      }
    } catch (e, stackTrace) {
      print('❌ [SyncService] 数据校验异常: $e');
      print(
          'Stack trace: ${stackTrace.toString().split('\n').take(3).join('\n')}');
      return false;
    }
  }

  /// 🆕 处理和报告错误（增强版）
  void _handleError(SyncError error) {
    // 生成详细的错误日志
    final timestamp = DateTime.now().toIso8601String();
    final deviceInfo = _currentDevice != null
        ? '${_currentDevice!.deviceName} (${_currentDevice!.deviceId})'
        : 'Unknown Device';

    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('❌ [SyncService] 错误报告 [$timestamp]');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📱 设备: $deviceInfo');
    print('🏷️  类型: ${error.type}');
    print('💬 消息: ${error.message}');
    print('📋 用户消息: ${error.getUserFriendlyMessage()}');
    print('💡 建议: ${error.getSuggestion()}');

    if (error.details != null) {
      print('📝 详情: ${error.details}');
    }

    if (error.originalError != null) {
      print('🔍 原始错误: ${error.originalError}');
    }

    if (error.stackTrace != null) {
      print('📚 堆栈跟踪 (前5行):');
      print(
          '   ${error.stackTrace.toString().split('\n').take(5).join('\n   ')}');
    }

    print('🔄 可恢复: ${error.isRecoverable}');
    print('👤 显示给用户: ${error.shouldShowToUser()}');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n');

    // 只向用户显示需要显示的错误
    if (error.shouldShowToUser() && !_errorController.isClosed) {
      _errorController.add(error);
    }
  }

  /// 安全执行操作，捕获并处理错误
  /// 这是一个通用工具方法，可以在需要的地方使用
  /// 示例：await _safeExecute(() => someRiskyOperation(), operationName: '操作名称');
  Future<T?> _safeExecute<T>(
    Future<T> Function() operation, {
    required String operationName,
    T? defaultValue,
  }) async {
    try {
      return await operation();
    } catch (e, stackTrace) {
      final syncError = SyncError.fromException(
        e,
        stackTrace: stackTrace,
      );
      _handleError(SyncError(
        type: syncError.type,
        message: syncError.message,
        details: '操作: $operationName',
        originalError: syncError.originalError,
        stackTrace: stackTrace,
        isRecoverable: syncError.isRecoverable,
      ));
      return defaultValue;
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
    if (_currentDevice == null) {
      _handleError(SyncError(
        type: SyncErrorType.unknown,
        message: '当前设备信息未初始化',
        isRecoverable: false,
      ));
      return false;
    }

    print('🔗 [SyncService] 连接到设备: ${device.deviceName}');
    print('🔍 [SyncService] 设备详情: deviceId=${device.deviceId}');
    print(
        '🔍 [SyncService] 设备IP: "${device.ipAddress}" (长度: ${device.ipAddress.length})');
    print('🔍 [SyncService] 设备端口: ${device.port}');

    // 验证IP地址不为空
    if (device.ipAddress.isEmpty) {
      _handleError(SyncError(
        type: SyncErrorType.deviceNotFound,
        message: 'IP地址为空，无法连接',
        details: '设备: ${device.deviceName}',
      ));
      return false;
    }

    // 使用 _safeExecute 进行错误处理
    final result = await _safeExecute<bool>(
      () async {
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

          print('✅ [SyncService] 成功连接到: ${device.deviceName}');
          return true;
        } else {
          _handleError(SyncError(
            type: SyncErrorType.connectionFailed,
            message: '无法连接到设备',
            details:
                '设备: ${device.deviceName} (${device.ipAddress}:${device.port})',
          ));
          return false;
        }
      },
      operationName: '连接到设备 ${device.deviceName}',
      defaultValue: false,
    );

    return result ?? false;
  }

  /// 断开设备连接
  Future<void> disconnectFromDevice(String deviceId) async {
    await _safeExecute(
      () async {
        final client = _clientServices[deviceId];
        if (client != null) {
          await client.disconnect();
          _clientServices.remove(deviceId);
          _connectedDevicesMap.remove(deviceId);
          _notifyConnectedDevicesChanged();
          print('✅ [SyncService] 已断开设备连接: $deviceId');
        }
      },
      operationName: '断开设备连接 $deviceId',
    );
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
    // 🆕 使用同步锁防止并发
    final acquired = await _syncLock.acquire(deviceId, 'syncAllDataToDevice');
    if (!acquired) {
      _handleError(SyncError(
        type: SyncErrorType.operationInProgress,
        message: '同步操作正在进行中',
        details: '设备: $deviceId',
        isRecoverable: true,
      ));
      return false;
    }

    try {
      return await _syncAllDataToDeviceInternal(deviceId);
    } finally {
      await _syncLock.release(deviceId);
    }
  }

  /// 内部同步方法（不包含锁检查）
  Future<bool> _syncAllDataToDeviceInternal(String deviceId) async {
    if (_currentDevice == null) {
      _handleError(SyncError(
        type: SyncErrorType.unknown,
        message: '设备信息未初始化',
        isRecoverable: false,
      ));
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
        _handleError(SyncError(
          type: SyncErrorType.deviceNotFound,
          message: '未找到设备',
          details: 'Device ID: $deviceId',
        ));
        return false;
      }

      // 尝试连接
      print('🔗 [SyncService] 正在连接到设备: ${discoveredDevice.deviceName}');
      final connected = await connectToDevice(discoveredDevice);
      if (!connected) {
        _handleError(SyncError(
          type: SyncErrorType.connectionFailed,
          message: '自动连接失败',
          details: '设备: ${discoveredDevice.deviceName}',
        ));
        return false;
      }

      device = discoveredDevice;
      print('✅ [SyncService] 自动连接成功');
    }

    print('🔄 [SyncService] 开始全量同步到: ${device.deviceName}');

    try {
      // 发送初始进度事件
      _notifySyncProgress(SyncProgressEvent(
        deviceId: deviceId,
        deviceName: device.deviceName,
        phase: 'starting',
        dataType: 'all',
        progress: 0.0,
        message: '开始同步...',
      ));

      // ⚡ 第一步：解决活动计时冲突 (10%)
      _notifySyncProgress(SyncProgressEvent(
        deviceId: deviceId,
        deviceName: device.deviceName,
        phase: 'resolving_conflicts',
        dataType: 'timers',
        progress: 0.1,
        message: '正在解决计时冲突...',
      ));
      await _resolveActiveTimerConflicts(deviceId);

      // 同步待办事项 (40%)
      _notifySyncProgress(SyncProgressEvent(
        deviceId: deviceId,
        deviceName: device.deviceName,
        phase: 'syncing',
        dataType: 'todos',
        progress: 0.2,
        message: '正在准备待办事项数据...',
      ));

      final todoData = await _getTodosData();
      // 🆕 添加空值和类型安全检查
      final items = todoData['items'];
      final lists = todoData['lists'];
      if (items is! List || lists is! List) {
        print('❌ [SyncService] 待办数据格式错误');
        return false;
      }
      final todoCount = items.length + lists.length;

      _notifySyncProgress(SyncProgressEvent(
        deviceId: deviceId,
        deviceName: device.deviceName,
        phase: 'syncing',
        dataType: 'todos',
        progress: 0.3,
        message: '正在发送 $todoCount 项待办数据...',
      ));
      await _syncTodosToDevice(deviceId);

      // 同步时间日志 (70%)
      _notifySyncProgress(SyncProgressEvent(
        deviceId: deviceId,
        deviceName: device.deviceName,
        phase: 'syncing',
        dataType: 'timeLogs',
        progress: 0.5,
        message: '正在准备时间日志...',
      ));

      final logsData = await _getTimeLogsData();
      final logsCount = logsData.length;

      _notifySyncProgress(SyncProgressEvent(
        deviceId: deviceId,
        deviceName: device.deviceName,
        phase: 'syncing',
        dataType: 'timeLogs',
        progress: 0.6,
        message: '正在发送 $logsCount 条时间日志...',
      ));
      await _syncTimeLogsToDevice(deviceId);

      // 同步目标 (90%)
      _notifySyncProgress(SyncProgressEvent(
        deviceId: deviceId,
        deviceName: device.deviceName,
        phase: 'syncing',
        dataType: 'targets',
        progress: 0.8,
        message: '正在准备目标数据...',
      ));

      final targetsData = await _getTargetsData();
      final targetsCount = targetsData.length;

      _notifySyncProgress(SyncProgressEvent(
        deviceId: deviceId,
        deviceName: device.deviceName,
        phase: 'syncing',
        dataType: 'targets',
        progress: 0.85,
        message: '正在发送 $targetsCount 个目标...',
      ));
      await _syncTargetsToDevice(deviceId);

      // 完成 (100%)
      _notifySyncProgress(SyncProgressEvent(
        deviceId: deviceId,
        deviceName: device.deviceName,
        phase: 'completed',
        dataType: 'all',
        progress: 1.0,
        message: '同步完成！',
      ));

      // 记录成功
      await _historyService.recordPush(
        deviceId: deviceId,
        deviceName: device.deviceName,
        dataType: 'all',
        itemCount: 0,
        description: '全量同步成功 (包含待办、日志、目标)',
        success: true,
      );

      // 记录同步时间
      _lastSyncTimes[deviceId] = DateTime.now();

      print('✅ [SyncService] 全量同步完成');
      return true;
    } catch (e, stackTrace) {
      final error = SyncError.fromException(e, stackTrace: stackTrace);
      _handleError(SyncError(
        type: error.type,
        message: '全量同步失败',
        details: '目标设备: ${device.deviceName}',
        originalError: e,
        stackTrace: stackTrace,
      ));

      await _historyService.recordPush(
        deviceId: deviceId,
        deviceName: device.deviceName,
        dataType: 'all',
        itemCount: 0,
        success: false,
        errorMessage: error.getUserFriendlyMessage(),
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

  // ==================== 活动计时冲突解决 ====================

  /// 解决活动计时冲突
  /// 当两台设备都有正在进行的计时活动时，保留较晚开始的活动，结束较早的活动
  Future<void> _resolveActiveTimerConflicts(String remoteDeviceId) async {
    print('🔍 [SyncService] 检测活动计时冲突...');

    try {
      // 1. 获取本地当前活动
      final localActivity = await TimeLoggerStorage.getCurrentActivity();

      // 2. 获取远程设备的活动状态
      final remoteTimer = _activeTimers[remoteDeviceId];

      // 3. 如果只有一方有活动，无需处理
      if (localActivity == null && remoteTimer == null) {
        print('✅ [SyncService] 无活动冲突');
        return;
      }

      if (localActivity == null) {
        print('📥 [SyncService] 本地无活动，远程有活动: ${remoteTimer!.todoTitle}');
        // 远程活动会通过正常的计时同步机制处理
        return;
      }

      if (remoteTimer == null) {
        print('📤 [SyncService] 本地有活动，远程无活动: ${localActivity.name}');
        // 本地活动会通过broadcastTimerStart发送
        return;
      }

      // 4. 两边都有活动，需要解决冲突
      print('⚠️  [SyncService] 检测到活动冲突:');
      print(
          '   本地活动: ${localActivity.name} (开始时间: ${localActivity.startTime})');
      print(
          '   远程活动: ${remoteTimer.todoTitle} (开始时间: ${remoteTimer.startTime})');

      // 5. 比较开始时间，保留较晚的活动
      if (localActivity.startTime.isAfter(remoteTimer.startTime)) {
        // 本地活动更晚，结束远程活动
        print('🏆 [SyncService] 本地活动更晚，将结束远程活动');
        await _endRemoteActivity(remoteDeviceId, remoteTimer);

        // 广播本地活动
        if (localActivity.linkedTodoId != null) {
          broadcastTimerStart(
            localActivity.linkedTodoId!,
            localActivity.linkedTodoTitle ?? localActivity.name,
            localActivity.startTime,
          );
        }
      } else {
        // 远程活动更晚，结束本地活动
        print('🏆 [SyncService] 远程活动更晚，将结束本地活动');
        await _endLocalActivity(localActivity, remoteTimer.startTime);

        // 远程活动已经在_activeTimers中，会自动显示
      }

      print('✅ [SyncService] 活动冲突已解决');
    } catch (e) {
      print('❌ [SyncService] 解决活动冲突失败: $e');
      // 不抛出异常，继续同步其他数据
    }
  }

  /// 结束本地活动
  Future<void> _endLocalActivity(
      ActivityRecordData localActivity, DateTime conflictTime) async {
    print('⏹️  [SyncService] 结束本地活动: ${localActivity.name}');

    try {
      // 使用冲突时间作为结束时间（远程活动的开始时间）
      final endedActivity = ActivityRecordData(
        name: localActivity.name,
        startTime: localActivity.startTime,
        endTime: conflictTime,
        linkedTodoId: localActivity.linkedTodoId,
        linkedTodoTitle: localActivity.linkedTodoTitle,
      );

      // 保存为完成的记录
      await TimeLoggerStorage.addRecord(endedActivity);
      print('💾 [SyncService] 本地活动已保存为完成记录');

      // 清除当前活动
      await TimeLoggerStorage.saveCurrentActivity(null);
      print('🗑️  [SyncService] 本地当前活动已清除');

      // 广播计时停止
      if (localActivity.linkedTodoId != null) {
        final duration =
            conflictTime.difference(localActivity.startTime).inSeconds;
        broadcastTimerStop(
          localActivity.linkedTodoId!,
          localActivity.startTime,
          conflictTime,
          duration,
        );
      }
    } catch (e) {
      print('❌ [SyncService] 结束本地活动失败: $e');
      rethrow;
    }
  }

  /// 结束远程活动
  Future<void> _endRemoteActivity(
      String remoteDeviceId, TimerState remoteTimer) async {
    print('⏹️  [SyncService] 通知远程设备结束活动: ${remoteTimer.todoTitle}');

    try {
      // 发送停止计时消息到远程设备
      if (_currentDevice != null) {
        final message = SyncMessage(
          type: SyncMessageType.timerForceStop,
          senderId: _currentDevice!.deviceId,
          data: {
            'reason': 'activity_conflict',
            'newerActivityStartTime': DateTime.now().toIso8601String(),
            'message': '检测到更新的活动，自动结束此活动',
          },
        );
        _sendMessageToDevice(remoteDeviceId, message);
        print('📤 [SyncService] 已发送强制停止消息');
      }

      // 从本地活动列表中移除
      _activeTimers.remove(remoteDeviceId);
      _notifyActiveTimersChanged();
    } catch (e) {
      print('❌ [SyncService] 结束远程活动失败: $e');
      rethrow;
    }
  }

  // ==================== 数据转换方法 ====================

  /// 同步待办事项到指定设备
  Future<void> _syncTodosToDevice(String deviceId) async {
    print('📤 [SyncService] 同步待办事项到: $deviceId');

    try {
      // 获取本地数据
      final todoData = await _getTodosData();

      // 解析待办项和列表
      final allItems = (todoData['items'] as List)
          .map((json) => SyncableTodoItem.fromJson(json))
          .toList();
      final allLists = (todoData['lists'] as List)
          .map((json) => SyncableTodoList.fromJson(json))
          .toList();

      // 根据同步模式过滤需要同步的数据
      final itemsToSync =
          _filterSyncableData<SyncableTodoItem>(allItems, deviceId);
      final listsToSync =
          _filterSyncableData<SyncableTodoList>(allLists, deviceId);

      // 如果没有需要同步的数据，跳过
      if (itemsToSync.isEmpty && listsToSync.isEmpty) {
        print('ℹ️  [SyncService] 没有需要同步的待办数据');
        return;
      }

      // 构建同步数据
      final syncData = {
        'items': itemsToSync.map((item) => item.toJson()).toList(),
        'lists': listsToSync.map((list) => list.toJson()).toList(),
      };

      // 🆕 压缩数据（如果数据量大）
      final dataSize = SyncCompression.estimateJsonSize(syncData);
      final envelope = dataSize > SyncCompression.compressionThreshold
          ? SyncCompression.compressJson(syncData)
          : {'compressed': false, 'data': syncData};

      // 发送数据
      final message = SyncMessage.dataUpdate(
        _currentDevice!.deviceId,
        'todos',
        envelope,
      );
      _sendMessageToDevice(deviceId, message);

      final totalCount = itemsToSync.length + listsToSync.length;
      print(
          '✅ [SyncService] 已发送 ${itemsToSync.length} 个待办事项和 ${listsToSync.length} 个列表 (共 $totalCount 项)');
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

      // 解析为 SyncableTimeLog 对象
      final allLogs =
          logsData.map((json) => SyncableTimeLog.fromJson(json)).toList();

      // 根据同步模式过滤需要同步的数据
      final logsToSync =
          _filterSyncableData<SyncableTimeLog>(allLogs, deviceId);

      // 如果没有需要同步的数据，跳过
      if (logsToSync.isEmpty) {
        print('ℹ️  [SyncService] 没有需要同步的时间日志');
        return;
      }

      // 转换回 JSON
      final syncData = logsToSync.map((log) => log.toJson()).toList();

      // 🆕 压缩数据
      final dataSize = SyncCompression.estimateJsonSize({'items': syncData});
      final envelope = dataSize > SyncCompression.compressionThreshold
          ? SyncCompression.compressBatch(syncData)
          : {'compressed': false, 'data': syncData};

      // 发送数据
      final message = SyncMessage.dataUpdate(
        _currentDevice!.deviceId,
        'timeLogs',
        envelope,
      );
      _sendMessageToDevice(deviceId, message);

      print('✅ [SyncService] 已发送 ${logsToSync.length} 个时间日志');
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

      // 解析为 SyncableTarget 对象
      final allTargets =
          targetsData.map((json) => SyncableTarget.fromJson(json)).toList();

      // 根据同步模式过滤需要同步的数据
      final targetsToSync =
          _filterSyncableData<SyncableTarget>(allTargets, deviceId);

      // 如果没有需要同步的数据，跳过
      if (targetsToSync.isEmpty) {
        print('ℹ️  [SyncService] 没有需要同步的目标');
        return;
      }

      // 转换回 JSON
      final syncData = targetsToSync.map((target) => target.toJson()).toList();

      // 发送数据
      final message = SyncMessage.dataUpdate(
        _currentDevice!.deviceId,
        'targets',
        syncData,
      );
      _sendMessageToDevice(deviceId, message);

      print('✅ [SyncService] 已发送 ${targetsToSync.length} 个目标');
    } catch (e) {
      print('❌ [SyncService] 同步目标失败: $e');
      rethrow;
    }
  }

  /// 处理接收到的待办事项数据
  Future<void> _handleTodosDataUpdate(
      Map<String, dynamic> remoteData, String fromDeviceId) async {
    print('🔄 [SyncService] 处理待办事项更新: 来自 $fromDeviceId');

    try {
      // 🆕 尝试解压数据
      Map<String, dynamic> actualData;
      if (remoteData.containsKey('compressed')) {
        final decompressed = SyncCompression.decompressJson(remoteData);
        if (decompressed == null) {
          _handleError(SyncError(
            type: SyncErrorType.dataCorrupted,
            message: '数据解压失败',
            details: '来源: $fromDeviceId',
          ));
          return;
        }
        actualData = decompressed;
      } else {
        actualData = remoteData;
      }

      int conflictCount = 0;
      int mergedItems = 0;
      int updatedItems = 0;

      // 获取本地数据和元数据
      final localTodos = await TodoStorage.getTodoItems();
      final localSyncMetadata = await TodoStorage.getSyncMetadata();
      bool hasChanges = false;

      // 处理待办项
      if (actualData['items'] != null) {
        final remoteItems = (actualData['items'] as List)
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
      dynamic remoteLogs, String fromDeviceId) async {
    print('🔄 [SyncService] 处理时间日志更新: 来自 $fromDeviceId');

    try {
      // 🆕 处理可能压缩的数据
      List<dynamic> actualLogs;
      if (remoteLogs is Map<String, dynamic> &&
          remoteLogs.containsKey('compressed')) {
        final decompressed = SyncCompression.decompressBatch(remoteLogs);
        if (decompressed == null) {
          _handleError(SyncError(
            type: SyncErrorType.dataCorrupted,
            message: '时间日志数据解压失败',
            details: '来源: $fromDeviceId',
          ));
          return;
        }
        actualLogs = decompressed;
      } else {
        actualLogs = remoteLogs as List<dynamic>;
      }

      final syncableLogs =
          actualLogs.map((json) => SyncableTimeLog.fromJson(json)).toList();

      print('📦 [SyncService] 收到 ${syncableLogs.length} 个时间日志');

      int mergedLogs = 0;

      // 获取本地所有记录
      final existingLogs =
          await TimeLoggerStorage.getAllRecords(forceRefresh: true);

      for (final remoteLog in syncableLogs) {
        try {
          // 🆕 改进的重复检测：使用时间窗口和内容匹配
          // 考虑到网络延迟，同一事件可能在±2秒内
          final exists = existingLogs.any((log) {
            final timeDiff = (log.startTime.millisecondsSinceEpoch -
                    remoteLog.startTime.millisecondsSinceEpoch)
                .abs();
            // 时间差在2秒内，且活动名称相同，视为同一记录
            return timeDiff < 2000 && log.name == remoteLog.name;
          });

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

  // ==================== 🆕 连接健康检查 ====================

  /// 启动连接健康检查
  void _startConnectionHealthCheck() {
    _stopConnectionHealthCheck(); // 确保没有重复的定时器

    print('🏥 [SyncService] 启动连接健康检查');
    _connectionHealthCheckTimer = Timer.periodic(_healthCheckInterval, (timer) {
      _performHealthCheck();
    });
  }

  /// 停止连接健康检查
  void _stopConnectionHealthCheck() {
    _connectionHealthCheckTimer?.cancel();
    _connectionHealthCheckTimer = null;
  }

  /// 启动内存清理
  void _startMemoryCleanup() {
    _stopMemoryCleanup(); // 确保没有重复的定时器

    print('🧹 [SyncService] 启动内存清理定时器');
    _memoryCleanupTimer = Timer.periodic(_memoryCleanupInterval, (timer) {
      _performMemoryCleanup();
    });
  }

  /// 停止内存清理
  void _stopMemoryCleanup() {
    _memoryCleanupTimer?.cancel();
    _memoryCleanupTimer = null;
  }

  /// 执行内存清理
  Future<void> _performMemoryCleanup() async {
    print('🧹 [SyncService] 执行内存清理...');

    final now = DateTime.now();
    int cleanedItems = 0;

    // 1. 清理过期的性能指标（保留最近N天）
    final expiredMetrics = <String>[];
    for (final entry in _performanceMetrics.entries) {
      final lastSyncTime = entry.value.lastSyncTime;
      if (lastSyncTime != null) {
        final age = now.difference(lastSyncTime).inDays;
        if (age > _maxPerformanceMetricsAge) {
          expiredMetrics.add(entry.key);
        }
      }
    }
    for (final deviceId in expiredMetrics) {
      _performanceMetrics.remove(deviceId);
      cleanedItems++;
    }
    if (expiredMetrics.isNotEmpty) {
      print('   清理了 ${expiredMetrics.length} 个过期性能指标');
    }

    // 2. 清理失败过多的同步任务
    if (_syncQueue.length > _maxSyncQueueSize) {
      final removedCount = _syncQueue.length - _maxSyncQueueSize;
      _syncQueue.removeRange(_maxSyncQueueSize, _syncQueue.length);
      cleanedItems += removedCount;
      print('   清理了 $removedCount 个积压的同步任务');
    }

    // 3. 清理过期的重试计数
    final expiredRetries = <String>[];
    for (final entry in _lastSyncAttempt.entries) {
      final age = now.difference(entry.value).inHours;
      if (age > 24) {
        // 24小时未活动
        expiredRetries.add(entry.key);
      }
    }
    for (final deviceId in expiredRetries) {
      _lastSyncAttempt.remove(deviceId);
      _syncRetryCount.remove(deviceId);
      cleanedItems++;
    }
    if (expiredRetries.isNotEmpty) {
      print('   清理了 ${expiredRetries.length} 个过期的重试记录');
    }

    // 4. 清理过期的同步时间记录
    final expiredSyncTimes = <String>[];
    for (final entry in _lastSyncTimes.entries) {
      final age = now.difference(entry.value).inDays;
      if (age > 30) {
        // 30天未同步
        expiredSyncTimes.add(entry.key);
      }
    }
    for (final deviceId in expiredSyncTimes) {
      _lastSyncTimes.remove(deviceId);
      cleanedItems++;
    }
    if (expiredSyncTimes.isNotEmpty) {
      print('   清理了 ${expiredSyncTimes.length} 个过期的同步时间记录');
    }

    print('✅ [SyncService] 内存清理完成 (共清理 $cleanedItems 项)');
  }

  /// 执行健康检查
  Future<void> _performHealthCheck() async {
    print('🏥 [SyncService] 执行连接健康检查...');

    // 检查所有客户端连接
    final disconnectedClients = <String>[];
    for (final entry in _clientServices.entries) {
      if (!entry.value.isConnected) {
        disconnectedClients.add(entry.key);
        print('⚠️  [SyncService] 发现僵尸连接: ${entry.key}');
      }
    }

    // 清理僵尸连接
    for (final deviceId in disconnectedClients) {
      await _clientServices[deviceId]?.disconnect();
      _clientServices.remove(deviceId);
      _connectedDevicesMap.remove(deviceId);
      print('🧹 [SyncService] 清理僵尸连接: $deviceId');
    }

    if (disconnectedClients.isNotEmpty) {
      _notifyConnectedDevicesChanged();
    }

    // 🆕 清理超时的同步锁
    await _syncLock.cleanupTimeoutLocks();

    print('✅ [SyncService] 健康检查完成 (清理 ${disconnectedClients.length} 个连接)');
  }

  // ==================== 🆕 同步队列和重试机制 ====================

  /// 将同步任务加入队列
  void _enqueueSyncTask(String deviceId, String deviceName, String taskType) {
    final task = _SyncTask(
      deviceId: deviceId,
      deviceName: deviceName,
      taskType: taskType,
    );
    _syncQueue.add(task);
    print('📝 [SyncService] 同步任务已加入队列: $taskType -> $deviceName');

    // 触发队列处理
    _processSyncQueue();
  }

  /// 处理同步队列
  Future<void> _processSyncQueue() async {
    if (_isProcessingQueue || _syncQueue.isEmpty) {
      return;
    }

    _isProcessingQueue = true;
    print('🔄 [SyncService] 开始处理同步队列 (${_syncQueue.length} 个任务)');

    while (_syncQueue.isNotEmpty) {
      final task = _syncQueue.first;

      // 检查是否需要延迟重试
      if (task.retryCount > 0) {
        final delay = _calculateRetryDelay(task.retryCount);
        final lastAttempt = _lastSyncAttempt[task.deviceId];
        if (lastAttempt != null) {
          final timeSinceLastAttempt = DateTime.now().difference(lastAttempt);
          if (timeSinceLastAttempt < delay) {
            // 还不到重试时间，跳过
            print(
                '⏳ [SyncService] 任务 ${task.taskType} -> ${task.deviceName} 等待重试 (${delay.inSeconds - timeSinceLastAttempt.inSeconds}秒)');
            break;
          }
        }
      }

      // 检查是否超过最大重试次数
      if (task.retryCount >= _maxSyncRetries) {
        print(
            '❌ [SyncService] 任务 ${task.taskType} -> ${task.deviceName} 超过最大重试次数，放弃');
        _syncQueue.removeAt(0);
        _syncRetryCount.remove(task.deviceId);
        continue;
      }

      // 执行任务
      print(
          '🚀 [SyncService] 执行同步任务: ${task.taskType} -> ${task.deviceName} (尝试 ${task.retryCount + 1})');
      _lastSyncAttempt[task.deviceId] = DateTime.now();

      final startTime = DateTime.now();
      bool success = false;

      try {
        if (task.taskType == 'push') {
          success = await _syncAllDataToDeviceInternal(task.deviceId);
        } else if (task.taskType == 'pull') {
          success = await pullAllDataFromDevice(task.deviceId);
        }

        final duration = DateTime.now().difference(startTime);

        // 记录性能指标
        _recordSyncPerformance(task.deviceId, success, duration);

        if (success) {
          print(
              '✅ [SyncService] 任务完成: ${task.taskType} -> ${task.deviceName} (耗时: ${duration.inSeconds}秒)');
          _syncQueue.removeAt(0);
          _syncRetryCount.remove(task.deviceId);
        } else {
          // 失败，增加重试次数
          task.retryCount++;
          _syncRetryCount[task.deviceId] = task.retryCount;
          print(
              '⚠️  [SyncService] 任务失败，将重试: ${task.taskType} -> ${task.deviceName} (${task.retryCount}/$_maxSyncRetries)');
        }
      } catch (e) {
        task.retryCount++;
        _syncRetryCount[task.deviceId] = task.retryCount;
        print('❌ [SyncService] 任务异常: $e (${task.retryCount}/$_maxSyncRetries)');
      }

      // 如果队列还有任务，稍作延迟
      if (_syncQueue.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    _isProcessingQueue = false;
    print('✅ [SyncService] 同步队列处理完成');
  }

  /// 计算重试延迟（指数退避）
  Duration _calculateRetryDelay(int retryCount) {
    final delay =
        _minRetryDelay * (1 << (retryCount - 1)); // 2^(n-1) * minDelay
    return delay > _maxRetryDelay ? _maxRetryDelay : delay;
  }

  /// 记录同步性能
  void _recordSyncPerformance(String deviceId, bool success, Duration duration,
      {int dataSize = 0}) {
    var metrics = _performanceMetrics[deviceId];
    if (metrics == null) {
      metrics = _SyncPerformanceMetrics(deviceId);
      _performanceMetrics[deviceId] = metrics;
    }

    metrics.recordSync(
      success: success,
      duration: duration,
      dataSize: dataSize,
    );

    print('📊 [SyncService] 性能指标 [$deviceId]:');
    print('   成功率: ${(metrics.successRate * 100).toStringAsFixed(1)}%');
    print('   平均耗时: ${metrics.averageDuration.inSeconds}秒');
    print(
        '   总同步: ${metrics.totalSyncs} (成功: ${metrics.successfulSyncs}, 失败: ${metrics.failedSyncs})');
  }

  /// 获取设备同步性能指标
  _SyncPerformanceMetrics? getSyncPerformanceMetrics(String deviceId) {
    return _performanceMetrics[deviceId];
  }

  // ==================== 🆕 改进的同步方法 ====================

  /// 🆕 带队列和重试的同步方法
  Future<bool> syncAllDataToDeviceWithRetry(String deviceId) async {
    final device = _connectedDevicesMap[deviceId] ??
        _serverService.getConnectedDevice(deviceId);

    if (device == null) {
      print('❌ [SyncService] 设备未找到: $deviceId');
      return false;
    }

    _enqueueSyncTask(deviceId, device.deviceName, 'push');
    return true;
  }

  /// 🆕 带队列和重试的拉取方法
  Future<bool> pullAllDataFromDeviceWithRetry(String deviceId) async {
    final device = _connectedDevicesMap[deviceId] ??
        _serverService.getConnectedDevice(deviceId);

    if (device == null) {
      print('❌ [SyncService] 设备未找到: $deviceId');
      return false;
    }

    _enqueueSyncTask(deviceId, device.deviceName, 'pull');
    return true;
  }

  /// 释放资源
  void dispose() {
    print('🧹 [SyncService] 释放资源');

    // 停止所有定时器
    _connectionHealthCheckTimer?.cancel();
    _connectionHealthCheckTimer = null;
    _memoryCleanupTimer?.cancel();
    _memoryCleanupTimer = null;

    // 释放服务
    _discoveryService.dispose();
    _serverService.stop();

    // 释放所有客户端连接
    for (final client in _clientServices.values) {
      client.dispose();
    }
    _clientServices.clear();

    // 关闭所有StreamController
    _discoveredDevicesController.close();
    _connectedDevicesController.close();
    _activeTimersController.close();
    _dataUpdatedController.close();
    _errorController.close();
    _syncProgressController.close();

    // 清理缓存数据
    _connectedDevicesMap.clear();
    _activeTimers.clear();
    _syncQueue.clear();
    _syncRetryCount.clear();
    _lastSyncAttempt.clear();
    _lastSyncTimes.clear();
    _performanceMetrics.clear();

    print('✅ [SyncService] 资源释放完成');
  }
}

// ==================== 辅助类定义 ====================

/// 同步任务
class _SyncTask {
  final String deviceId;
  final String deviceName;
  final String taskType; // 'push' or 'pull'
  final DateTime createdAt;
  int retryCount;

  _SyncTask({
    required this.deviceId,
    required this.deviceName,
    required this.taskType,
    DateTime? createdAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        retryCount = 0;
}

/// 同步性能指标
class _SyncPerformanceMetrics {
  final String deviceId;
  int totalSyncs = 0;
  int successfulSyncs = 0;
  int failedSyncs = 0;
  Duration totalDuration = Duration.zero;
  int totalDataSize = 0; // bytes
  DateTime? lastSyncTime;
  Duration? lastSyncDuration;

  _SyncPerformanceMetrics(this.deviceId);

  double get successRate => totalSyncs > 0 ? successfulSyncs / totalSyncs : 0.0;
  Duration get averageDuration =>
      totalSyncs > 0 ? totalDuration ~/ totalSyncs : Duration.zero;

  void recordSync({
    required bool success,
    required Duration duration,
    int dataSize = 0,
  }) {
    totalSyncs++;
    if (success) {
      successfulSyncs++;
    } else {
      failedSyncs++;
    }
    totalDuration += duration;
    totalDataSize += dataSize;
    lastSyncTime = DateTime.now();
    lastSyncDuration = duration;
  }
}
