import 'dart:async';
import 'dart:convert'; // 用于 JSON 序列化
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'; // 导入 Material 以使用 GlobalKey
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🆕 导入 SharedPreferences

/// 通知权限状态
enum NotificationPermissionStatus {
  granted,
  denied,
  notDetermined,
  notSupported,
}

/// 通知历史记录项
class NotificationHistoryItem {
  final DateTime timestamp;
  final String activityName;
  final String durationText;
  final int progressPercent;
  final bool wasClicked; // 🆕 是否被点击
  final String? actionTaken; // 🆕 采取的操作 (view/pause/stop)

  NotificationHistoryItem({
    required this.timestamp,
    required this.activityName,
    required this.durationText,
    required this.progressPercent,
    this.wasClicked = false,
    this.actionTaken,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'activityName': activityName,
        'durationText': durationText,
        'progressPercent': progressPercent,
        'wasClicked': wasClicked,
        'actionTaken': actionTaken,
      };

  factory NotificationHistoryItem.fromJson(Map<String, dynamic> json) =>
      NotificationHistoryItem(
        timestamp: DateTime.parse(json['timestamp']),
        activityName: json['activityName'],
        durationText: json['durationText'],
        progressPercent: json['progressPercent'],
        wasClicked: json['wasClicked'] ?? false,
        actionTaken: json['actionTaken'],
      );

  // 🆕 复制并更新交互信息
  NotificationHistoryItem copyWith({
    bool? wasClicked,
    String? actionTaken,
  }) {
    return NotificationHistoryItem(
      timestamp: timestamp,
      activityName: activityName,
      durationText: durationText,
      progressPercent: progressPercent,
      wasClicked: wasClicked ?? this.wasClicked,
      actionTaken: actionTaken ?? this.actionTaken,
    );
  }
}

/// 通知服务 - 用于在移动端应用后台时发送计时提醒
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  Timer? _notificationTimer;
  DateTime? _lastNotificationTime;
  DateTime? _activityStartTime; // 记录活动开始时间，用于计算时长

  // 通知权限状态
  NotificationPermissionStatus _permissionStatus =
      NotificationPermissionStatus.notDetermined;

  // 🆕 导航回调，用于点击通知时跳转
  Function()? _onNotificationNavigate;

  // 🆕 停止计时回调，用于通知操作按钮
  Function()? _onStopTimer;

  // 🆕 暂停/继续计时回调
  Function()? _onTogglePause;

  // 🆕 通知设置
  static const String _keyNotificationEnabled = 'notification_enabled';
  static const String _keyNotificationInterval = 'notification_interval';
  static const String _keyNotificationCount = 'notification_count'; // 统计发送次数
  static const String _keyNotificationHistory = 'notification_history'; // 通知历史
  static const int _maxHistoryItems = 50; // 最多保存50条历史记录
  static const String _keyNotificationSound = 'notification_sound'; // 通知声音
  static const String _keyNotificationVibration =
      'notification_vibration'; // 通知震动

  // 🆕 SharedPreferences 缓存，避免频繁读取
  SharedPreferences? _prefs;

  int _notificationIntervalMinutes = 5; // 默认5分钟
  bool _notificationsEnabled = true; // 默认开启
  int _notificationCount = 0; // 已发送的通知数量

  // 🆕 通知历史记录列表（内存缓存）
  final List<NotificationHistoryItem> _notificationHistory = [];
  bool _historyLoaded = false; // 🆕 标记历史记录是否已加载

  // 🆕 通知音效和震动设置
  bool _notificationSound = true; // 默认开启声音
  bool _notificationVibration = true; // 默认开启震动

  // 🆕 批量保存相关
  Timer? _historySaveTimer; // 历史记录保存定时器
  bool _historyNeedsSave = false; // 是否需要保存历史记录
  int _notificationFailCount = 0; // 通知发送失败次数

  // 🆕 通知去重相关
  String? _lastNotificationContent; // 上次发送的通知内容
  DateTime? _lastNotificationContentTime; // 上次发送相同内容的时间
  static const Duration _deduplicationWindow = Duration(minutes: 2); // 去重时间窗口

