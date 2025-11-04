/// 同步模式
enum SyncMode {
  incremental, // 增量同步：只同步修改过的数据
  full, // 全量同步：同步所有数据
}

/// 可同步数据的基类接口
abstract class SyncableData {
  SyncMetadata get syncMetadata;
}

/// 同步元数据 - 用于冲突检测和解决（Git-style 三方合并）
class SyncMetadata {
  final DateTime lastModifiedAt; // 最后修改时间
  final String lastModifiedBy; // 最后修改的设备ID
  final int version; // 版本号
  final bool isDeleted; // 是否已删除

  // 🆕 Git-style 共同祖先跟踪
  final DateTime? baseModifiedAt; // 上次同步时的修改时间（共同祖先）
  final int? baseVersion; // 上次同步时的版本号（共同祖先）
  final String? baseModifiedBy; // 上次同步时的修改者

  SyncMetadata({
    required this.lastModifiedAt,
    required this.lastModifiedBy,
    this.version = 1,
    this.isDeleted = false,
    this.baseModifiedAt,
    this.baseVersion,
    this.baseModifiedBy,
  });

  Map<String, dynamic> toJson() => {
        'lastModifiedAt': lastModifiedAt.toIso8601String(),
        'lastModifiedBy': lastModifiedBy,
        'version': version,
        'isDeleted': isDeleted,
        'baseModifiedAt': baseModifiedAt?.toIso8601String(),
        'baseVersion': baseVersion,
        'baseModifiedBy': baseModifiedBy,
      };

  factory SyncMetadata.fromJson(Map<String, dynamic> json) => SyncMetadata(
        lastModifiedAt: DateTime.parse(json['lastModifiedAt'] as String),
        lastModifiedBy: json['lastModifiedBy'] as String,
        version: json['version'] as int? ?? 1,
        isDeleted: json['isDeleted'] as bool? ?? false,
        baseModifiedAt: json['baseModifiedAt'] != null
            ? DateTime.parse(json['baseModifiedAt'] as String)
            : null,
        baseVersion: json['baseVersion'] as int?,
        baseModifiedBy: json['baseModifiedBy'] as String?,
      );

  SyncMetadata copyWith({
    DateTime? lastModifiedAt,
    String? lastModifiedBy,
    int? version,
    bool? isDeleted,
    DateTime? baseModifiedAt,
    int? baseVersion,
    String? baseModifiedBy,
  }) {
    return SyncMetadata(
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      lastModifiedBy: lastModifiedBy ?? this.lastModifiedBy,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
      baseModifiedAt: baseModifiedAt ?? this.baseModifiedAt,
      baseVersion: baseVersion ?? this.baseVersion,
      baseModifiedBy: baseModifiedBy ?? this.baseModifiedBy,
    );
  }

  /// 创建新的元数据
  static SyncMetadata create(String deviceId) {
    return SyncMetadata(
      lastModifiedAt: DateTime.now(),
      lastModifiedBy: deviceId,
      version: 1,
      isDeleted: false,
    );
  }

  /// 更新元数据
  SyncMetadata update(String deviceId) {
    return SyncMetadata(
      lastModifiedAt: DateTime.now(),
      lastModifiedBy: deviceId,
      version: version + 1,
      isDeleted: false,
      // 保留当前的 base 信息
      baseModifiedAt: baseModifiedAt,
      baseVersion: baseVersion,
      baseModifiedBy: baseModifiedBy,
    );
  }

  /// 标记为删除
  SyncMetadata markDeleted(String deviceId) {
    return SyncMetadata(
      lastModifiedAt: DateTime.now(),
      lastModifiedBy: deviceId,
      version: version + 1,
      isDeleted: true,
      baseModifiedAt: baseModifiedAt,
      baseVersion: baseVersion,
      baseModifiedBy: baseModifiedBy,
    );
  }

  /// 🆕 同步后更新 base（记录共同祖先）
  SyncMetadata updateBase() {
    return SyncMetadata(
      lastModifiedAt: lastModifiedAt,
      lastModifiedBy: lastModifiedBy,
      version: version,
      isDeleted: isDeleted,
      // 当前状态作为新的 base
      baseModifiedAt: lastModifiedAt,
      baseVersion: version,
      baseModifiedBy: lastModifiedBy,
    );
  }
}

