import '../models/sync_data_models.dart';

/// 冲突解决策略
enum ConflictResolutionStrategy {
  lastWriteWins, // 最后写入获胜(基于时间戳)
  highestVersionWins, // 最高版本号获胜
  manualResolve, // 手动解决(暂不实现)
}

/// 冲突类型
enum ConflictType {
  noConflict, // 无冲突
  updateUpdate, // 双方都更新了
  updateDelete, // 一方更新,一方删除
  deleteDelete, // 双方都删除了
}

/// 冲突解决结果
class ConflictResolution<T> {
  final ConflictType conflictType;
  final T? resolvedData; // 解决后的数据
  final T? localData; // 本地数据
  final T? remoteData; // 远程数据
  final String resolution; // 解决方案描述
  final DateTime resolvedAt;

  ConflictResolution({
    required this.conflictType,
    this.resolvedData,
    this.localData,
    this.remoteData,
    required this.resolution,
    DateTime? resolvedAt,
  }) : resolvedAt = resolvedAt ?? DateTime.now();

  bool get hasConflict => conflictType != ConflictType.noConflict;

  Map<String, dynamic> toJson() => {
        'conflictType': conflictType.toString(),
        'resolution': resolution,
        'resolvedAt': resolvedAt.toIso8601String(),
      };
}

/// 冲突解决器
class SyncConflictResolver {
  final ConflictResolutionStrategy strategy;

  SyncConflictResolver({
    this.strategy = ConflictResolutionStrategy.lastWriteWins,
  });

  /// 解决待办事项冲突
  ConflictResolution<SyncableTodoItem> resolveTodoItemConflict(
    SyncableTodoItem? local,
    SyncableTodoItem remote,
  ) {
    // 如果本地不存在,直接使用远程数据
    if (local == null) {
      return ConflictResolution(
        conflictType: ConflictType.noConflict,
        resolvedData: remote,
        remoteData: remote,
        resolution: '本地不存在,使用远程数据',
      );
    }

    // 检查是否有冲突
    final conflictType = _detectConflictType(
      local.syncMetadata,
      remote.syncMetadata,
    );

    // 无冲突
    if (conflictType == ConflictType.noConflict) {
      // 远程版本更新,使用远程数据
      if (remote.syncMetadata.version > local.syncMetadata.version) {
        return ConflictResolution(
          conflictType: ConflictType.noConflict,
          resolvedData: remote,
          localData: local,
          remoteData: remote,
          resolution: '远程版本更新,使用远程数据',
        );
      }
      // 本地版本更新或相同,保持本地数据
      return ConflictResolution(
        conflictType: ConflictType.noConflict,
        resolvedData: local,
        localData: local,
        remoteData: remote,
        resolution: '本地版本已是最新',
      );
    }

    // 有冲突,根据策略解决
    switch (strategy) {
      case ConflictResolutionStrategy.lastWriteWins:
        return _resolveByLastWrite(local, remote, conflictType);
      case ConflictResolutionStrategy.highestVersionWins:
        return _resolveByHighestVersion(local, remote, conflictType);
      case ConflictResolutionStrategy.manualResolve:
        // 暂不实现手动解决
        return _resolveByLastWrite(local, remote, conflictType);
    }
  }

  /// 解决待办列表冲突
  ConflictResolution<SyncableTodoList> resolveTodoListConflict(
    SyncableTodoList? local,
    SyncableTodoList remote,
  ) {
    if (local == null) {
      return ConflictResolution(
        conflictType: ConflictType.noConflict,
        resolvedData: remote,
        remoteData: remote,
        resolution: '本地不存在,使用远程数据',
      );
    }

    final conflictType = _detectConflictType(
      local.syncMetadata,
      remote.syncMetadata,
    );

    if (conflictType == ConflictType.noConflict) {
      if (remote.syncMetadata.version > local.syncMetadata.version) {
        return ConflictResolution(
          conflictType: ConflictType.noConflict,
          resolvedData: remote,
          localData: local,
          remoteData: remote,
          resolution: '远程版本更新,使用远程数据',
        );
      }
      return ConflictResolution(
        conflictType: ConflictType.noConflict,
        resolvedData: local,
        localData: local,
        remoteData: remote,
        resolution: '本地版本已是最新',
      );
    }

    switch (strategy) {
      case ConflictResolutionStrategy.lastWriteWins:
        return _resolveByLastWrite(local, remote, conflictType);
      case ConflictResolutionStrategy.highestVersionWins:
        return _resolveByHighestVersion(local, remote, conflictType);
      case ConflictResolutionStrategy.manualResolve:
        return _resolveByLastWrite(local, remote, conflictType);
    }
  }