  // 🆕 通知统计相关
  int _notificationClickCount = 0; // 通知点击次数
  int _notificationActionCount = 0; // 通知操作次数
  static const String _keyNotificationClickCount = 'notification_click_count';
  static const String _keyNotificationActionCount = 'notification_action_count';

  // 🆕 智能通知优先级相关
  bool _adaptiveNotificationEnabled = true; // 是否启用自适应通知
  static const String _keyAdaptiveNotificationEnabled =
      'adaptive_notification_enabled';

  // 🆕 智能通知功能
  static const String _keyDoNotDisturbEnabled = 'dnd_enabled';
  static const String _keyDoNotDisturbStart = 'dnd_start_hour';
  static const String _keyDoNotDisturbEnd = 'dnd_end_hour';
  bool _doNotDisturbEnabled = false;
  int _doNotDisturbStartHour = 22; // 默认晚上10点
  int _doNotDisturbEndHour = 7; // 默认早上7点

  // 🆕 通知渠道常量
  static const String _channelId = 'timer_channel';
  static const String _channelName = 'Timer Notifications';
  static const String _channelDescription =
      'Notifications for ongoing time tracking';

  /// 🆕 设置导航回调
  void setNavigationCallback(Function() callback) {
    _onNotificationNavigate = callback;
  }

  /// 🆕 设置停止计时回调
  void setStopTimerCallback(Function() callback) {
    _onStopTimer = callback;
  }

  /// 🆕 设置暂停/继续计时回调
  void setTogglePauseCallback(Function() callback) {
    _onTogglePause = callback;
  }

  /// 🆕 清除导航回调（防止内存泄漏）
  void clearNavigationCallback() {
    _onNotificationNavigate = null;
  }

  /// 🆕 清除所有回调（防止内存泄漏）
  void clearAllCallbacks() {
    _onNotificationNavigate = null;
    _onStopTimer = null;
    _onTogglePause = null;
  }

  /// 🆕 获取通知权限状态
  NotificationPermissionStatus get permissionStatus => _permissionStatus;

  /// 🆕 获取通知统计信息
  int get notificationCount => _notificationCount;

  /// 🆕 获取通知历史记录（懒加载）
  Future<List<NotificationHistoryItem>> getNotificationHistory() async {
    if (!_historyLoaded) {
      await _loadNotificationHistory();
      _historyLoaded = true;
    }
    return List.unmodifiable(_notificationHistory);
  }

  /// 🆕 获取通知历史记录（同步，如果未加载则返回空）
  List<NotificationHistoryItem> get notificationHistory =>
      List.unmodifiable(_notificationHistory);

  /// 🆕 检查是否忽略了电池优化 (Android)
  /// 注意：此功能需要添加额外的插件如 battery_plus 或使用 platform channel
  Future<bool> isBatteryOptimizationIgnored() async {
    if (!Platform.isAndroid) return true; // iOS 不需要此检查

    // TODO: 实现电池优化检测
    // 可以使用 platform channel 调用原生 Android API:
    // PowerManager.isIgnoringBatteryOptimizations(packageName)
    debugPrint('通知服务: 电池优化检测功能待实现');
    return true; // 暂时返回 true
  }

  /// 🆕 请求忽略电池优化 (Android)
  Future<void> requestIgnoreBatteryOptimization() async {
    if (!Platform.isAndroid) return;

    // TODO: 实现请求忽略电池优化
    // 需要调用原生 Android API:
    // Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS)
    debugPrint('通知服务: 请求忽略电池优化功能待实现');
  }

  /// 初始化通知服务
  Future<void> initialize() async {
    // 只在移动端初始化
    if (!Platform.isAndroid && !Platform.isIOS) {
      debugPrint('通知服务: 非移动端平台，跳过初始化');
      _permissionStatus = NotificationPermissionStatus.notSupported;
      return;
    }

    try {
      // 🆕 初始化 SharedPreferences 缓存
      _prefs = await SharedPreferences.getInstance();

      // 🆕 加载通知设置
      await _loadSettings();

      // Android 初始化设置
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS 初始化设置
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      final initialized = await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      _isInitialized = initialized ?? false;

      if (_isInitialized) {
        debugPrint('通知服务: 初始化成功');

        // 请求 Android 13+ 的通知权限
        if (Platform.isAndroid) {
          await _requestAndroidPermissions();
        } else {
          // iOS 默认已授权
          _permissionStatus = NotificationPermissionStatus.granted;
        }

        // 🆕 创建通知渠道（Android 8.0+）
        await _createNotificationChannel();
      } else {
        debugPrint('通知服务: 初始化失败');
        _permissionStatus = NotificationPermissionStatus.denied;
      }
    } catch (e) {
      debugPrint('通知服务: 初始化异常 - $e');
      _isInitialized = false;
      _permissionStatus = NotificationPermissionStatus.denied;
    }
  }