/// 带同步元数据的待办事项
class SyncableTodoItem implements SyncableData {
  final String id;
  final String title;
  final String? description;
  final bool isCompleted;
  final DateTime createdAt;
  final String? listId;
  @override
  final SyncMetadata syncMetadata;

  SyncableTodoItem({
    required this.id,
    required this.title,
    this.description,
    this.isCompleted = false,
    required this.createdAt,
    this.listId,
    required this.syncMetadata,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'isCompleted': isCompleted,
        'createdAt': createdAt.toIso8601String(),
        'listId': listId,
        'syncMetadata': syncMetadata.toJson(),
      };

  factory SyncableTodoItem.fromJson(Map<String, dynamic> json) =>
      SyncableTodoItem(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        isCompleted: json['isCompleted'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        listId: json['listId'] as String?,
        syncMetadata:
            SyncMetadata.fromJson(json['syncMetadata'] as Map<String, dynamic>),
      );

  SyncableTodoItem copyWith({
    String? id,
    String? title,
    String? description,
    bool? isCompleted,
    DateTime? createdAt,
    String? listId,
    SyncMetadata? syncMetadata,
  }) {
    return SyncableTodoItem(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: createdAt ?? this.createdAt,
      listId: listId ?? this.listId,
      syncMetadata: syncMetadata ?? this.syncMetadata,
    );
  }
}

/// 带同步元数据的待办列表
class SyncableTodoList implements SyncableData {
  final String id;
  final String name;
  final bool isExpanded;
  final int colorValue;
  final List<String> itemIds;
  @override
  final SyncMetadata syncMetadata;

  SyncableTodoList({
    required this.id,
    required this.name,
    this.isExpanded = true,
    this.colorValue = 0xFF2196F3,
    List<String>? itemIds,
    required this.syncMetadata,
  }) : itemIds = itemIds ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isExpanded': isExpanded,
        'colorValue': colorValue,
        'itemIds': itemIds,
        'syncMetadata': syncMetadata.toJson(),
      };

  factory SyncableTodoList.fromJson(Map<String, dynamic> json) =>
      SyncableTodoList(
        id: json['id'] as String,
        name: json['name'] as String,
        isExpanded: json['isExpanded'] as bool? ?? true,
        colorValue: json['colorValue'] as int? ?? 0xFF2196F3,
        itemIds: (json['itemIds'] as List<dynamic>?)?.cast<String>() ?? [],
        syncMetadata:
            SyncMetadata.fromJson(json['syncMetadata'] as Map<String, dynamic>),
      );

  SyncableTodoList copyWith({
    String? id,
    String? name,
    bool? isExpanded,
    int? colorValue,
    List<String>? itemIds,
    SyncMetadata? syncMetadata,
  }) {
    return SyncableTodoList(
      id: id ?? this.id,
      name: name ?? this.name,
      isExpanded: isExpanded ?? this.isExpanded,
      colorValue: colorValue ?? this.colorValue,
      itemIds: itemIds ?? this.itemIds,
      syncMetadata: syncMetadata ?? this.syncMetadata,
    );
  }
}

/// 带同步元数据的时间日志
class SyncableTimeLog implements SyncableData {
  final String id; // 数据库ID
  final String activityId; // 活动计时器的唯一标识符（用于跨设备同步）
  final String name;
  final DateTime startTime;
  final DateTime? endTime;
  final String? linkedTodoId;
  final String? linkedTodoTitle;
  @override
  final SyncMetadata syncMetadata;

