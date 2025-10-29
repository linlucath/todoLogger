/// 同步元数据 - 用于冲突检测和解决
class SyncMetadata {
  final DateTime lastModifiedAt; // 最后修改时间
  final String lastModifiedBy; // 最后修改的设备ID
  final int version; // 版本号
  final bool isDeleted; // 是否已删除

  SyncMetadata({
    required this.lastModifiedAt,
    required this.lastModifiedBy,
    this.version = 1,
    this.isDeleted = false,
  });

  Map<String, dynamic> toJson() => {
        'lastModifiedAt': lastModifiedAt.toIso8601String(),
        'lastModifiedBy': lastModifiedBy,
        'version': version,
        'isDeleted': isDeleted,
      };

  factory SyncMetadata.fromJson(Map<String, dynamic> json) => SyncMetadata(
        lastModifiedAt: DateTime.parse(json['lastModifiedAt'] as String),
        lastModifiedBy: json['lastModifiedBy'] as String,
        version: json['version'] as int? ?? 1,
        isDeleted: json['isDeleted'] as bool? ?? false,
      );

  SyncMetadata copyWith({
    DateTime? lastModifiedAt,
    String? lastModifiedBy,
    int? version,
    bool? isDeleted,
  }) {
    return SyncMetadata(
      lastModifiedAt: lastModifiedAt ?? this.lastModifiedAt,
      lastModifiedBy: lastModifiedBy ?? this.lastModifiedBy,
      version: version ?? this.version,
      isDeleted: isDeleted ?? this.isDeleted,
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
    );
  }

  /// 标记为删除
  SyncMetadata markDeleted(String deviceId) {
    return SyncMetadata(
      lastModifiedAt: DateTime.now(),
      lastModifiedBy: deviceId,
      version: version + 1,
      isDeleted: true,
    );
  }
}

/// 带同步元数据的待办事项
class SyncableTodoItem {
  final String id;
  final String title;
  final String? description;
  final bool isCompleted;
  final DateTime createdAt;
  final String? listId;
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
class SyncableTodoList {
  final String id;
  final String name;
  final bool isExpanded;
  final int colorValue;
  final List<String> itemIds;
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
class SyncableTimeLog {
  final String id; // 添加唯一ID
  final String name;
  final DateTime startTime;
  final DateTime? endTime;
  final String? linkedTodoId;
  final String? linkedTodoTitle;
  final SyncMetadata syncMetadata;

  SyncableTimeLog({
    required this.id,
    required this.name,
    required this.startTime,
    this.endTime,
    this.linkedTodoId,
    this.linkedTodoTitle,
    required this.syncMetadata,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
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
    String? name,
    DateTime? startTime,
    DateTime? endTime,
    String? linkedTodoId,
    String? linkedTodoTitle,
    SyncMetadata? syncMetadata,
  }) {
    return SyncableTimeLog(
      id: id ?? this.id,
      name: name ?? this.name,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      linkedTodoId: linkedTodoId ?? this.linkedTodoId,
      linkedTodoTitle: linkedTodoTitle ?? this.linkedTodoTitle,
      syncMetadata: syncMetadata ?? this.syncMetadata,
    );
  }
}