  /// 🆕 加载通知设置
  Future<void> _loadSettings() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      _notificationsEnabled = _prefs!.getBool(_keyNotificationEnabled) ?? true;
      _notificationIntervalMinutes =
          _prefs!.getInt(_keyNotificationInterval) ?? 5;
      _notificationCount = _prefs!.getInt(_keyNotificationCount) ?? 0;
      _notificationSound = _prefs!.getBool(_keyNotificationSound) ?? true;
      _notificationVibration =
          _prefs!.getBool(_keyNotificationVibration) ?? true;

      // 🆕 加载免打扰设置
      _doNotDisturbEnabled = _prefs!.getBool(_keyDoNotDisturbEnabled) ?? false;
      _doNotDisturbStartHour = _prefs!.getInt(_keyDoNotDisturbStart) ?? 22;
      _doNotDisturbEndHour = _prefs!.getInt(_keyDoNotDisturbEnd) ?? 7;

      // 🆕 加载统计数据
      _notificationClickCount = _prefs!.getInt(_keyNotificationClickCount) ?? 0;
      _notificationActionCount =
          _prefs!.getInt(_keyNotificationActionCount) ?? 0;

      // 🆕 加载自适应通知设置
      _adaptiveNotificationEnabled =
          _prefs!.getBool(_keyAdaptiveNotificationEnabled) ?? true;

      // 🆕 不在初始化时加载历史记录，改为懒加载
      // await _loadNotificationHistory();

