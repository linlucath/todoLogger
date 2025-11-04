import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/sync_models.dart';
import '../models/sync_data_models.dart';
import '../models/sync_error.dart';
import '../utils/sync_compression.dart';
import '../utils/sync_lock.dart';
import 'device_discovery_service.dart';
import 'sync_server_service.dart';
import 'sync_client_service.dart';
import 'git_style_merger.dart'; // 🆕 Git-style 合并器
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
  final GitStyleMerger _gitMerger = GitStyleMerger(
      conflictStrategy: ConflictStrategy.lastWrite); // 🆕 Git-style 合并器
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

  // 🆕 活动计时器更新定时器
  Timer? _activeTimersUpdateTimer;
  static const Duration _activeTimersUpdateInterval = Duration(seconds: 1);

  // 当前计时状态
  final Map<String, TimerState> _activeTimers = {};
  // 🆕 计时器Map的互斥标志，防止并发修改
  bool _isUpdatingActiveTimers = false;

  // 🆕 设备断连延迟移除（防止快速重连导致计时器丢失）
  final Map<String, Timer> _deviceDisconnectTimers = {};
  static const Duration _deviceRemovalDelay = Duration(seconds: 5);

  // 🆕 冲突解决锁（防止并发冲突解决）
  bool _isResolvingConflicts = false;

  // 🆕 同步会话跟踪（防止循环同步）
  final Set<String> _processedSyncSessions = {};
  static const int _maxSyncSessionsToTrack = 100; // 最多跟踪100个会话
  String? _currentOutgoingSyncSession; // 当前发起的同步会话ID

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

    // 🆕 加载本地活动计时器
    await _loadLocalActiveTimer();

    // 🆕 启动活动计时器更新
    _startActiveTimersUpdate();
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

    // 🆕 停止活动计时器更新
    _stopActiveTimersUpdate();

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
    if (_isServerRunning || _currentDevice == null) {
      print('⚠️  [SyncService] 无法启动服务器');
      print('   _isServerRunning: $_isServerRunning');
      print('   _currentDevice: ${_currentDevice?.deviceName ?? "null"}');
      return;
    }

    print('🌐 [SyncService] 启动服务器');
    print('   当前设备: ${_currentDevice!.deviceName}');
    print('   端口: ${_currentDevice!.port}');

    final success = await _serverService.start(_currentDevice!);
    if (success) {
      _isServerRunning = true;
      print('✅ [SyncService] 服务器启动成功');

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
      print('🔧 [SyncService] 设置服务器回调函数');
      _serverService.onMessageReceived = _handleServerMessage;
      _serverService.onDeviceConnected = _handleDeviceConnected;
      _serverService.onDeviceDisconnected = _handleDeviceDisconnected;
      print('✅ [SyncService] 服务器回调设置完成');
    } else {
      print('❌ [SyncService] 服务器启动失败');
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

  // ==================== 计时器同步 Step 3: 接收并路由消息 ====================

  /// 处理服务器收到的消息
  ///
  /// 当其他设备发送消息到本设备时，这个函数负责：
  /// 1. 验证消息来源（防止处理自己发送的消息）
  /// 2. 根据消息类型路由到对应的处理函数
  ///
  /// 对于计时器相关的消息类型：
  /// - timerStart: 其他设备启动了计时器
  /// - timerStop: 其他设备停止了计时器
  /// - timerUpdate: 其他设备的计时器时间更新
  /// - timerForceStop: 冲突解决时强制停止本地计时器
  void _handleServerMessage(SyncMessage message, String fromDeviceId) {
    print('📨 [SyncService] 处理消息: ${message.type} from $fromDeviceId');
    print('   senderId: ${message.senderId}');
    print('   currentDeviceId: ${_currentDevice?.deviceId}');

    // 🔍 关键检查：忽略来自自己的消息（防止广播回环）
    // 原因：当本设备广播消息时，如果本设备也运行着服务器，
    // 可能会收到自己发出的消息，需要过滤掉
    if (message.senderId != null &&
        message.senderId == _currentDevice?.deviceId) {
      print('⏭️  [SyncService] 忽略来自自己的消息 (广播回环)');
      return;
    }

    // === 消息路由：根据消息类型调用对应的处理函数 ===
    switch (message.type) {
      case SyncMessageType.dataRequest:
        _handleDataRequest(message, fromDeviceId);
        break;
      case SyncMessageType.dataUpdate:
        _handleDataUpdate(message);
        break;
      case SyncMessageType.timerStart:
        // 🎯 计时器启动消息 - 转到 _handleTimerStart 处理
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
    print('🤝 [SyncService] 设备已连接');
    print('   设备ID: $deviceId');
    print('   设备名: ${device.deviceName}');
    print('   设备IP: ${device.ipAddress}');
    print('   设备端口: ${device.port}');

    _connectedDevicesMap[deviceId] = device;
    print('   已连接设备总数: ${_connectedDevicesMap.length}');

    _notifyConnectedDevicesChanged();
    print('✅ [SyncService] 设备连接处理完成');

    // 🆕 设备连接后，立即同步当前计时器状态
    // 使用 Future.microtask 避免在回调中直接执行异步操作
    Future.microtask(() async {
      print('🔄 [SyncService] 检查并同步当前计时状态...');
      await _syncCurrentTimerState(deviceId);
    });
  }

  /// 处理设备断开
  void _handleDeviceDisconnected(String deviceId) {
    print('👋 [SyncService] 设备已断开: $deviceId');
    _connectedDevicesMap.remove(deviceId);
    _notifyConnectedDevicesChanged();

    // 🆕 延迟移除该设备的活动计时器（给重连留时间）
    if (_activeTimers.containsKey(deviceId)) {
      print(
          '⏳ [SyncService] 将在${_deviceRemovalDelay.inSeconds}秒后移除设备计时器: $deviceId');

      // 取消之前的延迟定时器（如果存在）
      _deviceDisconnectTimers[deviceId]?.cancel();

      // 创建新的延迟定时器
      _deviceDisconnectTimers[deviceId] = Timer(_deviceRemovalDelay, () {
        if (_activeTimers.containsKey(deviceId)) {
          _activeTimers.remove(deviceId);
          _notifyActiveTimersChanged();
          print('🗑️  [SyncService] 已清理长时间断连设备的计时器: $deviceId');
        }
        _deviceDisconnectTimers.remove(deviceId);
      });
    }
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
    print('📥 [SyncService] 开始处理数据更新消息');

    if (message.data == null) {
      print('⚠️  [SyncService] 数据更新消息缺少data字段');
      return;
    }

    final dataType = message.data!['dataType'];
    final updateData = message.data!['data'];

    print('📊 [SyncService] 数据类型: $dataType');
    print('📦 [SyncService] 数据大小: ${updateData.toString().length} 字符');

    if (dataType == null || dataType is! String) {
      print('⚠️  [SyncService] 数据更新消息dataType无效');
      return;
    }

    if (updateData == null || message.senderId == null) {
      print('⚠️  [SyncService] 数据更新消息缺少必要字段');
      return;
    }

    print('🔄 [SyncService] 处理数据更新: $dataType from ${message.senderId}');

    // 🆕 先解压数据（如果需要），然后再验证
    dynamic actualData = updateData;

    // 检查是否为压缩数据（todos 使用 compressJson 格式）
    if (dataType == 'todos' && updateData is Map<String, dynamic>) {
      if (updateData.containsKey('compressed')) {
        print('🔄 [SyncService] 检测到压缩数据，开始解压...');
        final decompressed = SyncCompression.decompressJson(updateData);
        if (decompressed == null) {
          print('❌ [SyncService] 数据解压失败');
          _handleError(SyncError(
            type: SyncErrorType.dataCorrupted,
            message: '数据解压失败',
            details: '数据类型: $dataType, 来源: ${message.senderId}',
            isRecoverable: false,
          ));
          return;
        }
        actualData = decompressed;
        print('✅ [SyncService] 数据解压成功');
      }
    }
    // 检查是否为压缩数据（timeLogs 使用 compressBatch 格式）
    else if (dataType == 'timeLogs' && updateData is Map<String, dynamic>) {
      if (updateData.containsKey('compressed')) {
        print('🔄 [SyncService] 检测到压缩数据，开始解压...');
        final decompressed = SyncCompression.decompressBatch(updateData);
        if (decompressed == null) {
          print('❌ [SyncService] 数据解压失败');
          _handleError(SyncError(
            type: SyncErrorType.dataCorrupted,
            message: '数据解压失败',
            details: '数据类型: $dataType, 来源: ${message.senderId}',
            isRecoverable: false,
          ));
          return;
        }
        actualData = decompressed;
        print('✅ [SyncService] 数据解压成功');
      }
    }
    // 🆕 检查是否为压缩数据（targets 使用 compressJson 格式，与todos一致）
    else if (dataType == 'targets' && updateData is Map<String, dynamic>) {
      if (updateData.containsKey('compressed')) {
        print('🔄 [SyncService] 检测到压缩数据，开始解压...');
        final decompressed = SyncCompression.decompressJson(updateData);
        if (decompressed == null) {
          print('❌ [SyncService] 目标数据解压失败');
          _handleError(SyncError(
            type: SyncErrorType.dataCorrupted,
            message: '目标数据解压失败',
            details: '数据类型: $dataType, 来源: ${message.senderId}',
            isRecoverable: false,
          ));
          return;
        }
        actualData = decompressed;
        print('✅ [SyncService] 目标数据解压成功');
      }
    }

    // 验证数据完整性（使用解压后的数据）
    if (!_validateSyncData(actualData, dataType)) {
      print('❌ [SyncService] 数据校验失败，拒绝更新');
      print('❌ [SyncService] 数据类型: $dataType');
      print(
          '❌ [SyncService] 数据内容: ${actualData.toString().substring(0, actualData.toString().length > 200 ? 200 : actualData.toString().length)}...');
      _handleError(SyncError(
        type: SyncErrorType.unknown,
        message: '接收到的数据格式不正确',
        details: '数据类型: $dataType, 来源: ${message.senderId}',
        isRecoverable: false,
      ));
      return;
    }

    print('✅ [SyncService] 数据验证通过: $dataType');

    // 🆕 检查同步会话ID，防止循环同步
    if (message.syncSessionId != null) {
      // 如果是我们自己发起的同步会话，忽略
      if (message.syncSessionId == _currentOutgoingSyncSession) {
        print('ℹ️  [SyncService] 忽略自己发起的同步会话: ${message.syncSessionId}');
        return;
      }

      // 如果已经处理过这个会话，忽略
      if (_processedSyncSessions.contains(message.syncSessionId!)) {
        print('ℹ️  [SyncService] 已处理过的同步会话: ${message.syncSessionId}');
        return;
      }

      // 记录这个会话
      _processedSyncSessions.add(message.syncSessionId!);

      // 限制跟踪的会话数量
      if (_processedSyncSessions.length > _maxSyncSessionsToTrack) {
        // 移除最旧的会话（简单实现：清空一半）
        final toRemove =
            _processedSyncSessions.take(_maxSyncSessionsToTrack ~/ 2).toList();
        _processedSyncSessions.removeAll(toRemove);
      }
    }

    // 根据数据类型处理更新（传递解压后的数据）
    print('🔀 [SyncService] 路由数据更新到处理器: $dataType');
    switch (dataType) {
      case 'todos':
        _handleTodosDataUpdate(actualData as Map<String, dynamic>,
            message.senderId!, message.syncSessionId);
        break;
      case 'timeLogs':
        _handleTimeLogsDataUpdate(
            actualData as List<dynamic>, message.senderId!);
        break;
      case 'targets':
        print('➡️  [SyncService] 调用 _handleTargetsDataUpdate');
        _handleTargetsDataUpdate(
            actualData, message.senderId!, message.syncSessionId);
        break;
      default:
        print('⚠️  [SyncService] 未知数据类型: $dataType');
    }
  }

  // ==================== 计时器同步 Step 4: 处理接收到的计时开始消息 ====================

  /// 处理计时开始消息
  ///
  /// 当收到其他设备发送的计时开始消息时：
  /// 处理计时开始消息
  Future<void> _handleTimerStart(SyncMessage message) async {
    // 验证消息
    if (message.data == null || message.senderId == null) {
      print('⚠️  [SyncService] 计时开始消息无效');
      return;
    }

    // 防止处理自己发送的消息
    if (message.senderId == _currentDevice?.deviceId) {
      print('⏭️  [SyncService] 忽略来自自己的计时开始消息');
      return;
    }

    // 提取数据
    final activityId = message.data!['activityId'] as String?;
    final activityName = message.data!['activityName'] as String?;
    final startTimeStr = message.data!['startTime'] as String?;
    final linkedTodoId = message.data!['linkedTodoId'] as String?;
    final linkedTodoTitle = message.data!['linkedTodoTitle'] as String?;

    if (activityId == null || activityName == null || startTimeStr == null) {
      print('⚠️  [SyncService] 计时开始消息缺少必要字段');
      print('   activityId: $activityId');
      print('   activityName: $activityName');
      print('   startTime: $startTimeStr');
      return;
    }

    print('📥 [SyncService] 收到计时开始消息');
    print('   发送者设备: ${message.senderId}');
    print('   activityId: $activityId');
    print('   activityName: $activityName');
    print('   startTime: $startTimeStr');

    final startTime = DateTime.parse(startTimeStr);

    // 🆕 检查该设备是否已有活动计时器
    final existingTimer = _activeTimers[message.senderId];
    if (existingTimer != null) {
      // 检查是否是同一个活动（可能是重新连接后的同步）
      if (existingTimer.activityId == activityId) {
        print('ℹ️  [SyncService] 该设备已有相同活动的计时器，更新状态');
        // 更新现有计时器（保留较早的开始时间）
        if (startTime.isBefore(existingTimer.startTime)) {
          print('   使用更早的开始时间: $startTime (旧: ${existingTimer.startTime})');
          _activeTimers[message.senderId!] = existingTimer.copyWith(
            startTime: startTime,
            currentDuration: DateTime.now().difference(startTime).inSeconds,
          );
        } else {
          print('   保持现有开始时间: ${existingTimer.startTime}');
        }
        _notifyActiveTimersChanged();
        return;
      } else {
        print('⚠️  [SyncService] 该设备有不同的活动在运行');
        print('   现有activityId: ${existingTimer.activityId}');
        print('   新的activityId: $activityId');
        print('   将覆盖为新活动（旧活动可能已在其设备上结束）');
      }
    }

    // 获取发送者设备信息
    DeviceInfo? senderDevice =
        _serverService.getConnectedDevice(message.senderId!);

    senderDevice ??= _connectedDevicesMap[message.senderId!];

    if (senderDevice == null) {
      final client = _clientServices[message.senderId!];
      if (client != null) {
        senderDevice = client.remoteDevice;
      }
    }

    final deviceName = senderDevice?.deviceName ??
        'Device-${message.senderId!.substring(0, 8)}';

    // 创建计时器状态
    final timerState = TimerState(
      activityId: activityId,
      activityName: activityName,
      linkedTodoId: linkedTodoId,
      linkedTodoTitle: linkedTodoTitle,
      startTime: startTime,
      currentDuration: 0,
      deviceId: message.senderId!,
      deviceName: deviceName,
    );

    // 🔒 安全地添加计时器
    // 取消该设备的延迟移除定时器（如果存在）
    _deviceDisconnectTimers[message.senderId!]?.cancel();
    _deviceDisconnectTimers.remove(message.senderId!);

    // 添加到活动计时器列表
    _activeTimers[message.senderId!] = timerState;

    _notifyActiveTimersChanged();

    print('⏱️  [SyncService] 计时开始: ${timerState.activityName} on $deviceName');
    print('   activityId: $activityId');
    print('   开始时间: $startTime');
    print('   活动计时器总数: ${_activeTimers.length}');
  }

  /// 处理计时停止
  Future<void> _handleTimerStop(SyncMessage message) async {
    if (message.senderId == null || message.data == null) {
      print('⚠️  [SyncService] 计时停止消息无效: 缺少senderId或data');
      return;
    }

    final activityId = message.data!['activityId'] as String?;
    final duration = message.data!['duration'] as int?;

    if (activityId == null) {
      print('⚠️  [SyncService] 计时停止消息无效: 缺少activityId');
      return;
    }

    print('📥 [SyncService] 收到计时停止消息');
    print('   发送者: ${message.senderId}');
    print('   activityId: $activityId');
    print('   持续时间: $duration秒');

    // 🔒 查找并验证计时器
    final existingTimer = _activeTimers[message.senderId!];
    if (existingTimer != null) {
      // 验证activityId是否匹配
      if (existingTimer.activityId != activityId) {
        print('⚠️  [SyncService] 计时器ID不匹配!');
        print('   期望的activityId: ${existingTimer.activityId}');
        print('   收到的activityId: $activityId');
        print('   请求完整状态重新同步...');

        // ID不匹配时，请求该设备的完整计时器状态
        await _syncCurrentTimerState(message.senderId!);
        return;
      } else {
        print('✅ [SyncService] activityId 匹配验证通过');
      }

      print('⏹️  [SyncService] 计时停止: ${existingTimer.activityName}');
      if (duration != null) {
        print('   持续时间: $duration秒 (${(duration / 60).toStringAsFixed(1)}分钟)');
      }
    } else {
      print('⚠️  [SyncService] 计时停止: 未找到设备 ${message.senderId} 的活动计时器');
      print('   这可能意味着计时器已经被停止或从未启动');
    }

    // 移除计时器
    _activeTimers.remove(message.senderId);

    _notifyActiveTimersChanged();
  }

  /// 处理计时更新
  Future<void> _handleTimerUpdate(SyncMessage message) async {
    if (message.data == null || message.senderId == null) return;

    final activityId = message.data!['activityId'] as String?;
    final currentDuration = message.data!['currentDuration'] as int?;

    if (activityId == null || currentDuration == null) {
      print('⚠️  [SyncService] 计时更新消息无效: 缺少activityId或currentDuration');
      return;
    }

    print('📥 [SyncService] 收到计时更新: from ${message.senderId}');
    print('   activityId: $activityId');
    print('   currentDuration: $currentDuration 秒');

    // 🔒 查找并验证计时器
    final existingTimer = _activeTimers[message.senderId];
    if (existingTimer != null) {
      // 验证activityId是否匹配
      if (existingTimer.activityId != activityId) {
        print(
            '⚠️  [SyncService] 计时更新ID不匹配: 期望${existingTimer.activityId}, 收到$activityId');
        // ID不匹配时，请求该设备的完整计时器状态
        await _syncCurrentTimerState(message.senderId!);
        return;
      }

      _activeTimers[message.senderId!] =
          existingTimer.copyWith(currentDuration: currentDuration);
      print(
          '✅ [SyncService] 更新计时器时长: ${existingTimer.activityName} -> $currentDuration 秒');
    } else {
      // 🆕 关键修复：如果计时器不存在，主动请求完整状态而不是静默失败
      print('⚠️  [SyncService] 未找到计时器 (设备: ${message.senderId})');
      print('   尝试重新同步计时器状态...');
      await _syncCurrentTimerState(message.senderId!);
      return;
    }

    _notifyActiveTimersChanged();
  }

  /// 处理强制停止计时（冲突解决）
  Future<void> _handleTimerForceStop(SyncMessage message) async {
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

      // 🆕 通知计时器页面刷新（本地活动已被强制停止）
      _notifyDataUpdated('timeLogs', message.senderId ?? 'unknown', 1);
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

    // 🆕 添加已删除但尚未同步的待办项（只在 syncMetadata 中存在且标记为已删除）
    for (var entry in syncMetadata.entries) {
      final itemId = entry.key;
      final metadata = entry.value;

      // 跳过列表的元数据（以 'list_' 开头）
      if (itemId.startsWith('list_')) continue;

      // 如果标记为已删除且不在当前 todoItems 中，添加一个占位项用于同步删除
      if (metadata.isDeleted && !todoItems.containsKey(itemId)) {
        syncableItems.add(SyncableTodoItem(
          id: itemId,
          title: '[已删除]', // 占位标题
          description: null,
          isCompleted: false,
          createdAt: metadata.lastModifiedAt,
          listId: null,
          syncMetadata: metadata,
        ));
        print('🗑️ [SyncService] 包含已删除的待办项用于同步: $itemId');
      }
    }

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

    // 🆕 添加已删除但尚未同步的待办列表
    final existingListIds = todoLists.map((list) => list.id).toSet();
    for (var entry in syncMetadata.entries) {
      final metadataId = entry.key;
      final metadata = entry.value;

      // 只处理列表的元数据（以 'list_' 开头）
      if (!metadataId.startsWith('list_')) continue;

      final listId = metadataId.substring(5); // 移除 'list_' 前缀

      // 如果标记为已删除且不在当前 todoLists 中，添加一个占位列表用于同步删除
      if (metadata.isDeleted && !existingListIds.contains(listId)) {
        syncableLists.add(SyncableTodoList(
          id: listId,
          name: '[已删除]', // 占位名称
          isExpanded: false,
          colorValue: 0xFF2196F3,
          itemIds: [],
          syncMetadata: metadata,
        ));
        print('🗑️ [SyncService] 包含已删除的待办列表用于同步: $listId');
      }
    }

    return {
      'items': syncableItems.map((item) => item.toJson()).toList(),
      'lists': syncableLists.map((list) => list.toJson()).toList(),
    };
  }

  /// 获取时间日志数据（包括正在进行的活动）
  Future<List<Map<String, dynamic>>> _getTimeLogsData() async {
    print('📊 [SyncService] 获取时间日志数据...');

    final logs = await TimeLoggerStorage.getAllRecords();
    print('   已完成的记录数: ${logs.length}');

    // 🆕 获取当前正在进行的活动
    final currentActivity = await TimeLoggerStorage.getCurrentActivity();
    print('   当前活动: ${currentActivity?.name ?? "无"}');

    if (currentActivity != null) {
      print('   活动详情:');
      print('     - name: ${currentActivity.name}');
      print('     - startTime: ${currentActivity.startTime}');
      print('     - linkedTodoId: ${currentActivity.linkedTodoId}');
      print('     - linkedTodoTitle: ${currentActivity.linkedTodoTitle}');
    }

    // 合并已完成的记录和正在进行的活动
    final allActivities = <ActivityRecordData>[...logs];
    if (currentActivity != null) {
      // 检查是否已经在记录列表中（避免重复）
      final isDuplicate = logs.any((log) {
        final timeDiff = (log.startTime.millisecondsSinceEpoch -
                currentActivity.startTime.millisecondsSinceEpoch)
            .abs();
        return timeDiff < 1000 && log.name == currentActivity.name;
      });

      if (!isDuplicate) {
        allActivities.add(currentActivity);
        print('✅ [SyncService] 包含正在进行的活动: ${currentActivity.name}');
      } else {
        print('⚠️  [SyncService] 当前活动已在记录中，跳过');
      }
    }

    print('   总共准备发送: ${allActivities.length} 条时间日志');

    // 将 ActivityRecordData 转换为 SyncableTimeLog
    final syncableLogs = allActivities.map((log) {
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
        activityId: log.activityId, // 🆕 使用ActivityRecordData中的activityId
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
    print('📊 [SyncService] 开始获取目标数据...');
    final storage = TargetStorage();
    final targets = await storage.loadTargets();
    final syncMetadata = await TodoStorage.getSyncMetadata();
    print('📂 [SyncService] 加载了 ${targets.length} 个目标');

    // 将 Target 转换为 SyncableTarget
    final syncableTargets = targets.map((target) {
      // 获取或创建同步元数据
      final targetMetadataId = 'target_${target.id}';
      final metadata = syncMetadata[targetMetadataId] ??
          SyncMetadata.create(_currentDevice?.deviceId ?? 'unknown');

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

    // 🆕 添加已删除但尚未同步的目标（只在 syncMetadata 中存在且标记为已删除）
    final existingTargetIds = targets.map((t) => t.id).toSet();
    for (var entry in syncMetadata.entries) {
      final metadataId = entry.key;
      final metadata = entry.value;

      // 只处理目标的元数据（以 'target_' 开头）
      if (!metadataId.startsWith('target_')) continue;

      final targetId = metadataId.substring(7); // 移除 'target_' 前缀

      // 如果标记为已删除且不在当前 targets 中，添加一个占位目标用于同步删除
      if (metadata.isDeleted && !existingTargetIds.contains(targetId)) {
        syncableTargets.add(SyncableTarget(
          id: targetId,
          name: '[已删除]', // 占位名称
          type: 0, // TargetType.achievement
          period: 0, // TimePeriod.daily
          targetSeconds: 0,
          linkedTodoIds: [],
          linkedListIds: [],
          createdAt: metadata.lastModifiedAt,
          isActive: false,
          colorValue: 0xFF2196F3,
          syncMetadata: metadata,
        ));
        print('🗑️ [SyncService] 包含已删除的目标用于同步: $targetId');
      }
    }

    print('✅ [SyncService] 目标数据准备完成: ${syncableTargets.length} 个（包含已删除）');
    return syncableTargets.map((target) => target.toJson()).toList();
  }

  /// 通知已连接设备变化
  void _notifyConnectedDevicesChanged() {
    if (!_connectedDevicesController.isClosed) {
      _connectedDevicesController.add(connectedDevices);
    }
  }

  // ==================== 计时器同步 Step 5: 通知 UI 更新 ====================

  /// 通知活动计时器变化
  ///
  /// 这是连接数据层和UI层的关键函数
  /// 工作流程：
  /// 1. 从 _activeTimers Map 获取所有活动计时器
  /// 2. 打印日志（用于调试）
  /// 3. 通过 _activeTimersController 发送事件
  /// 4. UI 中的 StreamBuilder 监听 activeTimersStream 会收到更新
  ///
  /// 为什么使用 Stream？
  /// - Stream 是 Flutter 中的响应式数据流
  /// - StreamBuilder 会自动监听数据变化并重建 UI
  /// - 这样实现了数据和 UI 的解耦
  void _notifyActiveTimersChanged() {
    // 获取当前所有活动计时器的列表
    // activeTimers getter 返回 _activeTimers.values.toList()
    final timers = activeTimers;

    print('📢 [SyncService] 通知活动计时器变化, 当前 ${timers.length} 个活动计时器');
    print('   当前设备ID: ${_currentDevice?.deviceId}');

    // 打印每个计时器的详细信息（用于调试）
    for (final timer in timers) {
      print(
          '   - ${timer.activityName} (设备: ${timer.deviceName}, ID: ${timer.deviceId}): ${timer.currentDuration}s');
    }

    // 🎯 关键：通过 StreamController 发送新事件
    // 这会触发所有监听 activeTimersStream 的 StreamBuilder 重建
    if (!_activeTimersController.isClosed) {
      _activeTimersController.add(timers);
      print('✅ [SyncService] 活动计时器已通过Stream发送到UI');
      print('   发送的计时器数量: ${timers.length}');
      print('   Stream 有监听者吗: ${_activeTimersController.hasListener}');
    } else {
      print('⚠️  [SyncService] 活动计时器控制器已关闭');
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
          // 验证目标数据（与todos保持一致的结构）
          if (data is Map<String, dynamic> && data.containsKey('items')) {
            // 新格式：{items: [...]}
            final items = data['items'];
            if (items is! List) {
              print('❌ [SyncService] 目标数据items类型错误: ${items.runtimeType}');
              return false;
            }
            for (var i = 0; i < items.length; i++) {
              final target = items[i];
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
              if (!target.containsKey('syncMetadata')) {
                print('❌ [SyncService] 目标[$i]缺少syncMetadata');
                return false;
              }
            }
            print('✅ [SyncService] 目标数据验证通过: ${items.length}个');
            return true;
          } else if (data is List) {
            // 兼容旧格式：直接是列表
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
            print('✅ [SyncService] 目标数据验证通过 (旧格式): ${data.length}个');
            return true;
          } else {
            print('❌ [SyncService] 目标数据格式错误: ${data.runtimeType}');
            return false;
          }

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
      print('❌ [SyncService] 无法连接: 当前设备信息未初始化');
      _handleError(SyncError(
        type: SyncErrorType.unknown,
        message: '当前设备信息未初始化',
        isRecoverable: false,
      ));
      return false;
    }

    print('🔗 [SyncService] 开始连接到设备');
    print('   目标设备名: ${device.deviceName}');
    print('   目标设备ID: ${device.deviceId}');
    print('   目标设备IP: "${device.ipAddress}"');
    print('   目标设备端口: ${device.port}');
    print('   当前设备名: ${_currentDevice!.deviceName}');

    // 验证IP地址不为空
    if (device.ipAddress.isEmpty) {
      print('❌ [SyncService] IP地址为空，无法连接');
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
        print('📞 [SyncService] 创建客户端连接...');
        // 创建客户端服务
        final client = SyncClientService();
        final success = await client.connect(_currentDevice!, device);

        if (success) {
          print('✅ [SyncService] 连接成功，保存客户端服务');
          _clientServices[device.deviceId] = client;

          // 将设备添加到已连接设备列表
          _connectedDevicesMap[device.deviceId] = device;
          print('   已连接设备总数: ${_connectedDevicesMap.length}');
          _notifyConnectedDevicesChanged();

          // 设置回调
          print('🔧 [SyncService] 设置客户端回调函数');
          client.onMessageReceived = _handleClientMessage;
          client.onDisconnected = () {
            _clientServices.remove(device.deviceId);
            _connectedDevicesMap.remove(device.deviceId);
            _notifyConnectedDevicesChanged();
          };

          print('✅ [SyncService] 成功连接到: ${device.deviceName}');

          // 🆕 连接成功后，立即检查并传递当前正在进行的计时信息
          print('🔄 [SyncService] 检查当前计时状态...');
          await _syncCurrentTimerState(device.deviceId);

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

  // ==================== 计时器同步 Step 2: 广播计时开始消息 ====================

  /// 广播计时开始
  ///
  /// 这是计时器同步的核心函数，负责将本地计时器启动事件通知所有已连接设备
  ///
  /// 工作原理：
  /// 1. 创建包含计时信息的 SyncMessage
  /// 2. 通过两种渠道发送消息：
  ///    a) 服务器广播：发送给所有连接到本设备的客户端（本设备作为服务器）
  ///    b) 客户端发送：发送给本设备连接到的所有服务器（本设备作为客户端）
  /// 3. 这样确保了双向通信，无论哪个设备是服务器/客户端都能收到消息
  void broadcastTimerStart(String activityId, String activityName,
      DateTime startTime, String? todoId, String? todoTitle) {
    if (_currentDevice == null) {
      print('⚠️  [SyncService] 无法广播计时开始：当前设备未初始化');
      return;
    }

    print('📤 [SyncService] 广播计时开始');
    print('   activityId: $activityId');
    print('   activityName: $activityName');
    print('   开始时间: $startTime');

    final message = SyncMessage.timerStart(
      deviceId: _currentDevice!.deviceId,
      activityId: activityId,
      activityName: activityName,
      startTime: startTime,
      linkedTodoId: todoId,
      linkedTodoTitle: todoTitle,
    );

    int sentCount = 0;

    // 通过服务器广播
    if (_isServerRunning) {
      _serverService.broadcastMessage(message);
      sentCount++;
      print('   ✓ 通过服务器广播');
    }

    // 通过客户端发送
    for (final client in _clientServices.values) {
      if (client.isConnected) {
        client.sendMessage(message);
        sentCount++;
      }
    }

    print('   已发送到 $sentCount 个连接');
  }

  /// 广播计时停止
  void broadcastTimerStop(
      String activityId, DateTime startTime, DateTime endTime, int duration) {
    if (_currentDevice == null) {
      print('⚠️  [SyncService] 无法广播计时停止：当前设备未初始化');
      return;
    }

    print('📤 [SyncService] 广播计时停止');
    print('   activityId: $activityId');
    print('   持续时间: $duration秒');

    final message = SyncMessage.timerStop(
      deviceId: _currentDevice!.deviceId,
      activityId: activityId,
      startTime: startTime,
      endTime: endTime,
      duration: duration,
    );

    int sentCount = 0;

    // 通过服务器广播
    if (_isServerRunning) {
      _serverService.broadcastMessage(message);
      sentCount++;
    }

    // 通过客户端发送
    for (final client in _clientServices.values) {
      if (client.isConnected) {
        client.sendMessage(message);
        sentCount++;
      }
    }

    print('   已发送到 $sentCount 个连接');
  }

  /// 广播计时更新
  void broadcastTimerUpdate(String activityId, int currentDuration) {
    if (_currentDevice == null) return;

    final message = SyncMessage.timerUpdate(
      deviceId: _currentDevice!.deviceId,
      activityId: activityId,
      currentDuration: currentDuration,
    );

    // 通过服务器广播
    if (_isServerRunning) {
      _serverService.broadcastMessage(message);
    }

    // 通过客户端发送
    for (final client in _clientServices.values) {
      if (client.isConnected) {
        client.sendMessage(message);
      }
    }
  }

  // ==================== 数据同步功能 ====================

  /// 全量同步所有数据到指定设备
  Future<bool> syncAllDataToDevice(String deviceId) async {
    print('🔘 [SyncService] syncAllDataToDevice 调用，强制全量同步模式');

    // 🆕 用户点击同步按钮时，强制使用全量同步模式
    final originalMode = _syncMode;
    _syncMode = SyncMode.full;

    // 🆕 使用同步锁防止并发
    final acquired = await _syncLock.acquire(deviceId, 'syncAllDataToDevice');
    if (!acquired) {
      _syncMode = originalMode; // 恢复原模式
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
      _syncMode = originalMode; // 恢复原模式
      print('ℹ️  [SyncService] 同步完成，恢复同步模式: $originalMode');
    }
  }

  /// 内部同步方法（不包含锁检查）
  Future<bool> _syncAllDataToDeviceInternal(String deviceId) async {
    print('🚀 [SyncService] _syncAllDataToDeviceInternal 开始');
    print('   目标设备ID: $deviceId');
    print('   当前设备: ${_currentDevice?.deviceName ?? "未初始化"}');

    if (_currentDevice == null) {
      print('❌ [SyncService] 当前设备未初始化');
      _handleError(SyncError(
        type: SyncErrorType.unknown,
        message: '设备信息未初始化',
        isRecoverable: false,
      ));
      return false;
    }

    // 检查设备是否已连接（服务器端连接）
    DeviceInfo? device = _serverService.getConnectedDevice(deviceId);
    print('   从 _serverService 查找设备: ${device != null ? "找到" : "未找到"}');

    // 如果不是服务器端连接，检查是否为客户端连接
    device ??= _connectedDevicesMap[deviceId];
    print('   从 _connectedDevicesMap 查找设备: ${device != null ? "找到" : "未找到"}');

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

      // 🆕 同步当前计时器状态 (15%)
      _notifySyncProgress(SyncProgressEvent(
        deviceId: deviceId,
        deviceName: device.deviceName,
        phase: 'syncing',
        dataType: 'timers',
        progress: 0.15,
        message: '正在同步计时器状态...',
      ));
      await _syncCurrentTimerState(deviceId);

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
      print('🎯 [SyncService] 开始同步目标...');
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
      print('📊 [SyncService] 准备发送 $targetsCount 个目标');

      _notifySyncProgress(SyncProgressEvent(
        deviceId: deviceId,
        deviceName: device.deviceName,
        phase: 'syncing',
        dataType: 'targets',
        progress: 0.85,
        message: '正在发送 $targetsCount 个目标...',
      ));
      await _syncTargetsToDevice(deviceId);
      print('✅ [SyncService] 目标同步完成');

      // 完成 (100%)
      _notifySyncProgress(SyncProgressEvent(
        deviceId: deviceId,
        deviceName: device.deviceName,
        phase: 'completed',
        dataType: 'all',
        progress: 1.0,
        message: '同步完成！',
      ));

      // 🆕 清理已成功同步的删除标记
      await _cleanupDeletedItemsMetadata();

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
      // 🆕 首先请求当前计时器状态
      // 注意：虽然连接时会自动同步计时器，但显式请求可确保最新状态
      print('⏱️  [SyncService] 请求计时器状态...');
      // 发送 dataRequest 为 'currentTimer' (需要服务端支持)
      // 或直接等待自动同步（设备连接时已触发）

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
        description: '请求全量数据 (包含待办、日志、目标、计时器)',
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
  /// 检查所有设备的计时器，如果存在多个活动，保留最新开始的，结束其他
  Future<void> _resolveActiveTimerConflicts(String? triggerDeviceId) async {
    // 🔒 防止并发执行冲突解决
    if (_isResolvingConflicts) {
      print('⏭️  [SyncService] 冲突解决正在进行中，跳过本次调用');
      return;
    }

    _isResolvingConflicts = true;

    try {
      await _doResolveActiveTimerConflicts(triggerDeviceId);
    } finally {
      _isResolvingConflicts = false;
    }
  }

  /// 执行实际的冲突解决逻辑
  Future<void> _doResolveActiveTimerConflicts(String? triggerDeviceId) async {
    print('🔍 [SyncService] 检测活动计时冲突...');

    try {
      // 1. 获取本地当前活动
      final localActivity = await TimeLoggerStorage.getCurrentActivity();

      // 2. 收集所有正在进行的活动
      final activeActivities = <_ActiveActivity>[];

      // 添加本地活动
      if (localActivity != null) {
        activeActivities.add(_ActiveActivity(
          deviceId: _currentDevice?.deviceId ?? 'local',
          deviceName: _currentDevice?.deviceName ?? '本地设备',
          activity: localActivity,
          isLocal: true,
        ));
        print(
            '📍 [SyncService] 本地活动: ${localActivity.name} (开始: ${localActivity.startTime})');
      }

      // 添加所有远程活动
      for (final entry in _activeTimers.entries) {
        final deviceId = entry.key;
        final timer = entry.value;

        // 跳过本地设备的计时器（已在上面添加）
        if (deviceId == _currentDevice?.deviceId) continue;

        final remoteActivity = ActivityRecordData(
          name: timer.activityName,
          startTime: timer.startTime,
          endTime: null,
          linkedTodoId: timer.linkedTodoId,
          linkedTodoTitle: timer.linkedTodoTitle,
        );
        activeActivities.add(_ActiveActivity(
          deviceId: deviceId,
          deviceName: timer.deviceName,
          activity: remoteActivity,
          isLocal: false,
        ));
        print(
            '📍 [SyncService] 远程活动: ${timer.activityName} (${timer.deviceName}, 开始: ${timer.startTime})');
      }

      // 3. 如果没有活动或只有一个活动，无需处理
      if (activeActivities.isEmpty) {
        print('✅ [SyncService] 无活动冲突');
        return;
      }

      if (activeActivities.length == 1) {
        print('✅ [SyncService] 只有一个活动，无需冲突解决');
        // 确保单个活动被正确处理
        final single = activeActivities.first;

        if (single.isLocal) {
          // 本地活动，广播给其他设备（使用稳定的activityId）
          broadcastTimerStart(
            single.activity.activityId,
            single.activity.name,
            single.activity.startTime,
            single.activity.linkedTodoId,
            single.activity.linkedTodoTitle,
          );
        } else {
          // 远程活动已存在于 _activeTimers 中，无需额外处理
          print('📥 [SyncService] 远程活动已存在: ${single.activity.name}');
        }
        return;
      }

      // 4. 存在多个活动，需要解决冲突
      print('⚠️  [SyncService] 检测到 ${activeActivities.length} 个正在进行的活动冲突');

      // 按开始时间排序，最新的在前
      activeActivities
          .sort((a, b) => b.activity.startTime.compareTo(a.activity.startTime));

      // 保留最新的活动（第一个）
      final newestActivity = activeActivities.first;
      print(
          '🏆 [SyncService] 保留最新活动: ${newestActivity.activity.name} (${newestActivity.deviceName})');

      // 结束其他所有活动
      for (int i = 1; i < activeActivities.length; i++) {
        final oldActivity = activeActivities[i];

        // 计算结束时间：使用较新活动的开始时间
        final endTime = activeActivities[i - 1].activity.startTime;

        print(
            '⏹️  [SyncService] 结束旧活动: ${oldActivity.activity.name} (${oldActivity.deviceName})');
        print('   开始时间: ${oldActivity.activity.startTime}');
        print('   结束时间: $endTime');

        if (oldActivity.isLocal) {
          // 结束本地活动
          await _endLocalActivity(oldActivity.activity, endTime);
        } else {
          // 发送消息给远程设备，请求结束其活动
          await _sendEndActivityRequest(oldActivity.deviceId, endTime);
        }
      }

      // 5. 确保最新活动被正确设置
      if (newestActivity.isLocal) {
        // 本地活动保持运行，广播给其他设备（使用稳定的activityId）
        broadcastTimerStart(
          newestActivity.activity.activityId,
          newestActivity.activity.name,
          newestActivity.activity.startTime,
          newestActivity.activity.linkedTodoId,
          newestActivity.activity.linkedTodoTitle,
        );
      } else {
        // 🆕 远程活动获胜，需要在本地设置并通知UI
        print('📥 [SyncService] 远程活动获胜，设置为本地当前活动');

        // 将远程活动保存为本地当前活动
        await TimeLoggerStorage.saveCurrentActivity(ActivityRecordData(
          activityId: newestActivity.activity.activityId,
          name: newestActivity.activity.name,
          startTime: newestActivity.activity.startTime,
          endTime: null,
          linkedTodoId: newestActivity.activity.linkedTodoId,
          linkedTodoTitle: newestActivity.activity.linkedTodoTitle,
        ));
        print('💾 [SyncService] 远程活动已保存为本地当前活动');

        // 🔑 关键修复：确保远程活动在 _activeTimers 中（如果不存在则添加）
        if (!_activeTimers.containsKey(newestActivity.deviceId)) {
          final timerState = TimerState(
            activityId: newestActivity.activity.activityId,
            activityName: newestActivity.activity.name,
            linkedTodoId: newestActivity.activity.linkedTodoId,
            linkedTodoTitle: newestActivity.activity.linkedTodoTitle,
            startTime: newestActivity.activity.startTime,
            currentDuration: DateTime.now()
                .difference(newestActivity.activity.startTime)
                .inSeconds,
            deviceId: newestActivity.deviceId,
            deviceName: newestActivity.deviceName,
          );
          _activeTimers[newestActivity.deviceId] = timerState;
          print('✅ [SyncService] 远程活动已添加到 _activeTimers');
        }

        // 🔑 关键修复：通知活动计时器变化，让UI显示远程活动
        _notifyActiveTimersChanged();
        print('📢 [SyncService] 已调用 _notifyActiveTimersChanged() 更新UI计时器显示');

        // 通知计时器页面刷新（显示远程活动）
        _notifyDataUpdated('timeLogs', newestActivity.deviceId, 1);
        print('📢 [SyncService] 已通知UI刷新以显示远程活动');
      }

      print(
          '✅ [SyncService] 冲突已解决: 保留1个活动，结束${activeActivities.length - 1}个活动');
    } catch (e) {
      print('❌ [SyncService] 解决活动冲突失败: $e');
      // 不抛出异常，继续同步其他数据
    }
  }

  /// 发送结束活动请求到远程设备
  Future<void> _sendEndActivityRequest(
      String deviceId, DateTime endTime) async {
    print('📤 [SyncService] 发送结束活动请求到设备: $deviceId');

    try {
      if (_currentDevice != null) {
        final message = SyncMessage(
          type: SyncMessageType.timerForceStop,
          senderId: _currentDevice!.deviceId,
          data: {
            'reason': 'activity_conflict',
            'newerActivityStartTime': endTime.toIso8601String(),
            'message': '检测到更新的活动，自动结束此活动',
          },
        );
        _sendMessageToDevice(deviceId, message);
        print('✅ [SyncService] 已发送强制停止消息');
      }

      // 从本地活动列表中移除
      _activeTimers.remove(deviceId);
      _notifyActiveTimersChanged();
    } catch (e) {
      print('❌ [SyncService] 发送结束活动请求失败: $e');
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

      // 🔑 从本地活动列表中移除（如果存在）
      final localDeviceId = _currentDevice?.deviceId;
      if (localDeviceId != null && _activeTimers.containsKey(localDeviceId)) {
        _activeTimers.remove(localDeviceId);
        print('🗑️  [SyncService] 从 _activeTimers 移除本地活动');
      }

      // 广播计时停止
      final duration =
          conflictTime.difference(localActivity.startTime).inSeconds;
      broadcastTimerStop(
        localActivity.activityId,
        localActivity.startTime,
        conflictTime,
        duration,
      );

      // 🆕 通知活动计时器变化（本地活动已结束）
      _notifyActiveTimersChanged();
      print('📢 [SyncService] 已调用 _notifyActiveTimersChanged() 更新UI计时器显示');

      // 🆕 通知计时器页面刷新（本地活动已结束）
      _notifyDataUpdated('timeLogs', _currentDevice?.deviceId ?? 'local', 1);
    } catch (e) {
      print('❌ [SyncService] 结束本地活动失败: $e');
      rethrow;
    }
  }

  /// 同步当前计时器状态到新连接的设备
  Future<void> _syncCurrentTimerState(String deviceId) async {
    print('⏱️  [SyncService] 同步当前计时器状态到: $deviceId');

    try {
      // 获取本地当前活动
      final localActivity = await TimeLoggerStorage.getCurrentActivity();

      if (localActivity != null) {
        print('📤 [SyncService] 发现本地正在进行的计时:');
        print('   活动ID: ${localActivity.activityId}');
        print('   活动名称: ${localActivity.name}');
        print('   任务: ${localActivity.linkedTodoTitle ?? "无"}');
        print('   开始时间: ${localActivity.startTime}');

        // 发送计时开始消息给新连接的设备（使用稳定的activityId）
        final message = SyncMessage.timerStart(
          deviceId: _currentDevice!.deviceId,
          activityId: localActivity.activityId,
          activityName: localActivity.name,
          startTime: localActivity.startTime,
          linkedTodoId: localActivity.linkedTodoId,
          linkedTodoTitle: localActivity.linkedTodoTitle,
        );

        _sendMessageToDevice(deviceId, message);
        print(
            '✅ [SyncService] 已发送当前计时状态到新设备 (activityId: ${localActivity.activityId})');
      } else {
        print('ℹ️  [SyncService] 本地没有正在进行的计时');
      }
    } catch (e) {
      print('❌ [SyncService] 同步计时器状态失败: $e');
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

      // 🆕 生成同步会话ID
      _currentOutgoingSyncSession = const Uuid().v4();

      // 发送数据
      final message = SyncMessage.dataUpdate(
        _currentDevice!.deviceId,
        'todos',
        envelope,
        syncSessionId: _currentOutgoingSyncSession,
      );
      _sendMessageToDevice(deviceId, message);

      final totalCount = itemsToSync.length + listsToSync.length;
      print(
          '✅ [SyncService] 已发送 ${itemsToSync.length} 个待办事项和 ${listsToSync.length} 个列表 (共 $totalCount 项) [会话: $_currentOutgoingSyncSession]');
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
      print('📊 [SyncService] 获取到 ${targetsData.length} 个本地目标');

      // 解析为 SyncableTarget 对象
      final allTargets =
          targetsData.map((json) => SyncableTarget.fromJson(json)).toList();
      print('📦 [SyncService] 解析完成，准备过滤...');

      // 根据同步模式过滤需要同步的数据
      final targetsToSync =
          _filterSyncableData<SyncableTarget>(allTargets, deviceId);
      print('🔍 [SyncService] 过滤后剩余 ${targetsToSync.length} 个目标需要同步');

      // 如果没有需要同步的数据，跳过
      if (targetsToSync.isEmpty) {
        print('ℹ️  [SyncService] 没有需要同步的目标（本地有 ${allTargets.length} 个，但都已同步）');
        return;
      }

      // 构建同步数据（与todos保持一致的结构）
      final syncData = {
        'items': targetsToSync.map((target) => target.toJson()).toList(),
      };

      // 🆕 压缩数据（如果数据量大）
      final dataSize = SyncCompression.estimateJsonSize(syncData);
      final envelope = dataSize > SyncCompression.compressionThreshold
          ? SyncCompression.compressJson(syncData)
          : {'compressed': false, 'data': syncData};

      // 🆕 生成同步会话ID
      _currentOutgoingSyncSession = const Uuid().v4();

      // 发送数据
      final message = SyncMessage.dataUpdate(
        _currentDevice!.deviceId,
        'targets',
        envelope,
        syncSessionId: _currentOutgoingSyncSession,
      );
      _sendMessageToDevice(deviceId, message);

      print(
          '✅ [SyncService] 已发送 ${targetsToSync.length} 个目标 [会话: $_currentOutgoingSyncSession]');
    } catch (e) {
      print('❌ [SyncService] 同步目标失败: $e');
      rethrow;
    }
  }

  /// 🆕 清理已删除项的元数据（在同步成功后调用）
  /// 删除那些标记为已删除且已经同步到所有设备的项的元数据
  Future<void> _cleanupDeletedItemsMetadata() async {
    try {
      print('🧹 [SyncService] 开始清理已删除项的元数据...');

      final syncMetadata = await TodoStorage.getSyncMetadata();
      final todoItems = await TodoStorage.getTodoItems();
      final todoLists = await TodoStorage.getTodoLists();
      final existingListIds = todoLists.map((list) => list.id).toSet();

      // 🆕 获取目标数据
      final targetStorage = TargetStorage();
      final targets = await targetStorage.loadTargets();
      final existingTargetIds = targets.map((t) => t.id).toSet();

      int cleanedCount = 0;
      final keysToRemove = <String>[];

      for (var entry in syncMetadata.entries) {
        final metadataId = entry.key;
        final metadata = entry.value;

        // 只清理已删除的项
        if (!metadata.isDeleted) continue;

        // 对于待办项
        if (!metadataId.startsWith('list_') &&
            !metadataId.startsWith('target_')) {
          // 如果已删除且不在当前 todoItems 中，可以清理
          if (!todoItems.containsKey(metadataId)) {
            keysToRemove.add(metadataId);
            cleanedCount++;
          }
        }
        // 对于待办列表
        else if (metadataId.startsWith('list_')) {
          final listId = metadataId.substring(5); // 移除 'list_' 前缀
          // 如果已删除且不在当前 todoLists 中，可以清理
          if (!existingListIds.contains(listId)) {
            keysToRemove.add(metadataId);
            cleanedCount++;
          }
        }
        // 🆕 对于目标
        else if (metadataId.startsWith('target_')) {
          final targetId = metadataId.substring(7); // 移除 'target_' 前缀
          // 如果已删除且不在当前 targets 中，可以清理
          if (!existingTargetIds.contains(targetId)) {
            keysToRemove.add(metadataId);
            cleanedCount++;
          }
        }
      }

      // 批量删除
      if (keysToRemove.isNotEmpty) {
        for (var key in keysToRemove) {
          syncMetadata.remove(key);
        }
        await TodoStorage.saveSyncMetadata(syncMetadata);
        print('✅ [SyncService] 清理了 $cleanedCount 个已删除项的元数据');
      } else {
        print('ℹ️  [SyncService] 没有需要清理的元数据');
      }
    } catch (e) {
      print('⚠️  [SyncService] 清理元数据失败: $e');
      // 不抛出异常，清理失败不应影响同步流程
    }
  }

  /// 处理接收到的待办事项数据
  Future<void> _handleTodosDataUpdate(Map<String, dynamic> remoteData,
      String fromDeviceId, String? syncSessionId) async {
    print('🔄 [SyncService] 处理待办事项更新: 来自 $fromDeviceId [会话: $syncSessionId]');

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

            // 🆕 使用 Git-style 三方合并
            final mergeResult = _gitMerger.merge<SyncableTodoItem>(
              localSyncableItem,
              remoteItem,
              _currentDevice?.deviceId ?? 'unknown',
            );

            print(
                '🔀 [GitMerge] ${remoteItem.title}: ${mergeResult.mergeType} - ${mergeResult.description}');

            // 如果有冲突，记录
            if (mergeResult.hasConflict) {
              conflictCount++;
            }

            // 应用合并结果
            if (mergeResult.needsUpdate && mergeResult.mergedData != null) {
              final resolved = mergeResult.mergedData!;

              // 🆕 检查是否已删除
              if (resolved.syncMetadata.isDeleted) {
                // 如果标记为删除，从本地移除
                localTodos.remove(resolved.id);
                localSyncMetadata.remove(resolved.id);
                print('🗑️ [SyncService] 删除待办: ${resolved.title}');
                hasChanges = true;
              } else {
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

            // 🆕 使用 Git-style 三方合并
            final mergeResult = _gitMerger.merge<SyncableTodoList>(
              localSyncableList,
              remoteList,
              _currentDevice?.deviceId ?? 'unknown',
            );

            print(
                '🔀 [GitMerge] 列表${remoteList.name}: ${mergeResult.mergeType} - ${mergeResult.description}');

            // 如果有冲突，记录
            if (mergeResult.hasConflict) {
              conflictCount++;
            }

            // 应用合并结果
            if (mergeResult.needsUpdate && mergeResult.mergedData != null) {
              final resolved = mergeResult.mergedData!;

              // 🆕 检查是否已删除
              if (resolved.syncMetadata.isDeleted) {
                // 如果标记为删除，从本地移除
                localListMap.remove(resolved.id);
                final listMetadataId = 'list_${resolved.id}';
                localSyncMetadata.remove(listMetadataId);
                print('🗑️ [SyncService] 删除列表: ${resolved.name}');
                listHasChanges = true;
              } else {
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

      // 通知UI更新 - 即使没有新增/更新项也要通知（可能有删除或其他变化）
      final totalItems = mergedItems + updatedItems;
      print('📢 [SyncService] 通知待办数据更新: 新增=$mergedItems, 更新=$updatedItems');
      _notifyDataUpdated('todos', fromDeviceId, totalItems);
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
      int ongoingActivitiesCount = 0;

      // 获取本地所有记录
      final existingLogs =
          await TimeLoggerStorage.getAllRecords(forceRefresh: true);

      // 获取本地当前正在进行的活动
      final localCurrentActivity = await TimeLoggerStorage.getCurrentActivity();

      // 收集远程正在进行的活动（endTime为null的记录）
      final remoteOngoingActivities =
          syncableLogs.where((log) => log.endTime == null).toList();

      if (remoteOngoingActivities.isNotEmpty) {
        print('📍 [SyncService] 收到 ${remoteOngoingActivities.length} 个正在进行的活动');
        ongoingActivitiesCount = remoteOngoingActivities.length;
      }

      for (final remoteLog in syncableLogs) {
        try {
          // 🆕 改进的重复检测：优先使用activityId，回退到时间窗口匹配
          final exists = existingLogs.any((log) {
            // 如果activityId都存在，优先使用activityId进行精确匹配
            if (log.activityId.isNotEmpty && remoteLog.activityId.isNotEmpty) {
              return log.activityId == remoteLog.activityId;
            }

            // 回退方案：使用时间窗口和内容匹配（考虑网络延迟）
            final timeDiff = (log.startTime.millisecondsSinceEpoch -
                    remoteLog.startTime.millisecondsSinceEpoch)
                .abs();
            // 时间差在2秒内，且活动名称相同，视为同一记录
            return timeDiff < 2000 && log.name == remoteLog.name;
          });

          // 检查是否与本地当前活动相同
          final isLocalCurrentActivity = localCurrentActivity != null &&
              (
                  // 优先使用activityId匹配
                  (localCurrentActivity.activityId.isNotEmpty &&
                          remoteLog.activityId.isNotEmpty &&
                          localCurrentActivity.activityId ==
                              remoteLog.activityId) ||
                      // 回退方案：时间窗口匹配
                      ((localCurrentActivity.startTime.millisecondsSinceEpoch -
                                      remoteLog
                                          .startTime.millisecondsSinceEpoch)
                                  .abs() <
                              2000 &&
                          localCurrentActivity.name == remoteLog.name));

          if (!exists && !isLocalCurrentActivity) {
            // 如果是正在进行的活动（endTime为null），不保存为历史记录
            // 而是添加到 _activeTimers 供UI显示和冲突解决使用
            if (remoteLog.endTime == null) {
              print('⏸️  [SyncService] 检测到远程正在进行的活动: ${remoteLog.name}');

              // 🆕 直接使用远程日志中的activityId，不再重新计算
              // 这样确保跨设备activityId一致，计时器可以正确启动和停止
              final activityId = remoteLog.activityId;
              print('   远程activityId: $activityId');

              final timerState = TimerState(
                activityId: activityId,
                activityName: remoteLog.name,
                linkedTodoId: remoteLog.linkedTodoId,
                linkedTodoTitle: remoteLog.linkedTodoTitle,
                startTime: remoteLog.startTime,
                currentDuration:
                    DateTime.now().difference(remoteLog.startTime).inSeconds,
                deviceId: fromDeviceId,
                deviceName: _connectedDevicesMap[fromDeviceId]?.deviceName ??
                    _serverService
                        .getConnectedDevice(fromDeviceId)
                        ?.deviceName ??
                    '远程设备',
              );

              _activeTimers[fromDeviceId] = timerState;
              print(
                  '✅ [SyncService] 已添加远程活动到计时器列表: ${timerState.activityName} (${timerState.deviceName})');

              // 正在进行的活动将通过 _resolveActiveTimerConflicts 处理
              continue;
            }

            // 保存已完成的时间日志
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
            if (isLocalCurrentActivity) {
              print('⏭️  [SyncService] 跳过与本地当前活动相同的日志: ${remoteLog.name}');
            } else {
              print('⏭️  [SyncService] 跳过已存在的日志: ${remoteLog.name}');
            }
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
          description:
              '成功合并 $mergedLogs 个时间日志${ongoingActivitiesCount > 0 ? '，检测到 $ongoingActivitiesCount 个正在进行的活动' : ''}',
          success: true,
        );
      }

      print(
          '✅ [SyncService] 时间日志更新完成: 合并 $mergedLogs 条${ongoingActivitiesCount > 0 ? '，正在进行的活动 $ongoingActivitiesCount 个' : ''}');

      // 🆕 如果收到了正在进行的活动，触发冲突解决
      if (remoteOngoingActivities.isNotEmpty) {
        print('🔄 [SyncService] 触发活动冲突解决...');
        await _resolveActiveTimerConflicts(fromDeviceId);

        // 🆕 冲突解决后，强制发送数据更新通知，确保UI刷新
        // 无论 mergedLogs 是否为 0，都要通知UI当前活动可能已改变
        print('📢 [SyncService] 冲突解决完成，发送UI更新通知');
        _notifyDataUpdated(
            'timeLogs', fromDeviceId, mergedLogs + ongoingActivitiesCount);
      } else {
        // 没有正在进行的活动，正常发送数据更新事件
        _notifyDataUpdated('timeLogs', fromDeviceId, mergedLogs);
      }
    } catch (e) {
      print('❌ [SyncService] 处理时间日志更新失败: $e');
    }
  }

  /// 处理接收到的目标数据
  Future<void> _handleTargetsDataUpdate(
      dynamic remoteData, String fromDeviceId, String? syncSessionId) async {
    print('🔄 [SyncService] 处理目标更新: 来自 $fromDeviceId [会话: $syncSessionId]');
    print('📦 [SyncService] 接收到的原始数据类型: ${remoteData.runtimeType}');

    try {
      // 🆕 尝试解压数据（与todos保持一致）
      Map<String, dynamic> actualData;
      if (remoteData is Map<String, dynamic> &&
          remoteData.containsKey('compressed')) {
        print('🔄 [SyncService] 检测到压缩数据，开始解压...');
        final decompressed = SyncCompression.decompressJson(remoteData);
        if (decompressed == null) {
          print('❌ [SyncService] 目标数据解压失败');
          _handleError(SyncError(
            type: SyncErrorType.dataCorrupted,
            message: '目标数据解压失败',
            details: '来源: $fromDeviceId',
          ));
          return;
        }
        actualData = decompressed;
        print('✅ [SyncService] 目标数据解压成功');
      } else if (remoteData is Map<String, dynamic> &&
          remoteData.containsKey('data')) {
        print('📦 [SyncService] 使用未压缩数据');
        actualData = remoteData['data'] as Map<String, dynamic>;
      } else if (remoteData is Map<String, dynamic>) {
        print('📦 [SyncService] 直接使用Map数据');
        actualData = remoteData;
      } else {
        print('⚠️  [SyncService] 使用旧格式（兼容）');
        // 兼容旧格式：直接是列表
        actualData = {'items': remoteData as List<dynamic>};
      }

      final storage = TargetStorage();
      final localTargets = await storage.loadTargets();
      final localSyncMetadata = await TodoStorage.getSyncMetadata();

      // 从actualData中提取items（与todos保持一致）
      final remoteTargetsJson = actualData['items'] ?? actualData;
      final actualTargets =
          (remoteTargetsJson is List) ? remoteTargetsJson : [remoteTargetsJson];

      print('📦 [SyncService] 收到 ${actualTargets.length} 个目标');

      int mergedCount = 0;
      int updatedCount = 0;
      int conflictCount = 0;
      bool hasChanges = false;
      final localTargetMap = {for (var t in localTargets) t.id: t};

      for (final remoteTargetJson in actualTargets) {
        try {
          final remoteTarget = SyncableTarget.fromJson(remoteTargetJson);

          // 构建本地的 SyncableTarget（如果存在）
          SyncableTarget? localSyncableTarget;
          final localTarget = localTargetMap[remoteTarget.id];
          if (localTarget != null) {
            final targetMetadataId = 'target_${localTarget.id}';
            final localMetadata = localSyncMetadata[targetMetadataId] ??
                SyncMetadata.create(_currentDevice?.deviceId ?? 'unknown');
            localSyncableTarget = SyncableTarget(
              id: localTarget.id,
              name: localTarget.name,
              type: localTarget.type.index,
              period: localTarget.period.index,
              targetSeconds: localTarget.targetSeconds,
              linkedTodoIds: localTarget.linkedTodoIds,
              linkedListIds: localTarget.linkedListIds,
              createdAt: localTarget.createdAt,
              isActive: localTarget.isActive,
              colorValue:
                  localTarget.color.value, // ignore: deprecated_member_use
              syncMetadata: localMetadata,
            );
          }

          // 🆕 使用 Git-style 三方合并
          final mergeResult = _gitMerger.merge<SyncableTarget>(
            localSyncableTarget,
            remoteTarget,
            _currentDevice?.deviceId ?? 'unknown',
          );

          print(
              '🔀 [GitMerge] 目标${remoteTarget.name}: ${mergeResult.mergeType} - ${mergeResult.description}');

          // 如果有冲突，记录
          if (mergeResult.hasConflict) {
            conflictCount++;
          }

          // 应用合并结果
          if (mergeResult.needsUpdate && mergeResult.mergedData != null) {
            final resolved = mergeResult.mergedData!;

            // 🆕 检查是否已删除
            if (resolved.syncMetadata.isDeleted) {
              // 如果标记为删除，从本地移除
              localTargetMap.remove(resolved.id);
              final targetMetadataId = 'target_${resolved.id}';
              localSyncMetadata.remove(targetMetadataId);
              print('🗑️ [SyncService] 删除目标: ${resolved.name}');
              hasChanges = true;
            } else {
              // 更新目标数据
              localTargetMap[resolved.id] = Target(
                id: resolved.id,
                name: resolved.name,
                type: TargetType.values[resolved.type],
                period: TimePeriod.values[resolved.period],
                targetSeconds: resolved.targetSeconds,
                linkedTodoIds: resolved.linkedTodoIds,
                linkedListIds: resolved.linkedListIds,
                createdAt: resolved.createdAt,
                isActive: resolved.isActive,
                color: Color(resolved.colorValue),
              );

              // 保存目标的元数据
              final targetMetadataId = 'target_${resolved.id}';
              localSyncMetadata[targetMetadataId] = resolved.syncMetadata;

              if (localSyncableTarget == null) {
                mergedCount++;
                print('➕ [SyncService] 新增目标: ${resolved.name}');
              } else {
                updatedCount++;
                print('🔄 [SyncService] 更新目标: ${resolved.name}');
              }
              hasChanges = true;
            }
          }
        } catch (e) {
          print('❌ [SyncService] 处理目标失败: $e');
        }
      }

      // 保存更新后的目标列表和元数据
      if (hasChanges) {
        await storage.saveTargets(localTargetMap.values.toList());
        await TodoStorage.saveSyncMetadata(localSyncMetadata);
        print('💾 [SyncService] 目标数据已保存');
        print('⚠️  [SyncService] 解决了 $conflictCount 个冲突');
      }

      // 记录历史
      final device = _serverService.getConnectedDevice(fromDeviceId);
      if (device != null) {
        final totalChanges = mergedCount + updatedCount;
        await _historyService.recordMerge(
          deviceId: fromDeviceId,
          deviceName: device.deviceName,
          dataType: 'targets',
          itemCount: totalChanges,
          description: '成功合并 $mergedCount 个新目标，更新 $updatedCount 个目标',
          success: true,
        );
      }

      print('✅ [SyncService] 目标更新完成: 新增 $mergedCount 个，更新 $updatedCount 个');

      // 发送数据更新事件 - 始终通知UI更新（即使没有变化也要刷新显示）
      final totalChanges = mergedCount + updatedCount;
      print('📢 [SyncService] 通知目标数据更新: 新增=$mergedCount, 更新=$updatedCount');
      _notifyDataUpdated('targets', fromDeviceId, totalChanges);
    } catch (e, stack) {
      print('❌ [SyncService] 处理目标更新失败: $e');
      print('Stack: $stack');
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

  /// 加载本地活动计时器
  Future<void> _loadLocalActiveTimer() async {
    if (_currentDevice == null) return;

    print('📂 [SyncService] 加载本地活动计时器...');

    try {
      // 从 TimeLoggerStorage 加载当前正在运行的活动
      final currentActivity = await TimeLoggerStorage.getCurrentActivity();

      if (currentActivity != null && currentActivity.endTime == null) {
        print('✅ [SyncService] 发现本地正在运行的活动: ${currentActivity.name}');
        print('   activityId: ${currentActivity.activityId}');

        // 计算当前持续时间
        final duration =
            DateTime.now().difference(currentActivity.startTime).inSeconds;

        // 创建 TimerState（直接使用存储的 activityId）
        final timerState = TimerState(
          activityId: currentActivity.activityId,
          activityName: currentActivity.name,
          linkedTodoId: currentActivity.linkedTodoId,
          linkedTodoTitle: currentActivity.linkedTodoTitle,
          deviceId: _currentDevice!.deviceId,
          deviceName: _currentDevice!.deviceName,
          startTime: currentActivity.startTime,
          currentDuration: duration,
        );

        // 添加到活动计时器
        _activeTimers[_currentDevice!.deviceId] = timerState;

        // 通知更新
        _notifyActiveTimersChanged();

        print('✅ [SyncService] 本地活动计时器已加载');
      } else {
        print('ℹ️  [SyncService] 本地没有正在运行的活动');
      }
    } catch (e) {
      print('❌ [SyncService] 加载本地活动计时器失败: $e');
    }
  }

  /// 启动活动计时器更新
  void _startActiveTimersUpdate() {
    _stopActiveTimersUpdate(); // 确保没有重复的定时器

    print('⏱️  [SyncService] 启动活动计时器更新定时器');
    _activeTimersUpdateTimer =
        Timer.periodic(_activeTimersUpdateInterval, (timer) {
      _updateActiveTimers();
    });
  }

  /// 停止活动计时器更新
  void _stopActiveTimersUpdate() {
    _activeTimersUpdateTimer?.cancel();
    _activeTimersUpdateTimer = null;
  }

  /// 更新活动计时器的 currentDuration
  void _updateActiveTimers() {
    if (_activeTimers.isEmpty) {
      return;
    }

    // 🔒 防止重入（如果上次更新还未完成）
    if (_isUpdatingActiveTimers) {
      return;
    }
    _isUpdatingActiveTimers = true;

    try {
      bool hasUpdates = false;
      final now = DateTime.now();

      // 🆕 直接在Map上增量更新，避免清空重建
      for (final entry in _activeTimers.entries.toList()) {
        final deviceId = entry.key;
        final timer = entry.value;
        final newDuration = now.difference(timer.startTime).inSeconds;

        // 只有当时间发生变化时才更新
        if (newDuration != timer.currentDuration) {
          _activeTimers[deviceId] =
              timer.copyWith(currentDuration: newDuration);
          hasUpdates = true;

          // 🆕 每30秒输出一次详细日志，帮助调试长时间运行的计时器
          if (newDuration % 30 == 0) {
            print('⏱️  [SyncService] 计时器更新: ${timer.activityName}');
            print('   设备: ${timer.deviceName} (${timer.deviceId})');
            print(
                '   当前时长: $newDuration 秒 (${(newDuration / 60).toStringAsFixed(1)} 分钟)');
          }
        }
      }

      // 只有有实际时间更新时才通知UI
      if (hasUpdates) {
        _notifyActiveTimersChanged();
      }
    } finally {
      _isUpdatingActiveTimers = false;
    }
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
    _activeTimersUpdateTimer?.cancel();
    _activeTimersUpdateTimer = null;

    // 🆕 清理设备断连定时器
    for (final timer in _deviceDisconnectTimers.values) {
      timer.cancel();
    }
    _deviceDisconnectTimers.clear();

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

/// 活动状态（用于冲突解决）
class _ActiveActivity {
  final String deviceId;
  final String deviceName;
  final ActivityRecordData activity;
  final bool isLocal;

  _ActiveActivity({
    required this.deviceId,
    required this.deviceName,
    required this.activity,
    required this.isLocal,
  });
}