  /// 解决时间日志冲突
  ConflictResolution<SyncableTimeLog> resolveTimeLogConflict(
    SyncableTimeLog? local,
    SyncableTimeLog remote,
  ) {
    if (local == null) {
      return ConflictResolution(
        conflictType: ConflictType.noConflict,
        resolvedData: remote,
        remoteData: remote,
        resolution: '本地不存在,使用远程数据',
      );
    }

    final conflictType = _detectConflictType(
      local.syncMetadata,
      remote.syncMetadata,
    );

    if (conflictType == ConflictType.noConflict) {
      if (remote.syncMetadata.version > local.syncMetadata.version) {
        return ConflictResolution(
          conflictType: ConflictType.noConflict,
          resolvedData: remote,
          localData: local,
          remoteData: remote,
          resolution: '远程版本更新,使用远程数据',
        );
      }
      return ConflictResolution(
        conflictType: ConflictType.noConflict,
        resolvedData: local,
        localData: local,
        remoteData: remote,
        resolution: '本地版本已是最新',
      );
    }

    switch (strategy) {
      case ConflictResolutionStrategy.lastWriteWins:
        return _resolveByLastWrite(local, remote, conflictType);
      case ConflictResolutionStrategy.highestVersionWins:
        return _resolveByHighestVersion(local, remote, conflictType);
      case ConflictResolutionStrategy.manualResolve:
        return _resolveByLastWrite(local, remote, conflictType);
    }
  }

  /// 检测冲突类型
  ConflictType _detectConflictType(
    SyncMetadata local,
    SyncMetadata remote,
  ) {
    // 检查是否在不同设备上同时修改
    final bothModified = local.version > 1 && remote.version > 1;
    final differentDevices = local.lastModifiedBy != remote.lastModifiedBy;

    if (!bothModified || !differentDevices) {
      return ConflictType.noConflict;
    }

    // 双方都删除
    if (local.isDeleted && remote.isDeleted) {
      return ConflictType.deleteDelete;
    }

    // 一方删除,一方更新
    if (local.isDeleted != remote.isDeleted) {
      return ConflictType.updateDelete;
    }

    // 双方都更新
    return ConflictType.updateUpdate;
  }

  /// 基于最后写入时间解决冲突
  ConflictResolution<T> _resolveByLastWrite<T>(
    T local,
    T remote,
    ConflictType conflictType,
  ) {
    final localMeta = _getMetadata(local);
    final remoteMeta = _getMetadata(remote);

    // 删除-删除冲突:使用任意一个(都是删除状态)
    if (conflictType == ConflictType.deleteDelete) {
      return ConflictResolution(
        conflictType: conflictType,
        resolvedData: remote,
        localData: local,
        remoteData: remote,
        resolution: '双方都删除,保持删除状态',
      );
    }

    // 更新-删除冲突:删除优先
    if (conflictType == ConflictType.updateDelete) {
      final deletedData = remoteMeta.isDeleted ? remote : local;
      return ConflictResolution(
        conflictType: conflictType,
        resolvedData: deletedData,
        localData: local,
        remoteData: remote,
        resolution: '删除操作优先,使用删除状态',
      );
    }

    // 更新-更新冲突:使用时间戳更晚的
    if (remoteMeta.lastModifiedAt.isAfter(localMeta.lastModifiedAt)) {
      return ConflictResolution(
        conflictType: conflictType,
        resolvedData: remote,
        localData: local,
        remoteData: remote,
        resolution: '远程修改时间更晚,使用远程数据',
      );
    } else {
      return ConflictResolution(
        conflictType: conflictType,
        resolvedData: local,
        localData: local,
        remoteData: remote,
        resolution: '本地修改时间更晚,保持本地数据',
      );
    }
  }

  /// 基于版本号解决冲突
  ConflictResolution<T> _resolveByHighestVersion<T>(
    T local,
    T remote,
    ConflictType conflictType,
  ) {
    final localMeta = _getMetadata(local);
    final remoteMeta = _getMetadata(remote);

    if (conflictType == ConflictType.deleteDelete) {
      return ConflictResolution(
        conflictType: conflictType,
        resolvedData: remote,
        localData: local,
        remoteData: remote,
        resolution: '双方都删除,保持删除状态',
      );
    }

    if (conflictType == ConflictType.updateDelete) {
      final deletedData = remoteMeta.isDeleted ? remote : local;
      return ConflictResolution(
        conflictType: conflictType,
        resolvedData: deletedData,
        localData: local,
        remoteData: remote,
        resolution: '删除操作优先,使用删除状态',
      );
    }

    // 使用版本号更高的
    if (remoteMeta.version > localMeta.version) {
      return ConflictResolution(
        conflictType: conflictType,
        resolvedData: remote,
        localData: local,
        remoteData: remote,
        resolution: '远程版本号更高,使用远程数据',
      );
    } else {
      return ConflictResolution(
        conflictType: conflictType,
        resolvedData: local,
        localData: local,
        remoteData: remote,
        resolution: '本地版本号更高,保持本地数据',
      );
    }
  }

  /// 获取元数据
  SyncMetadata _getMetadata(dynamic data) {
    if (data is SyncableTodoItem) {
      return data.syncMetadata;
    } else if (data is SyncableTodoList) {
      return data.syncMetadata;
    } else if (data is SyncableTimeLog) {
      return data.syncMetadata;
    }
    throw ArgumentError('Unsupported data type');
  }
}