      debugPrint(
          '通知服务: 已加载设置 - 启用: $_notificationsEnabled, 间隔: $_notificationIntervalMinutes 分钟, 发送次数: $_notificationCount, 点击次数: $_notificationClickCount, 操作次数: $_notificationActionCount, 声音: $_notificationSound, 震动: $_notificationVibration, 自适应: $_adaptiveNotificationEnabled, 免打扰: $_doNotDisturbEnabled ($_doNotDisturbStartHour:00-$_doNotDisturbEndHour:00)');
    } catch (e) {
      debugPrint('通知服务: 加载设置失败 - $e');
    }
  }

  /// 🆕 加载通知历史记录
  Future<void> _loadNotificationHistory() async {
    try {
      _prefs ??= await SharedPreferences.getInstance();
      final historyJson = _prefs!.getStringList(_keyNotificationHistory);
      if (historyJson != null) {
        _notificationHistory.clear();
        for (var json in historyJson) {
          try {
            final item = NotificationHistoryItem.fromJson(jsonDecode(json));
            _notificationHistory.add(item);
          } catch (e) {
            debugPrint('通知服务: 解析历史记录失败 - $e');
          }
        }
      }
    } catch (e) {
      debugPrint('通知服务: 加载通知历史失败 - $e');
    }
  }

  /// 🆕 保存通知历史记录 (批量保存)
  Future<void> _saveNotificationHistory() async {
    if (!_historyNeedsSave) return; // 如果不需要保存，直接返回

    try {
      _prefs ??= await SharedPreferences.getInstance();

      // 限制历史记录数量
      if (_notificationHistory.length > _maxHistoryItems) {
        _notificationHistory.removeRange(
          0,
          _notificationHistory.length - _maxHistoryItems,
        );
      }

      // 序列化为 JSON
      final historyJson = _notificationHistory
          .map((item) => jsonEncode(item.toJson()))
          .toList();

      await _prefs!.setStringList(_keyNotificationHistory, historyJson);
      _historyNeedsSave = false; // 重置标记
      debugPrint('通知服务: 已批量保存 ${_notificationHistory.length} 条历史记录');
    } catch (e) {
      debugPrint('通知服务: 保存通知历史失败 - $e');
    }
  }

  /// 🆕 标记历史需要保存（延迟保存策略）
  void _markHistoryForSave() {
    _historyNeedsSave = true;

    // 取消之前的定时器
    _historySaveTimer?.cancel();

    // 30秒后自动保存，或者当有5条新记录时立即保存
    if (_notificationHistory.length % 5 == 0) {
      _saveNotificationHistory();
    } else {
      _historySaveTimer = Timer(const Duration(seconds: 30), () {
        _saveNotificationHistory();
      });
    }
  }

  /// 🆕 创建 Android 通知渠道
  Future<void> _createNotificationChannel() async {
    if (!Platform.isAndroid) return;

    try {
      final androidPlugin =
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        final channel = AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.high,
          playSound: true,
          enableVibration: true,
          showBadge: true,
        );

        await androidPlugin.createNotificationChannel(channel);
        debugPrint('通知服务: 已创建通知渠道 - $_channelId');
      }
    } catch (e) {
      debugPrint('通知服务: 创建通知渠道失败 - $e');
    }
  }

  /// 🆕 通用设置保存方法
  Future<void> _saveSetting<T>(String key, T value) async {
    try {
      if (value is bool) {
        await _prefs!.setBool(key, value);
      } else if (value is int) {
        await _prefs!.setInt(key, value);
      } else if (value is double) {
        await _prefs!.setDouble(key, value);
      } else if (value is String) {
        await _prefs!.setString(key, value);
      } else {
        debugPrint('通知服务: 不支持的设置类型 - ${value.runtimeType}');
        return;
      }
      debugPrint('通知服务: 已保存设置 $key = $value');
    } catch (e) {
      debugPrint('通知服务: 保存设置失败 $key - $e');
    }
  }

  /// 🆕 保存通知启用状态
  Future<void> setNotificationsEnabled(bool enabled) async {
    await _saveSetting(_keyNotificationEnabled, enabled);
    _notificationsEnabled = enabled;
  }

  /// 🆕 保存通知间隔
  Future<void> setNotificationInterval(int minutes) async {
    await _saveSetting(_keyNotificationInterval, minutes);
    _notificationIntervalMinutes = minutes;
  }

  /// 🆕 保存通知声音设置
  Future<void> setNotificationSound(bool enabled) async {
    await _saveSetting(_keyNotificationSound, enabled);
    _notificationSound = enabled;
  }

  /// 🆕 保存通知震动设置
  Future<void> setNotificationVibration(bool enabled) async {
    await _saveSetting(_keyNotificationVibration, enabled);
    _notificationVibration = enabled;
  }

  /// 🆕 设置免打扰模式
  Future<void> setDoNotDisturb(bool enabled,
      {int? startHour, int? endHour}) async {
    await _saveSetting(_keyDoNotDisturbEnabled, enabled);
    _doNotDisturbEnabled = enabled;

    if (startHour != null) {
      await _saveSetting(_keyDoNotDisturbStart, startHour);
      _doNotDisturbStartHour = startHour;
    }

    if (endHour != null) {
      await _saveSetting(_keyDoNotDisturbEnd, endHour);
      _doNotDisturbEndHour = endHour;
    }

    debugPrint(
        '通知服务: 已设置免打扰 - 启用: $enabled, 时段: $_doNotDisturbStartHour:00-$_doNotDisturbEndHour:00');
  }

  /// 🆕 检查当前是否在免打扰时段
  bool _isInDoNotDisturbPeriod() {
    if (!_doNotDisturbEnabled) return false;

    final now = DateTime.now();
    final currentHour = now.hour;

    // 处理跨日情况（例如 22:00 - 7:00）
    if (_doNotDisturbStartHour > _doNotDisturbEndHour) {
      return currentHour >= _doNotDisturbStartHour ||
          currentHour < _doNotDisturbEndHour;
    } else {
      return currentHour >= _doNotDisturbStartHour &&
          currentHour < _doNotDisturbEndHour;
    }
  }

  /// 🆕 获取免打扰设置
  bool get doNotDisturbEnabled => _doNotDisturbEnabled;
  int get doNotDisturbStartHour => _doNotDisturbStartHour;
  int get doNotDisturbEndHour => _doNotDisturbEndHour;

  /// 🆕 增加通知计数
  Future<void> _incrementNotificationCount() async {
    try {
      _notificationCount++;
      await _prefs!.setInt(_keyNotificationCount, _notificationCount);
    } catch (e) {
      debugPrint('通知服务: 保存通知计数失败 - $e');
    }
  }

  /// 🆕 重置通知计数
  Future<void> resetNotificationCount() async {
    try {
      _notificationCount = 0;
      await _prefs!.setInt(_keyNotificationCount, 0);
      debugPrint('通知服务: 已重置通知计数');
    } catch (e) {
      debugPrint('通知服务: 重置通知计数失败 - $e');
    }
  }

  /// 🆕 清除通知历史记录
  Future<void> clearNotificationHistory() async {
    try {
      _notificationHistory.clear();
      await _prefs!.remove(_keyNotificationHistory);
      _historyNeedsSave = false; // 重置标记
      _historySaveTimer?.cancel(); // 取消定时器
      _historyLoaded = false; // 🆕 重置加载标记
      debugPrint('通知服务: 已清除通知历史');
    } catch (e) {
      debugPrint('通知服务: 清除通知历史失败 - $e');
    }
  }

  /// 🆕 获取通知启用状态
  bool get notificationsEnabled => _notificationsEnabled;

  /// 🆕 获取通知间隔
  int get notificationIntervalMinutes => _notificationIntervalMinutes;

  /// 🆕 获取通知声音设置
  bool get notificationSound => _notificationSound;

  /// 🆕 获取通知震动设置
  bool get notificationVibration => _notificationVibration;

  /// 请求 Android 通知权限 (Android 13+)
  Future<void> _requestAndroidPermissions() async {
    if (Platform.isAndroid) {
      final androidPlugin =
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidPlugin != null) {
        final granted = await androidPlugin.requestNotificationsPermission();
        _permissionStatus = (granted ?? false)
            ? NotificationPermissionStatus.granted
            : NotificationPermissionStatus.denied;
        debugPrint('通知服务: Android 权限请求结果 - $granted, 状态: $_permissionStatus');
      }
    }
  }

  /// 通知被点击时的回调
  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('通知被点击: ${response.payload}, actionId: ${response.actionId}');

    // 🆕 记录通知交互
    _recordNotificationInteraction(response.actionId);

    // 处理不同的通知操作
    if (response.actionId == 'stop_action') {
      // 点击停止按钮
      debugPrint('通知服务: 用户点击了停止按钮');
      if (_onStopTimer != null) {
        _onStopTimer!();
      }
    } else if (response.actionId == 'pause_action') {
      // 点击暂停/继续按钮
      debugPrint('通知服务: 用户点击了暂停/继续按钮');
      if (_onTogglePause != null) {
        _onTogglePause!();
      }
    } else if (response.payload == 'timer_reminder' ||
        response.actionId == 'view_action') {
      // 点击主通知或"查看详情"按钮
      debugPrint('通知服务: 用户点击了计时通知，跳转到计时页面');

      // 🆕 调用导航回调
      if (_onNotificationNavigate != null) {
        _onNotificationNavigate!();
      }
    }
  }

  /// 🆕 记录通知交互
  Future<void> _recordNotificationInteraction(String? actionId) async {
    try {
      _notificationClickCount++;
      await _prefs?.setInt(_keyNotificationClickCount, _notificationClickCount);

      if (actionId != null && actionId.isNotEmpty) {
        _notificationActionCount++;
        await _prefs?.setInt(
            _keyNotificationActionCount, _notificationActionCount);
      }

      // 更新最近的历史记录项
      if (_notificationHistory.isNotEmpty) {
        final lastIndex = _notificationHistory.length - 1;
        final lastItem = _notificationHistory[lastIndex];
        _notificationHistory[lastIndex] = lastItem.copyWith(
          wasClicked: true,
          actionTaken: actionId,
        );
        _markHistoryForSave();
      }

      debugPrint(
          '通知服务: 记录交互 - 点击次数: $_notificationClickCount, 操作次数: $_notificationActionCount, 操作: $actionId');
    } catch (e) {
      debugPrint('通知服务: 记录交互失败 - $e');
    }
  }

  /// 🆕 获取通知统计信息
  Map<String, dynamic> getNotificationStats() {
    final clickRate = _notificationCount > 0
        ? (_notificationClickCount / _notificationCount * 100)
            .toStringAsFixed(1)
        : '0.0';
    final actionRate = _notificationCount > 0
        ? (_notificationActionCount / _notificationCount * 100)
            .toStringAsFixed(1)
        : '0.0';

    return {
      'totalSent': _notificationCount,
      'totalClicks': _notificationClickCount,
      'totalActions': _notificationActionCount,
      'clickRate': '$clickRate%',
      'actionRate': '$actionRate%',
      'historyCount': _notificationHistory.length,
    };
  }

  /// 🆕 根据进度动态获取通知重要性
  Importance _getNotificationImportance(int progressPercent) {
    if (!_adaptiveNotificationEnabled) {
      return Importance.high; // 默认高重要性
    }

    // 根据进度调整重要性
    if (progressPercent >= 80) {
      return Importance.max; // 接近完成，最高重要性
    } else if (progressPercent >= 50) {
      return Importance.high; // 中期，高重要性
    } else if (progressPercent >= 20) {
      return Importance.defaultImportance; // 早期，默认重要性
    } else {
      return Importance.low; // 刚开始，低重要性
    }
  }

  /// 🆕 根据进度动态获取通知优先级
  Priority _getNotificationPriority(int progressPercent) {
    if (!_adaptiveNotificationEnabled) {
      return Priority.high; // 默认高优先级
    }

    // 根据进度调整优先级
    if (progressPercent >= 80) {
      return Priority.max; // 接近完成，最高优先级
    } else if (progressPercent >= 50) {
      return Priority.high; // 中期，高优先级
    } else if (progressPercent >= 20) {
      return Priority.defaultPriority; // 早期，默认优先级
    } else {
      return Priority.low; // 刚开始，低优先级
    }
  }

  /// 🆕 设置自适应通知
  Future<void> setAdaptiveNotification(bool enabled) async {
    await _saveSetting(_keyAdaptiveNotificationEnabled, enabled);
    _adaptiveNotificationEnabled = enabled;
  }

  /// 🆕 获取自适应通知设置
  bool get adaptiveNotificationEnabled => _adaptiveNotificationEnabled;

  /// 开始后台通知 - 根据用户设置的间隔提醒
  void startBackgroundNotifications(String activityName,
      {DateTime? startTime}) {
    if (!_isInitialized) {
      debugPrint('通知服务: 未初始化，无法启动后台通知');
      return;
    }

    // 🆕 检查通知是否被用户禁用
    if (!_notificationsEnabled) {
      debugPrint('通知服务: 通知已被用户禁用');
      return;
    }

    // 取消之前的通知定时器
    stopBackgroundNotifications();

    // 记录活动开始时间
    _activityStartTime = startTime ?? DateTime.now();

    // 🆕 重置失败计数
    _notificationFailCount = 0;

    debugPrint(
        '通知服务: 开始后台通知 - 活动: $activityName, 间隔: $_notificationIntervalMinutes 分钟, 免打扰: $_doNotDisturbEnabled');

    // 🆕 立即发送第一条通知（如果不在免打扰时段）
    final now = DateTime.now();
    if (!_isInDoNotDisturbPeriod() &&
        (_lastNotificationTime == null ||
            now.difference(_lastNotificationTime!).inMinutes >=
                _notificationIntervalMinutes)) {
      _sendTimerNotification(activityName);
    }

    // 🆕 使用可配置的定时器间隔
    _notificationTimer = Timer.periodic(
      Duration(minutes: _notificationIntervalMinutes),
      (timer) {
        // 🆕 检查免打扰时段
        if (_isInDoNotDisturbPeriod()) {
          debugPrint('通知服务: 当前处于免打扰时段，跳过通知');
          return;
        }
        _sendTimerNotification(activityName);
      },
    );
  }

  /// 停止后台通知
  void stopBackgroundNotifications() {
    if (_notificationTimer != null) {
      debugPrint('通知服务: 停止后台通知');
      _notificationTimer?.cancel();
      _notificationTimer = null;
      _activityStartTime = null; // 清除开始时间
    }

    // 🆕 同时取消历史保存定时器（如果计时器停止，不再需要延迟保存）
    if (_historySaveTimer != null && _historyNeedsSave) {
      _historySaveTimer?.cancel();
      _historySaveTimer = null;
      // 立即保存历史记录
      _saveNotificationHistory();
    }
  }

  /// 发送计时提醒通知
  Future<void> _sendTimerNotification(String activityName,
      {int retryCount = 0}) async {
    if (!_isInitialized) return;

    try {
      _lastNotificationTime = DateTime.now();

      // 计算已记录的时长
      String durationText = '未知时长';
      int progressPercent = 0;
      if (_activityStartTime != null) {
        final duration = DateTime.now().difference(_activityStartTime!);
        final hours = duration.inHours;
        final minutes = duration.inMinutes.remainder(60);

        if (hours > 0) {
          durationText = '已记录 $hours小时$minutes分钟';
        } else {
          durationText = '已记录 $minutes分钟';
        }

        // 🆕 计算进度百分比（假设目标是2小时）
        progressPercent =
            ((duration.inMinutes / 120) * 100).clamp(0, 100).toInt();
      }

      // 🆕 通知去重检查
      final currentContent = '$activityName-$durationText-$progressPercent';
      final now = DateTime.now();

      if (_lastNotificationContent == currentContent &&
          _lastNotificationContentTime != null &&
          now.difference(_lastNotificationContentTime!) <
              _deduplicationWindow) {
        debugPrint(
            '通知服务: 检测到重复通知内容，跳过发送 (距上次 ${now.difference(_lastNotificationContentTime!).inSeconds} 秒)');
        return;
      }

      // 更新去重信息
      _lastNotificationContent = currentContent;
      _lastNotificationContentTime = now;

      // 🆕 增加通知计数
      await _incrementNotificationCount();

      // 🆕 Android 通知操作按钮
      final List<AndroidNotificationAction> actions = [
        const AndroidNotificationAction(
          'view_action',
          '查看详情',
          showsUserInterface: true,
          icon: DrawableResourceAndroidBitmap('ic_launcher'),
        ),
        const AndroidNotificationAction(
          'pause_action',
          '暂停',
          showsUserInterface: false,
        ),
        const AndroidNotificationAction(
          'stop_action',
          '停止',
          showsUserInterface: false,
          cancelNotification: true, // 停止后取消通知
        ),
      ];

      // 🆕 改进的通知内容
      final String notificationBody =
          '📌 活动: $activityName\n⏱️ $durationText\n📊 进度: $progressPercent%\n\n💡 点击查看详情或返回应用继续记录';

      // 🆕 根据时长动态调整通知优先级和重要性
      final importance = _getNotificationImportance(progressPercent);
      final priority = _getNotificationPriority(progressPercent);

      final androidDetails = AndroidNotificationDetails(
        _channelId, // 使用常量通道ID
        _channelName, // 使用常量通道名称
        channelDescription: _channelDescription,
        importance: importance, // 🆕 动态重要性
        priority: priority, // 🆕 动态优先级
        showWhen: true,
        enableVibration: _notificationVibration, // 🆕 使用用户配置
        playSound: _notificationSound, // 🆕 使用用户配置
        ongoing: true, // 设置为持续通知，不能被滑动清除
        autoCancel: false, // 点击后不自动取消
        category: AndroidNotificationCategory.progress, // 进度类别
        actions: actions, // 🆕 添加操作按钮
        // 🆕 添加进度条显示
        showProgress: true,
        maxProgress: 100,
        progress: progressPercent,
        styleInformation: BigTextStyleInformation(
          notificationBody,
          htmlFormatBigText: false,
          contentTitle: '⏱️ 计时进行中',
          htmlFormatContentTitle: false,
          summaryText: '已发送 $_notificationCount 次提醒', // 🆕 显示提醒次数
          htmlFormatSummaryText: false,
        ),
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true, // iOS 声音通过系统设置控制
        subtitle: '点击返回应用', // 🆕 添加副标题
        // 🆕 iOS 也显示时长信息
        threadIdentifier: 'timer_thread',
        interruptionLevel: InterruptionLevel.active, // 活跃级别通知
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        0, // 通知ID (使用固定ID，新通知会替换旧通知)
        '⏱️ 计时进行中',
        '$activityName - $durationText', // 显示时长
        details,
        payload: 'timer_reminder',
      );

      // 🆕 通知发送成功，重置失败计数
      _notificationFailCount = 0;

      // 🆕 添加到历史记录
      _notificationHistory.add(NotificationHistoryItem(
        timestamp: DateTime.now(),
        activityName: activityName,
        durationText: durationText,
        progressPercent: progressPercent,
      ));

      // 🆕 标记需要保存（使用批量保存策略）
      _markHistoryForSave();

      debugPrint(
          '通知服务: 已发送通知 #$_notificationCount - $activityName ($durationText, 进度: $progressPercent%)');
    } catch (e) {
      debugPrint('通知服务: 发送通知失败 - $e');
      _notificationFailCount++;

      // 🆕 重试机制：最多重试3次
      if (retryCount < 3) {
        debugPrint('通知服务: 将在5秒后重试发送通知 (重试次数: ${retryCount + 1}/3)');
        await Future.delayed(const Duration(seconds: 5));
        await _sendTimerNotification(activityName, retryCount: retryCount + 1);
      } else {
        debugPrint('通知服务: 通知发送失败次数过多，停止重试。累计失败: $_notificationFailCount 次');
      }
    }
  }

  /// 取消所有通知
  Future<void> cancelAllNotifications() async {
    if (_isInitialized) {
      await _notifications.cancelAll();
      debugPrint('通知服务: 已取消所有通知');
    }
  }

  /// 🆕 预览通知 - 用于测试通知效果
  Future<void> previewNotification(String activityName,
      {String durationText = '已记录 25分钟', int progressPercent = 25}) async {
    if (!_isInitialized) {
      debugPrint('通知服务: 未初始化，无法预览通知');
      return;
    }

    try {
      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        enableVibration: _notificationVibration,
        playSound: _notificationSound,
        ongoing: false, // 预览通知可以滑动清除
        autoCancel: true,
        category: AndroidNotificationCategory.progress,
        showProgress: true,
        maxProgress: 100,
        progress: progressPercent,
        styleInformation: BigTextStyleInformation(
          '📌 活动: $activityName\n⏱️ $durationText\n📊 进度: $progressPercent%\n\n💡 这是一条预览通知',
          htmlFormatBigText: false,
          contentTitle: '⏱️ 计时进行中 (预览)',
          htmlFormatContentTitle: false,
          summaryText: '通知预览',
          htmlFormatSummaryText: false,
        ),
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        subtitle: '这是一条预览通知',
        threadIdentifier: 'preview_thread',
        interruptionLevel: InterruptionLevel.active,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        999, // 使用特殊ID避免与实际通知冲突
        '⏱️ 计时进行中 (预览)',
        '$activityName - $durationText',
        details,
        payload: 'preview',
      );

      debugPrint('通知服务: 已发送预览通知');
    } catch (e) {
      debugPrint('通知服务: 预览通知失败 - $e');
    }
  }

  /// 清理资源
  Future<void> dispose() async {
    debugPrint('通知服务: 开始清理资源');

    // 停止所有定时器和通知
    stopBackgroundNotifications();

    // 🆕 确保历史保存定时器被取消
    _historySaveTimer?.cancel();
    _historySaveTimer = null;

    // 🆕 在 dispose 时保存一次历史记录
    if (_historyNeedsSave) {
      await _saveNotificationHistory();
    }

    // 取消所有通知
    await cancelAllNotifications();

    // 清除所有回调避免内存泄漏
    clearAllCallbacks();

    // 清除缓存
    _prefs = null;

    // 🆕 清理内存中的历史记录
    _notificationHistory.clear();

    // 🆕 重置所有状态
    _lastNotificationTime = null;
    _activityStartTime = null;
    _notificationFailCount = 0;
    _historyNeedsSave = false;

    debugPrint('通知服务: 资源清理完成');
  }
}
