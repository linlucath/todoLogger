import '../../models/sync_data_models.dart';

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
    // 双方都删除
    if (local.isDeleted && remote.isDeleted) {
      return ConflictType.deleteDelete;
    }

    // 一方删除,一方更新
    if (local.isDeleted != remote.isDeleted) {
      return ConflictType.updateDelete;
    }

    // 检查是否在不同设备上同时修改
    final differentDevices = local.lastModifiedBy != remote.lastModifiedBy;

    // 如果是同一设备修改，没有冲突（可能是本地修改后同步回来）
    if (!differentDevices) {
      return ConflictType.noConflict;
    }

    // 版本相同但时间戳不同，说明有并发修改
    if (local.version == remote.version) {
      // 检查时间差，如果时间差很小（比如5秒内），认为是并发修改
      final timeDiff =
          local.lastModifiedAt.difference(remote.lastModifiedAt).abs();
      if (timeDiff.inSeconds < 5) {
        return ConflictType.updateUpdate;
      }
    }

    // 版本号不同，检查是否有因果关系
    // 如果一方的版本号明显更高，说明是顺序更新，不是冲突
    final versionDiff = (local.version - remote.version).abs();
    if (versionDiff > 1) {
      // 版本差距大于1，可能是分支修改，需要检查时间线
      // 如果较高版本的修改时间晚于较低版本，则是正常更新
      if (local.version > remote.version) {
        if (local.lastModifiedAt.isAfter(remote.lastModifiedAt)) {
          return ConflictType.noConflict; // 本地是基于远程的更新
        }
      } else {
        if (remote.lastModifiedAt.isAfter(local.lastModifiedAt)) {
          return ConflictType.noConflict; // 远程是基于本地的更新
        }
      }
      // 时间线不匹配，说明有并发修改
      return ConflictType.updateUpdate;
    }

    // 版本号相邻但修改者不同，检查时间线
    if (local.version > remote.version) {
      // 本地版本更高，但如果远程修改时间更晚，说明有冲突
      if (remote.lastModifiedAt.isAfter(local.lastModifiedAt)) {
        return ConflictType.updateUpdate;
      }
    } else if (remote.version > local.version) {
      // 远程版本更高，但如果本地修改时间更晚，说明有冲突
      if (local.lastModifiedAt.isAfter(remote.lastModifiedAt)) {
        return ConflictType.updateUpdate;
      }
    }

    // 双方都更新
    return ConflictType.noConflict;
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

    // 更新-更新冲突:使用时间戳更晚的，并合并元数据
    T winner;
    String resolutionDesc;
    if (remoteMeta.lastModifiedAt.isAfter(localMeta.lastModifiedAt)) {
      winner = remote;
      resolutionDesc = '远程修改时间更晚,使用远程数据';
    } else if (localMeta.lastModifiedAt.isAfter(remoteMeta.lastModifiedAt)) {
      winner = local;
      resolutionDesc = '本地修改时间更晚,保持本地数据';
    } else {
      // 时间戳相同，使用版本号更高的
      if (remoteMeta.version > localMeta.version) {
        winner = remote;
        resolutionDesc = '时间相同但远程版本更高,使用远程数据';
      } else {
        winner = local;
        resolutionDesc = '时间相同但本地版本更高或相等,保持本地数据';
      }
    }

    // 合并后的元数据：取最大版本号+1，最晚时间，以及胜出方的修改者
    final winnerMeta = _getMetadata(winner);
    final mergedVersion = (localMeta.version > remoteMeta.version
            ? localMeta.version
            : remoteMeta.version) +
        1;
    final mergedMetadata = winnerMeta.copyWith(
      version: mergedVersion,
      lastModifiedAt: DateTime.now(), // 使用当前时间作为合并时间
    );

    // 更新winner的元数据
    final resolvedData = _updateMetadata(winner, mergedMetadata);

    return ConflictResolution(
      conflictType: conflictType,
      resolvedData: resolvedData,
      localData: local,
      remoteData: remote,
      resolution: '$resolutionDesc (合并后版本: $mergedVersion)',
    );
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

    // 使用版本号更高的，如果版本号相同则使用时间戳
    T winner;
    String resolutionDesc;
    if (remoteMeta.version > localMeta.version) {
      winner = remote;
      resolutionDesc = '远程版本号更高,使用远程数据';
    } else if (localMeta.version > remoteMeta.version) {
      winner = local;
      resolutionDesc = '本地版本号更高,保持本地数据';
    } else {
      // 版本号相同，使用时间戳
      if (remoteMeta.lastModifiedAt.isAfter(localMeta.lastModifiedAt)) {
        winner = remote;
        resolutionDesc = '版本相同但远程修改时间更晚,使用远程数据';
      } else {
        winner = local;
        resolutionDesc = '版本相同但本地修改时间更晚或相等,保持本地数据';
      }
    }

    // 合并元数据
    final winnerMeta = _getMetadata(winner);
    final mergedVersion = (localMeta.version > remoteMeta.version
            ? localMeta.version
            : remoteMeta.version) +
        1;
    final mergedMetadata = winnerMeta.copyWith(
      version: mergedVersion,
      lastModifiedAt: DateTime.now(),
    );

    final resolvedData = _updateMetadata(winner, mergedMetadata);

    return ConflictResolution(
      conflictType: conflictType,
      resolvedData: resolvedData,
      localData: local,
      remoteData: remote,
      resolution: '$resolutionDesc (合并后版本: $mergedVersion)',
    );
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

  /// 更新数据的元数据
  T _updateMetadata<T>(T data, SyncMetadata newMetadata) {
    if (data is SyncableTodoItem) {
      return SyncableTodoItem(
        id: data.id,
        title: data.title,
        description: data.description,
        isCompleted: data.isCompleted,
        createdAt: data.createdAt,
        listId: data.listId,
        syncMetadata: newMetadata,
      ) as T;
    } else if (data is SyncableTodoList) {
      return SyncableTodoList(
        id: data.id,
        name: data.name,
        isExpanded: data.isExpanded,
        colorValue: data.colorValue,
        itemIds: data.itemIds,
        syncMetadata: newMetadata,
      ) as T;
    } else if (data is SyncableTimeLog) {
      return SyncableTimeLog(
        id: data.id,
        activityId: data.activityId,
        name: data.name,
        startTime: data.startTime,
        endTime: data.endTime,
        linkedTodoId: data.linkedTodoId,
        linkedTodoTitle: data.linkedTodoTitle,
        syncMetadata: newMetadata,
      ) as T;
    }
    throw ArgumentError('Unsupported data type');
  }
}