  SyncableTimeLog({
    required this.id,
    required this.activityId,
    required this.name,
    required this.startTime,
    this.endTime,
    this.linkedTodoId,
    this.linkedTodoTitle,
    required this.syncMetadata,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'activityId': activityId, // 🆕 包含activityId
        'name': name,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime?.toIso8601String(),
        'linkedTodoId': linkedTodoId,
        'linkedTodoTitle': linkedTodoTitle,
        'syncMetadata': syncMetadata.toJson(),
      };

  factory SyncableTimeLog.fromJson(Map<String, dynamic> json) =>
      SyncableTimeLog(
        id: json['id'] as String,
        activityId: json['activityId'] as String, // 🆕 从JSON读取activityId
        name: json['name'] as String,
        startTime: DateTime.parse(json['startTime'] as String),
        endTime: json['endTime'] != null
            ? DateTime.parse(json['endTime'] as String)
            : null,
        linkedTodoId: json['linkedTodoId'] as String?,
        linkedTodoTitle: json['linkedTodoTitle'] as String?,
        syncMetadata:
            SyncMetadata.fromJson(json['syncMetadata'] as Map<String, dynamic>),
      );

  SyncableTimeLog copyWith({
    String? id,
    String? activityId, // 🆕 添加activityId参数
    String? name,
    DateTime? startTime,
    DateTime? endTime,
    String? linkedTodoId,
    String? linkedTodoTitle,
    SyncMetadata? syncMetadata,
  }) {
    return SyncableTimeLog(
      id: id ?? this.id,
      activityId: activityId ?? this.activityId, // 🆕 使用activityId
      name: name ?? this.name,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      linkedTodoId: linkedTodoId ?? this.linkedTodoId,
      linkedTodoTitle: linkedTodoTitle ?? this.linkedTodoTitle,
      syncMetadata: syncMetadata ?? this.syncMetadata,
    );
  }
}

/// 带同步元数据的目标
class SyncableTarget implements SyncableData {
  final String id;
  final String name;
  final int type; // TargetType enum index
  final int period; // TimePeriod enum index
  final int targetSeconds;
  final List<String> linkedTodoIds;
  final List<String> linkedListIds;
  final DateTime createdAt;
  final bool isActive;
  final int colorValue;
  @override
  final SyncMetadata syncMetadata;

  SyncableTarget({
    required this.id,
    required this.name,
    required this.type,
    required this.period,
    required this.targetSeconds,
    required this.linkedTodoIds,
    required this.linkedListIds,
    required this.createdAt,
    required this.isActive,
    required this.colorValue,
    required this.syncMetadata,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'period': period,
        'targetSeconds': targetSeconds,
        'linkedTodoIds': linkedTodoIds,
        'linkedListIds': linkedListIds,
        'createdAt': createdAt.toIso8601String(),
        'isActive': isActive,
        'colorValue': colorValue,
        'syncMetadata': syncMetadata.toJson(),
      };

  factory SyncableTarget.fromJson(Map<String, dynamic> json) => SyncableTarget(
        id: json['id'] as String,
        name: json['name'] as String,
        type: json['type'] as int,
        period: json['period'] as int,
        targetSeconds: json['targetSeconds'] as int,
        linkedTodoIds: (json['linkedTodoIds'] as List<dynamic>).cast<String>(),
        linkedListIds: (json['linkedListIds'] as List<dynamic>).cast<String>(),
        createdAt: DateTime.parse(json['createdAt'] as String),
        isActive: json['isActive'] as bool,
        colorValue: json['colorValue'] as int,
        syncMetadata:
            SyncMetadata.fromJson(json['syncMetadata'] as Map<String, dynamic>),
      );

  SyncableTarget copyWith({
    String? id,
    String? name,
    int? type,
    int? period,
    int? targetSeconds,
    List<String>? linkedTodoIds,
    List<String>? linkedListIds,
    DateTime? createdAt,
    bool? isActive,
    int? colorValue,
    SyncMetadata? syncMetadata,
  }) {
    return SyncableTarget(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      period: period ?? this.period,
      targetSeconds: targetSeconds ?? this.targetSeconds,
      linkedTodoIds: linkedTodoIds ?? this.linkedTodoIds,
      linkedListIds: linkedListIds ?? this.linkedListIds,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
      colorValue: colorValue ?? this.colorValue,
      syncMetadata: syncMetadata ?? this.syncMetadata,
    );
  }
}
