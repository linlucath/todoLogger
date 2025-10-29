import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 同步操作类型
enum SyncOperationType {
  push, // 推送数据到远程
  pull, // 从远程拉取数据
  conflict, // 冲突解决
  merge, // 合并数据
}

/// 同步历史记录
class SyncHistoryRecord {
  final String id;
  final DateTime timestamp;
  final SyncOperationType operationType;
  final String? deviceId; // 涉及的设备ID
  final String? deviceName; // 涉及的设备名称
  final String dataType; // 数据类型(todos, timeLogs等)
  final int itemCount; // 同步的项目数量
  final int conflictCount; // 冲突数量
  final String? description; // 描述
  final bool success; // 是否成功
  final String? errorMessage; // 错误信息

  SyncHistoryRecord({
    required this.id,
    DateTime? timestamp,
    required this.operationType,
    this.deviceId,
    this.deviceName,
    required this.dataType,
    this.itemCount = 0,
    this.conflictCount = 0,
    this.description,
    this.success = true,
    this.errorMessage,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'operationType': operationType.toString(),
        'deviceId': deviceId,
        'deviceName': deviceName,
        'dataType': dataType,
        'itemCount': itemCount,
        'conflictCount': conflictCount,
        'description': description,
        'success': success,
        'errorMessage': errorMessage,
      };

  factory SyncHistoryRecord.fromJson(Map<String, dynamic> json) =>
      SyncHistoryRecord(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        operationType: SyncOperationType.values.firstWhere(
          (e) => e.toString() == json['operationType'],
        ),
        deviceId: json['deviceId'] as String?,
        deviceName: json['deviceName'] as String?,
        dataType: json['dataType'] as String,
        itemCount: json['itemCount'] as int? ?? 0,
        conflictCount: json['conflictCount'] as int? ?? 0,
        description: json['description'] as String?,
        success: json['success'] as bool? ?? true,
        errorMessage: json['errorMessage'] as String?,
      );

  /// 获取操作类型的显示文本
  String get operationTypeText {
    switch (operationType) {
      case SyncOperationType.push:
        return '推送';
      case SyncOperationType.pull:
        return '拉取';
      case SyncOperationType.conflict:
        return '冲突解决';
      case SyncOperationType.merge:
        return '合并';
    }
  }

  /// 获取数据类型的显示文本
  String get dataTypeText {
    switch (dataType) {
      case 'todos':
        return '待办事项';
      case 'timeLogs':
        return '时间日志';
      case 'all':
        return '全部数据';
      default:
        return dataType;
    }
  }
}

/// 同步历史服务
class SyncHistoryService {
  static const String _keyHistoryRecords = 'sync_history_records';
  static const int _maxRecords = 100; // 最多保存100条记录

  final List<SyncHistoryRecord> _records = [];
  bool _isLoaded = false;

  /// 获取所有历史记录
  Future<List<SyncHistoryRecord>> getAllRecords() async {
    if (!_isLoaded) {
      await _loadRecords();
    }
    return List.from(_records);
  }

  /// 获取指定设备的历史记录
  Future<List<SyncHistoryRecord>> getRecordsByDevice(String deviceId) async {
    if (!_isLoaded) {
      await _loadRecords();
    }
    return _records.where((r) => r.deviceId == deviceId).toList();
  }

  /// 获取指定数据类型的历史记录
  Future<List<SyncHistoryRecord>> getRecordsByDataType(String dataType) async {
    if (!_isLoaded) {
      await _loadRecords();
    }
    return _records.where((r) => r.dataType == dataType).toList();
  }

  /// 获取最近的N条记录
  Future<List<SyncHistoryRecord>> getRecentRecords(int count) async {
    if (!_isLoaded) {
      await _loadRecords();
    }
    final sorted = List<SyncHistoryRecord>.from(_records)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return sorted.take(count).toList();
  }

  /// 添加历史记录
  Future<void> addRecord(SyncHistoryRecord record) async {
    if (!_isLoaded) {
      await _loadRecords();
    }

    _records.insert(0, record);

    // 保持记录数量在限制内
    if (_records.length > _maxRecords) {
      _records.removeRange(_maxRecords, _records.length);
    }

    await _saveRecords();
    print(
        '📝 [SyncHistory] 记录已保存: ${record.operationTypeText} ${record.dataTypeText}');
  }

