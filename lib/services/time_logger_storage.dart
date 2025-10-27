import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_service.dart';

/// 活动记录数据模型
class ActivityRecordData {
  final String name;
  final DateTime startTime;
  final DateTime? endTime;
  final String? linkedTodoId;
  final String? linkedTodoTitle;

  ActivityRecordData({
    required this.name,
    required this.startTime,
    this.endTime,
    this.linkedTodoId,
    this.linkedTodoTitle,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'linkedTodoId': linkedTodoId,
        'linkedTodoTitle': linkedTodoTitle,
      };

  factory ActivityRecordData.fromJson(Map<String, dynamic> json) =>
      ActivityRecordData(
        name: json['name'] as String,
        startTime: DateTime.parse(json['startTime'] as String),
        endTime: json['endTime'] != null
            ? DateTime.parse(json['endTime'] as String)
            : null,
        linkedTodoId: json['linkedTodoId'] as String?,
        linkedTodoTitle: json['linkedTodoTitle'] as String?,
      );
}

/// 时间记录存储服务 - 使用 SQLite
class TimeLoggerStorage {
  static final _db = DatabaseService();

  // ==================== 活动记录 ====================

  /// 保存活动记录
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

  // ==================== 数据迁移 ====================

  /// 从旧的 SharedPreferences 迁移到 SQLite
  static Future<void> migrateFromOldStorage() async {
    final prefs = await SharedPreferences.getInstance();
    final migrated = prefs.getBool('migrated_to_sqlite') ?? false;

    if (migrated) return; // 已迁移

    print('🔄 开始数据迁移...');

    try {
      // 1. 迁移活动记录
      final oldRecordsJson = prefs.getString('time_logger_all_records');
      if (oldRecordsJson != null) {
        final List<dynamic> jsonList = jsonDecode(oldRecordsJson);
        final oldRecords =
            jsonList.map((json) => ActivityRecordData.fromJson(json)).toList();
        for (var record in oldRecords) {
          await addRecord(record);
        }
        print('✅ 迁移 ${oldRecords.length} 条活动记录');
      }

      // 2. 迁移活动历史
      final oldHistory = prefs.getStringList('time_logger_activity_history');
      if (oldHistory != null) {
        for (var name in oldHistory) {
          await _db.recordActivityUsage(name);
        }
        print('✅ 迁移 ${oldHistory.length} 条活动历史');
      }

      // 3. 清理旧数据
      await prefs.remove('time_logger_all_records');
      await prefs.remove('time_logger_activity_history');

      // 4. 标记已迁移
      await prefs.setBool('migrated_to_sqlite', true);
      print('✅ 数据迁移完成!');
    } catch (e) {
      print('❌ 数据迁移失败: $e');
      rethrow;
    }
  }

  // ==================== 辅助方法 ====================

  static ActivityRecordData _mapToRecord(Map<String, dynamic> map) {
    return ActivityRecordData(
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
