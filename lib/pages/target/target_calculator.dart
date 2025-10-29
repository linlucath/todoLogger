import 'package:intl/intl.dart';
import 'models.dart';
import '../../services/time_logger_storage.dart';
import '../../services/todo_storage.dart';

class TargetCalculator {
  /// 计算目标的当前周期
  DateTimeRange getCurrentPeriod(Target target) {
    final now = DateTime.now();
    DateTime periodStart;
    DateTime periodEnd;

    switch (target.period) {
      case TimePeriod.daily:
        // 今天的 00:00 到 23:59:59
        periodStart = DateTime(now.year, now.month, now.day);
        periodEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
        break;

      case TimePeriod.weekly:
        // 本周一 00:00 到周日 23:59:59
        final weekday = now.weekday;
        periodStart = DateTime(now.year, now.month, now.day - (weekday - 1));
        periodEnd =
            DateTime(now.year, now.month, now.day + (7 - weekday), 23, 59, 59);
        break;

      case TimePeriod.monthly:
        // 本月1号 00:00 到月末 23:59:59
        periodStart = DateTime(now.year, now.month, 1);
        periodEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        break;

      case TimePeriod.yearly:
        // 今年1月1日 00:00 到12月31日 23:59:59
        periodStart = DateTime(now.year, 1, 1);
        periodEnd = DateTime(now.year, 12, 31, 23, 59, 59);
        break;
    }

    return DateTimeRange(start: periodStart, end: periodEnd);
  }

  /// 计算目标进度
  Future<TargetProgress> calculateProgress(Target target) async {
    print('📊 [TargetCalculator] 计算目标进度: ${target.name}');

    // 获取当前周期
    final period = getCurrentPeriod(target);
    print(
        '📅 [TargetCalculator] 周期: ${DateFormat('yyyy-MM-dd HH:mm').format(period.start)} - ${DateFormat('yyyy-MM-dd HH:mm').format(period.end)}');

    // 加载所有活动记录
    final allRecords = await TimeLoggerStorage.getAllRecords();
    print('📂 [TargetCalculator] 加载了 ${allRecords.length} 条活动记录');

    // 构建需要匹配的 TODO ID 集合
    Set<String> targetTodoIds = Set.from(target.linkedTodoIds);

    // 如果有关联的列表，需要获取列表中的所有 TODO
    if (target.linkedListIds.isNotEmpty) {
      final todoData = await TodoStorage.getAllData();
      final lists = todoData['lists'] as List<TodoListData>;

      for (final listId in target.linkedListIds) {
        final list = lists.where((l) => l.id == listId).firstOrNull;
        if (list != null) {
          targetTodoIds.addAll(list.itemIds);
          print(
              '📁 [TargetCalculator] 添加列表 "${list.name}" 中的 ${list.itemIds.length} 个 TODO');
        }
      }
    }

    // 如果目标没有关联任何 TODO 或列表，返回空进度
    if (targetTodoIds.isEmpty) {
      print('⚠️ [TargetCalculator] 目标未关联任何 TODO 或列表');
      return TargetProgress(
        target: target,
        currentSeconds: 0,
        periodStart: period.start,
        periodEnd: period.end,
      );
    }

    print('🎯 [TargetCalculator] 总共需要匹配 ${targetTodoIds.length} 个 TODO');

    // 筛选符合条件的记录：
    // 1. 记录的结束时间在当前周期内
    // 2. 记录关联的 TODO 在目标的 linkedTodoIds 中
    int totalSeconds = 0;
    int matchedCount = 0;

    for (final record in allRecords) {
      // 跳过未结束的记录
      if (record.endTime == null) continue;

      // 检查记录是否在当前周期内
      if (record.endTime!.isBefore(period.start) ||
          record.endTime!.isAfter(period.end)) {
        continue;
      }

      // 检查记录是否关联了目标中的 TODO
      if (record.linkedTodoId != null &&
          targetTodoIds.contains(record.linkedTodoId)) {
        // 计算记录的时长（秒）
        final duration = record.endTime!.difference(record.startTime).inSeconds;
        totalSeconds += duration;
        matchedCount++;
        print('  ✅ 匹配记录: ${record.name} (${duration}s)');
      }
    }

    print('📊 [TargetCalculator] 找到 $matchedCount 条匹配记录，总时长: $totalSeconds 秒');

    return TargetProgress(
      target: target,
      currentSeconds: totalSeconds,
      periodStart: period.start,
      periodEnd: period.end,
    );
  }

  /// 批量计算多个目标的进度
  Future<List<TargetProgress>> calculateMultipleProgress(
      List<Target> targets) async {
    final List<TargetProgress> progressList = [];

    for (final target in targets) {
      if (target.isActive) {
        final progress = await calculateProgress(target);
        progressList.add(progress);
      }
    }

    return progressList;
  }

  /// 获取周期的格式化文本
  String formatPeriod(DateTimeRange period, TimePeriod periodType) {
    final dateFormat = DateFormat('M月d日');

    switch (periodType) {
      case TimePeriod.daily:
        return DateFormat('yyyy年M月d日').format(period.start);
      case TimePeriod.weekly:
        return '${dateFormat.format(period.start)} - ${dateFormat.format(period.end)}';
      case TimePeriod.monthly:
        return DateFormat('yyyy年M月').format(period.start);
      case TimePeriod.yearly:
        return DateFormat('yyyy年').format(period.start);
    }
  }

  /// 检查目标是否需要重置（用于历史记录）
  bool shouldReset(Target target, DateTime lastCheckTime) {
    final lastPeriod = getCurrentPeriodAt(target, lastCheckTime);
    final currentPeriod = getCurrentPeriod(target);

    // 如果周期的开始时间不同，说明已经进入新周期
    return !lastPeriod.start.isAtSameMomentAs(currentPeriod.start);
  }

  /// 获取指定时间点的周期
  DateTimeRange getCurrentPeriodAt(Target target, DateTime time) {
    DateTime periodStart;
    DateTime periodEnd;

    switch (target.period) {
      case TimePeriod.daily:
        periodStart = DateTime(time.year, time.month, time.day);
        periodEnd = DateTime(time.year, time.month, time.day, 23, 59, 59);
        break;

      case TimePeriod.weekly:
        final weekday = time.weekday;
        periodStart = DateTime(time.year, time.month, time.day - (weekday - 1));
        periodEnd = DateTime(
            time.year, time.month, time.day + (7 - weekday), 23, 59, 59);
        break;

      case TimePeriod.monthly:
        periodStart = DateTime(time.year, time.month, 1);
        periodEnd = DateTime(time.year, time.month + 1, 0, 23, 59, 59);
        break;

      case TimePeriod.yearly:
        periodStart = DateTime(time.year, 1, 1);
        periodEnd = DateTime(time.year, 12, 31, 23, 59, 59);
        break;
    }

    return DateTimeRange(start: periodStart, end: periodEnd);
  }
}

/// 日期时间范围（简化版，Flutter 中 DateTimeRange 在 material.dart 中）
class DateTimeRange {
  final DateTime start;
  final DateTime end;

  DateTimeRange({required this.start, required this.end});
}
