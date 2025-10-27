import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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

class TimeLoggerStorage {
  static const String _keyCurrentActivity = 'time_logger_current_activity';
  static const String _keyContinuousStart = 'time_logger_continuous_start';
  static const String _keyAllRecords = 'time_logger_all_records';
  static const String _keyActivityHistory = 'time_logger_activity_history';

  // 保存当前活动
  static Future<void> saveCurrentActivity(ActivityRecordData? activity) async {
    final prefs = await SharedPreferences.getInstance();
    if (activity == null) {
      await prefs.remove(_keyCurrentActivity);
    } else {
      await prefs.setString(_keyCurrentActivity, jsonEncode(activity.toJson()));
    }
  }

  // 获取当前活动
  static Future<ActivityRecordData?> getCurrentActivity() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyCurrentActivity);
    if (jsonStr == null) return null;
    return ActivityRecordData.fromJson(jsonDecode(jsonStr));
  }

  // 保存连续记录开始时间
  static Future<void> saveContinuousStartTime(DateTime? time) async {
    final prefs = await SharedPreferences.getInstance();
    if (time == null) {
      await prefs.remove(_keyContinuousStart);
    } else {
      await prefs.setString(_keyContinuousStart, time.toIso8601String());
    }
  }

  // 获取连续记录开始时间
  static Future<DateTime?> getContinuousStartTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeStr = prefs.getString(_keyContinuousStart);
    if (timeStr == null) return null;
    return DateTime.parse(timeStr);
  }

  // 保存所有记录
  static Future<void> saveAllRecords(List<ActivityRecordData> records) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = records.map((r) => r.toJson()).toList();
    await prefs.setString(_keyAllRecords, jsonEncode(jsonList));
  }

  // 获取所有记录
  static Future<List<ActivityRecordData>> getAllRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyAllRecords);
    if (jsonStr == null) return [];
    final List<dynamic> jsonList = jsonDecode(jsonStr);
    return jsonList.map((json) => ActivityRecordData.fromJson(json)).toList();
  }

  // 添加单条记录
  static Future<void> addRecord(ActivityRecordData record) async {
    final records = await getAllRecords();
    records.add(record);
    await saveAllRecords(records);
  }

  // 保存活动历史
  static Future<void> saveActivityHistory(Set<String> history) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyActivityHistory, history.toList());
  }

  // 获取活动历史
  static Future<Set<String>> getActivityHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_keyActivityHistory);
    if (list == null) return {};
    return list.toSet();
  }

  // 清除所有数据
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCurrentActivity);
    await prefs.remove(_keyContinuousStart);
    await prefs.remove(_keyAllRecords);
    await prefs.remove(_keyActivityHistory);
  }
}
