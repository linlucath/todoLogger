import 'time_logger_storage.dart';

/// 统计数据模型
class StatisticsData {
  final Map<String, ActivityStats> activityStats; // 按活动名称统计
  final List<DailyStats> dailyStats; // 每日统计
  final int totalSeconds; // 总秒数
  final int activityCount; // 活动种类数量
  final DateTime startDate; // 统计开始日期
  final DateTime endDate; // 统计结束日期

  StatisticsData({
    required this.activityStats,
    required this.dailyStats,
    required this.totalSeconds,
    required this.activityCount,
    required this.startDate,
    required this.endDate,
  });

  /// 总小时数
  double get totalHours => totalSeconds / 3600;

  /// 日均小时数
  double get avgHoursPerDay {
    final days = endDate.difference(startDate).inDays + 1;
    return days > 0 ? totalHours / days : 0;
  }
}

/// 单个活动的统计数据
class ActivityStats {
  final String name;
  final int totalSeconds;
  final int recordCount;

  ActivityStats({
    required this.name,
    required this.totalSeconds,
    required this.recordCount,
  });

  double get hours => totalSeconds / 3600;
}

/// 每日统计数据
class DailyStats {
  final DateTime date;
  final int totalSeconds;

  DailyStats({
    required this.date,
    required this.totalSeconds,
  });

  double get hours => totalSeconds / 3600;
}

/// 统计服务
class StatisticsService {
  /// 获取指定时间段的统计数据
  static Future<StatisticsData> getStatistics({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    // 获取时间段内的所有记录
    final allRecords = await TimeLoggerStorage.getAllRecords();

    // 过滤出指定时间段内的记录（只统计已完成的记录）
    final records = allRecords.where((record) {
      if (record.endTime == null) return false; // 未完成的不统计

      final recordDate = record.startTime;
      return recordDate.isAfter(startDate.subtract(const Duration(days: 1))) &&
          recordDate.isBefore(endDate.add(const Duration(days: 1)));
    }).toList();

    // 按活动名称分组统计
    final Map<String, ActivityStats> activityStats = {};
    for (final record in records) {
      final duration = record.endTime!.difference(record.startTime).inSeconds;

      if (activityStats.containsKey(record.name)) {
        final existing = activityStats[record.name]!;
        activityStats[record.name] = ActivityStats(
          name: record.name,
          totalSeconds: existing.totalSeconds + duration,
          recordCount: existing.recordCount + 1,
        );
      } else {
        activityStats[record.name] = ActivityStats(
          name: record.name,
          totalSeconds: duration,
          recordCount: 1,
        );
      }
    }

    // 按日期统计
    final Map<String, int> dailySecondsMap = {};
    for (final record in records) {
      final dateKey = _getDateKey(record.startTime);
      final duration = record.endTime!.difference(record.startTime).inSeconds;
      dailySecondsMap[dateKey] = (dailySecondsMap[dateKey] ?? 0) + duration;
    }

    // 转换为列表并排序
    final dailyStats = dailySecondsMap.entries.map((entry) {
      return DailyStats(
        date: DateTime.parse(entry.key),
        totalSeconds: entry.value,
      );
    }).toList()
      ..sort((a, b) => a.date.compareTo(b.date));

    // 计算总秒数
    final totalSeconds =
        activityStats.values.fold(0, (sum, stats) => sum + stats.totalSeconds);

    return StatisticsData(
      activityStats: activityStats,
      dailyStats: dailyStats,
      totalSeconds: totalSeconds,
      activityCount: activityStats.length,
      startDate: startDate,
      endDate: endDate,
    );
  }

  /// 获取今日统计
  static Future<StatisticsData> getTodayStatistics() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    return getStatistics(startDate: today, endDate: tomorrow);
  }

  /// 获取本周统计
  static Future<StatisticsData> getWeekStatistics() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 本周一
    final weekday = now.weekday; // 1=Monday, 7=Sunday
    final monday = today.subtract(Duration(days: weekday - 1));
    final nextMonday = monday.add(const Duration(days: 7));

    return getStatistics(startDate: monday, endDate: nextMonday);
  }

  /// 获取本月统计
  static Future<StatisticsData> getMonthStatistics() async {
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);

    return getStatistics(startDate: firstDay, endDate: nextMonth);
  }

  /// 获取本年统计
  static Future<StatisticsData> getYearStatistics() async {
    final now = DateTime.now();
    final firstDay = DateTime(now.year, 1, 1);
    final nextYear = DateTime(now.year + 1, 1, 1);

    return getStatistics(startDate: firstDay, endDate: nextYear);
  }

  /// 获取最近N天的统计
  static Future<StatisticsData> getRecentDaysStatistics(int days) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDate = today.subtract(Duration(days: days - 1));
    final endDate = today.add(const Duration(days: 1));

    return getStatistics(startDate: startDate, endDate: endDate);
  }

  /// 获取日期键（用于分组）
  static String _getDateKey(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  /// 为活动名称生成颜色
  static int getColorForActivity(String activityName) {
    // 使用活动名称的哈希值生成一致的颜色
    final hash = activityName.hashCode;

    // 预定义的漂亮颜色列表
    final colors = [
      0xFF6C63FF, // 紫色
      0xFF4CAF50, // 绿色
      0xFFFF6584, // 粉色
      0xFFFF9800, // 橙色
      0xFF9C27B0, // 紫红
      0xFF607D8B, // 蓝灰
      0xFF2196F3, // 蓝色
      0xFFFF5722, // 深橙
      0xFF009688, // 青色
      0xFFE91E63, // 粉红
      0xFF3F51B5, // 靛蓝
      0xFF8BC34A, // 浅绿
      0xFFFFC107, // 琥珀
      0xFF00BCD4, // 青蓝
      0xFFCDDC39, // 柠檬绿
    ];

    return colors[hash.abs() % colors.length];
  }
}