  /// 记录推送操作
  Future<void> recordPush({
    required String deviceId,
    required String deviceName,
    required String dataType,
    required int itemCount,
    String? description,
    bool success = true,
    String? errorMessage,
  }) async {
    await addRecord(SyncHistoryRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      operationType: SyncOperationType.push,
      deviceId: deviceId,
      deviceName: deviceName,
      dataType: dataType,
      itemCount: itemCount,
      description: description,
      success: success,
      errorMessage: errorMessage,
    ));
  }

  /// 记录拉取操作
  Future<void> recordPull({
    required String deviceId,
    required String deviceName,
    required String dataType,
    required int itemCount,
    String? description,
    bool success = true,
    String? errorMessage,
  }) async {
    await addRecord(SyncHistoryRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      operationType: SyncOperationType.pull,
      deviceId: deviceId,
      deviceName: deviceName,
      dataType: dataType,
      itemCount: itemCount,
      description: description,
      success: success,
      errorMessage: errorMessage,
    ));
  }

  /// 记录冲突解决
  Future<void> recordConflict({
    required String deviceId,
    required String deviceName,
    required String dataType,
    required int conflictCount,
    String? description,
  }) async {
    await addRecord(SyncHistoryRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      operationType: SyncOperationType.conflict,
      deviceId: deviceId,
      deviceName: deviceName,
      dataType: dataType,
      conflictCount: conflictCount,
      description: description,
      success: true,
    ));
  }

  /// 记录合并操作
  Future<void> recordMerge({
    required String deviceId,
    required String deviceName,
    required String dataType,
    required int itemCount,
    String? description,
    bool success = true,
    String? errorMessage,
  }) async {
    await addRecord(SyncHistoryRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      operationType: SyncOperationType.merge,
      deviceId: deviceId,
      deviceName: deviceName,
      dataType: dataType,
      itemCount: itemCount,
      description: description,
      success: success,
      errorMessage: errorMessage,
    ));
  }

  /// 清除所有历史记录
  Future<void> clearAllRecords() async {
    _records.clear();
    await _saveRecords();
    print('🗑️  [SyncHistory] 已清除所有历史记录');
  }

  /// 清除指定天数之前的记录
  Future<void> clearOldRecords(int days) async {
    if (!_isLoaded) {
      await _loadRecords();
    }

    final cutoffDate = DateTime.now().subtract(Duration(days: days));
    _records.removeWhere((r) => r.timestamp.isBefore(cutoffDate));

    await _saveRecords();
    print('🗑️  [SyncHistory] 已清除 $days 天前的记录');
  }

  /// 获取统计信息
  Future<Map<String, dynamic>> getStatistics() async {
    if (!_isLoaded) {
      await _loadRecords();
    }

    final totalRecords = _records.length;
    final successCount = _records.where((r) => r.success).length;
    final failureCount = _records.where((r) => !r.success).length;
    final totalConflicts =
        _records.fold<int>(0, (sum, r) => sum + r.conflictCount);
    final totalItems = _records.fold<int>(0, (sum, r) => sum + r.itemCount);

    final lastSync = _records.isNotEmpty ? _records.first.timestamp : null;

    return {
      'totalRecords': totalRecords,
      'successCount': successCount,
      'failureCount': failureCount,
      'totalConflicts': totalConflicts,
      'totalItems': totalItems,
      'lastSync': lastSync?.toIso8601String(),
    };
  }

  /// 加载历史记录
  Future<void> _loadRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_keyHistoryRecords);

      if (jsonString != null) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        _records.clear();
        _records.addAll(
          jsonList.map((json) => SyncHistoryRecord.fromJson(json)).toList(),
        );
        print('📚 [SyncHistory] 已加载 ${_records.length} 条历史记录');
      }

      _isLoaded = true;
    } catch (e) {
      print('❌ [SyncHistory] 加载历史记录失败: $e');
      _isLoaded = true;
    }
  }

  /// 保存历史记录
  Future<void> _saveRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(
        _records.map((r) => r.toJson()).toList(),
      );
      await prefs.setString(_keyHistoryRecords, jsonString);
    } catch (e) {
      print('❌ [SyncHistory] 保存历史记录失败: $e');
    }
  }
}
