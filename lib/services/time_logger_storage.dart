import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';

/// 活动记录数据模型
class ActivityRecordData {
  final int? id; // 数据库ID，用于更新和删除
  final String name;
  final DateTime startTime;
  final DateTime? endTime;
  final String? linkedTodoId;
  final String? linkedTodoTitle;

  ActivityRecordData({
    this.id,
    required this.name,
    required this.startTime,
    this.endTime,
    this.linkedTodoId,
    this.linkedTodoTitle,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'linkedTodoId': linkedTodoId,
        'linkedTodoTitle': linkedTodoTitle,
      };

  factory ActivityRecordData.fromJson(Map<String, dynamic> json) =>
      ActivityRecordData(
        id: json['id'] as int?,
        name: json['name'] as String,
        startTime: DateTime.parse(json['startTime'] as String),
        endTime: json['endTime'] != null
            ? DateTime.parse(json['endTime'] as String)
            : null,
        linkedTodoId: json['linkedTodoId'] as String?,
        linkedTodoTitle: json['linkedTodoTitle'] as String?,
      );

  // 创建一个副本，支持修改字段
  ActivityRecordData copyWith({
    int? id,
    String? name,
    DateTime? startTime,
    DateTime? endTime,
    String? linkedTodoId,
    String? linkedTodoTitle,
    bool clearLinkedTodo = false,
  }) {
    return ActivityRecordData(
      id: id ?? this.id,
      name: name ?? this.name,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      linkedTodoId:
          clearLinkedTodo ? null : (linkedTodoId ?? this.linkedTodoId),
      linkedTodoTitle:
          clearLinkedTodo ? null : (linkedTodoTitle ?? this.linkedTodoTitle),
    );
  }
}

/// 时间记录存储服务 - 使用 SQLite
class TimeLoggerStorage {
  static final _db = DatabaseService();

  // ==================== 活动记录 ====================

  /// 保存活动记录+
  static Future<int> addRecord(ActivityRecordData record) async {
    final id = await _db.insertActivityRecord({
      'name': record.name,
      'start_time': record.startTime.millisecondsSinceEpoch,
      'end_time': record.endTime?.millisecondsSinceEpoch,
      'linked_todo_id': record.linkedTodoId,
      'linked_todo_title': record.linkedTodoTitle,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });

    // 记录活动使用历史
    await _db.recordActivityUsage(record.name);

    return id;
  }

  /// 获取所有记录 (带缓存)
  static List<ActivityRecordData>? _cachedRecords;
  static DateTime? _cacheTime;

  static Future<List<ActivityRecordData>> getAllRecords({
    bool forceRefresh = false,
  }) async {
    // 缓存 5 分钟
    if (!forceRefresh &&
        _cachedRecords != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < const Duration(minutes: 5)) {
      return _cachedRecords!;
    }

    final records = await _db.getActivityRecords();
    _cachedRecords = records.map(_mapToRecord).toList();
    _cacheTime = DateTime.now();

    return _cachedRecords!;
  }

  /// 获取最近 N 天的记录 (优化版)
  static Future<List<ActivityRecordData>> getRecentRecords(int days) async {
    final records = await _db.getRecentActivityRecords(days);
    return records.map(_mapToRecord).toList();
  }

  /// 获取分页记录
  static Future<List<ActivityRecordData>> getPagedRecords({
    required int page,
    int pageSize = 50,
  }) async {
    final offset = page * pageSize;
    final records = await _db.getActivityRecords(
      limit: pageSize,
      offset: offset,
    );
    return records.map(_mapToRecord).toList();
  }

  /// 更新记录
  static Future<void> updateRecord(int id, ActivityRecordData record) async {
    await _db.updateActivityRecord(id, {
      'name': record.name,
      'start_time': record.startTime.millisecondsSinceEpoch,
      'end_time': record.endTime?.millisecondsSinceEpoch,
      'linked_todo_id': record.linkedTodoId,
      'linked_todo_title': record.linkedTodoTitle,
    });

    // 清除缓存
    _cachedRecords = null;
  }

  /// 删除记录
  static Future<void> deleteRecord(int id) async {
    await _db.deleteActivityRecord(id);

    // 清除缓存
    _cachedRecords = null;
  }

  /// 获取记录总数
  static Future<int> getRecordCount() async {
    return await _db.getActivityRecordCount();
  }

  // ==================== 当前活动 ====================

  static const String _keyCurrentActivity = 'current_activity_v2';
  static const String _keyContinuousStart = 'continuous_start_v2';

  /// 保存当前活动 (依然使用 SharedPreferences,因为需要快速读写)
  static Future<void> saveCurrentActivity(ActivityRecordData? activity) async {
    final prefs = await SharedPreferences.getInstance();
    if (activity == null) {
      await prefs.remove(_keyCurrentActivity);
    } else {
      final json = activity.toJson();
      await prefs.setString(_keyCurrentActivity, jsonEncode(json));
    }
  }

  /// 获取当前活动
  static Future<ActivityRecordData?> getCurrentActivity() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyCurrentActivity);
    if (jsonStr == null) return null;

    final json = jsonDecode(jsonStr);
    return ActivityRecordData.fromJson(json);
  }

  /// 保存连续记录开始时间
  static Future<void> saveContinuousStartTime(DateTime? time) async {
    final prefs = await SharedPreferences.getInstance();
    if (time == null) {
      await prefs.remove(_keyContinuousStart);
    } else {
      await prefs.setString(_keyContinuousStart, time.toIso8601String());
    }
  }

  /// 获取连续记录开始时间
  static Future<DateTime?> getContinuousStartTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(_keyContinuousStart);
    if (timeStr == null) return null;
    return DateTime.parse(timeStr);
  }

  // ==================== 活动历史 ====================

  /// 获取活动历史 (自动完成)
  static Future<Set<String>> getActivityHistory() async {
    final history = await _db.getActivityHistory();
    return history.toSet();
  }

  // ==================== 辅助方法 ====================

  static ActivityRecordData _mapToRecord(Map<String, dynamic> map) {
    return ActivityRecordData(
      id: map['id'] as int?,
      name: map['name'] as String,
      startTime: DateTime.fromMillisecondsSinceEpoch(map['start_time'] as int),
      endTime: map['end_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['end_time'] as int)
          : null,
      linkedTodoId: map['linked_todo_id'] as String?,
      linkedTodoTitle: map['linked_todo_title'] as String?,
    );
  }

  /// 清除缓存
  static void clearCache() {
    _cachedRecords = null;
    _cacheTime = null;
  }
}
