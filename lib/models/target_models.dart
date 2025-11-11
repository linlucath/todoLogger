import 'package:flutter/material.dart';

/// 目标类型
enum TargetType {
  achievement, // 达成目标（越多越好）
  limit, // 限制目标（不要超过）
}

/// 时间周期
enum TimePeriod {
  daily, // 每日
  weekly, // 每周
  monthly, // 每月
  yearly, // 每年
}

/// Target 数据模型
class Target {
  final String id;
  String name; // 目标名称，如 "学习时长"
  TargetType type; // 目标类型
  TimePeriod period; // 时间周期
  int targetSeconds; // 目标时长（秒）
  List<String> linkedTodoIds; // 关联的单个 TODO IDs
  List<String> linkedListIds; // 关联的整个 TODO List IDs
  DateTime createdAt; // 创建时间
  bool isActive; // 是否启用
  Color color; // 主题颜色

  Target({
    required this.id,
    required this.name,
    required this.type,
    required this.period,
    required this.targetSeconds,
    List<String>? linkedTodoIds,
    List<String>? linkedListIds,
    DateTime? createdAt,
    this.isActive = true,
    this.color = Colors.blue,
  })  : linkedTodoIds = linkedTodoIds ?? [],
        linkedListIds = linkedListIds ?? [],
        createdAt = createdAt ?? DateTime.now();

  /// 获取时间周期的显示文本
  String get periodText {
    switch (period) {
      case TimePeriod.daily:
        return '每日';
      case TimePeriod.weekly:
        return '每周';
      case TimePeriod.monthly:
        return '每月';
      case TimePeriod.yearly:
        return '每年';
    }
  }

  /// 获取目标类型的显示文本
  String get typeText {
    switch (type) {
      case TargetType.achievement:
        return '达成目标';
      case TargetType.limit:
        return '限制目标';
    }
  }

  /// 获取目标类型的图标
  IconData get typeIcon {
    switch (type) {
      case TargetType.achievement:
        return Icons.check_circle_outline;
      case TargetType.limit:
        return Icons.warning_amber_outlined;
    }
  }

  /// 格式化目标时长为可读文本
  String get targetTimeText {
    final hours = targetSeconds ~/ 3600;
    final minutes = (targetSeconds % 3600) ~/ 60;

    if (hours > 0 && minutes > 0) {
      return '$hours小时$minutes分钟';
    } else if (hours > 0) {
      return '$hours小时';
    } else {
      return '$minutes分钟';
    }
  }

  /// 从 JSON 创建 Target
  factory Target.fromJson(Map<String, dynamic> json) {
    return Target(
      id: json['id'] as String,
      name: json['name'] as String,
      type: TargetType.values[json['type'] as int],
      period: TimePeriod.values[json['period'] as int],
      targetSeconds: json['targetSeconds'] as int,
      linkedTodoIds:
          (json['linkedTodoIds'] as List<dynamic>?)?.cast<String>() ?? [],
      linkedListIds:
          (json['linkedListIds'] as List<dynamic>?)?.cast<String>() ?? [],
      createdAt: DateTime.parse(json['createdAt'] as String),
      isActive: json['isActive'] as bool? ?? true,
      color: Color(json['color'] as int? ?? Colors.blue.toARGB32()),
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type.index,
      'period': period.index,
      'targetSeconds': targetSeconds,
      'linkedTodoIds': linkedTodoIds,
      'linkedListIds': linkedListIds,
      'createdAt': createdAt.toIso8601String(),
      'isActive': isActive,
      'color': color.toARGB32(),
    };
  }

  /// 创建副本
  Target copyWith({
    String? id,
    String? name,
    TargetType? type,
    TimePeriod? period,
    int? targetSeconds,
    List<String>? linkedTodoIds,
    List<String>? linkedListIds,
    DateTime? createdAt,
    bool? isActive,
    Color? color,
  }) {
    return Target(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      period: period ?? this.period,
      targetSeconds: targetSeconds ?? this.targetSeconds,
      linkedTodoIds: linkedTodoIds ?? List.from(this.linkedTodoIds),
      linkedListIds: linkedListIds ?? List.from(this.linkedListIds),
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
      color: color ?? this.color,
    );
  }
}

/// 目标进度数据
class TargetProgress {
  final Target target;
  final int currentSeconds; // 当前已完成的秒数
  final DateTime periodStart; // 当前周期的开始时间
  final DateTime periodEnd; // 当前周期的结束时间

  TargetProgress({
    required this.target,
    required this.currentSeconds,
    required this.periodStart,
    required this.periodEnd,
  });

  /// 进度百分比 (0.0 - 1.0+)
  double get progressPercentage {
    if (target.targetSeconds == 0) return 0.0;
    return currentSeconds / target.targetSeconds;
  }

  /// 进度百分比文本
  String get progressPercentageText {
    return '${(progressPercentage * 100).toStringAsFixed(0)}%';
  }

  /// 剩余秒数（可能为负数）
  int get remainingSeconds => target.targetSeconds - currentSeconds;

  /// 是否已完成
  bool get isCompleted => currentSeconds >= target.targetSeconds;

  /// 是否超出限制
  bool get isOverLimit =>
      target.type == TargetType.limit && currentSeconds > target.targetSeconds;

  /// 警告状态（对于限制目标）
  /// 0-0.7: 安全（绿色）
  /// 0.7-0.9: 警告（橙色）
  /// 0.9+: 危险（红色）
  int get warningLevel {
    if (target.type != TargetType.limit) return 0;
    if (progressPercentage < 0.7) return 0;
    if (progressPercentage < 0.9) return 1;
    return 2;
  }

  /// 获取进度条颜色
  Color get progressColor {
    if (target.type == TargetType.achievement) {
      // 达成目标：总是使用目标颜色
      return target.color;
    } else {
      // 限制目标：根据警告级别
      switch (warningLevel) {
        case 0:
          return Colors.green;
        case 1:
          return Colors.orange;
        case 2:
          return Colors.red;
        default:
          return target.color;
      }
    }
  }

  /// 格式化当前时长
  String get currentTimeText {
    final hours = currentSeconds ~/ 3600;
    final minutes = (currentSeconds % 3600) ~/ 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  /// 格式化剩余时长
  String get remainingTimeText {
    final seconds = remainingSeconds.abs();
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;

    if (remainingSeconds < 0) {
      if (hours > 0) {
        return '超出 ${hours}h ${minutes}m';
      } else {
        return '超出 ${minutes}m';
      }
    } else {
      if (hours > 0) {
        return '还剩 ${hours}h ${minutes}m';
      } else {
        return '还剩 ${minutes}m';
      }
    }
  }
}
