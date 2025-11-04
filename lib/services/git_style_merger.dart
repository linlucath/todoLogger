import '../models/sync_data_models.dart';

/// 合并类型
enum MergeType {
  noChange, // 无变化
  fastForwardLocal, // 快进：本地可以直接接受远程
  fastForwardRemote, // 快进：远程已经是最新的
  autoMerge, // 自动合并：非冲突修改
  conflict, // 冲突：需要解决策略
}

/// 合并策略（解决冲突时使用）
enum ConflictStrategy {
  ours, // 采用本地版本
  theirs, // 采用远程版本
  lastWrite, // 最后写入优先
  newerVersion, // 版本号高的优先
}

/// 合并结果
class MergeResult<T extends SyncableData> {
  final MergeType mergeType;
  final T? mergedData; // 合并后的数据
  final String description; // 合并描述
  final DateTime mergedAt;

  MergeResult({
    required this.mergeType,
    this.mergedData,
    required this.description,
  }) : mergedAt = DateTime.now();

  bool get needsUpdate =>
      mergeType != MergeType.noChange &&
      mergeType != MergeType.fastForwardRemote;
  bool get hasConflict => mergeType == MergeType.conflict;
}

/// Git-style 三方合并器
///
/// 借鉴 Git 的合并策略：
/// 1. Fast-forward merge: 如果一方是另一方的直接后继，直接采用较新版本
/// 2. Three-way merge: 比较 base（共同祖先）、local、remote 三个版本
/// 3. Conflict detection: 只有真正的并发修改才算冲突
class GitStyleMerger {
  final ConflictStrategy conflictStrategy;

  GitStyleMerger({
    this.conflictStrategy = ConflictStrategy.lastWrite,
  });

  /// 执行三方合并
  ///
  /// @param local 本地版本
  /// @param remote 远程版本
  /// @param currentDeviceId 当前设备ID
  /// @return 合并结果
  MergeResult<T> merge<T extends SyncableData>(
    T? local,
    T? remote,
    String currentDeviceId,
  ) {
    // 情况1: 都不存在（不应该发生）
    if (local == null && remote == null) {
      return MergeResult(
        mergeType: MergeType.noChange,
        description: '本地和远程都不存在',
      );
    }

    // 情况2: 本地不存在，远程存在 -> 接受远程（新增）
    if (local == null && remote != null) {
      if (remote.syncMetadata.isDeleted) {
        return MergeResult(
          mergeType: MergeType.noChange,
          description: '远程已删除，本地无需创建',
        );
      }
      return MergeResult(
        mergeType: MergeType.fastForwardLocal,
        mergedData: _updateBase(remote),
        description: '接受远程新增项',
      );
    }

    // 情况3: 本地存在，远程不存在 -> 保留本地
    if (local != null && remote == null) {
      return MergeResult(
        mergeType: MergeType.fastForwardRemote,
        description: '保留本地项（远程不存在）',
      );
    }

    // 情况4: 都存在 -> 执行三方合并
    final localMeta = local!.syncMetadata;
    final remoteMeta = remote!.syncMetadata;

    // 检查是否有共同祖先（base）
    final hasBase =
        localMeta.baseModifiedAt != null && remoteMeta.baseModifiedAt != null;

    if (!hasBase) {
      // 没有 base 信息，使用传统冲突解决
      return _mergWithoutBase(local, remote, currentDeviceId);
    }

    // 有 base 信息，执行 Git-style 三方合并
    return _threeWayMerge(local, remote, currentDeviceId);
  }

  /// 三方合并（有共同祖先）
  MergeResult<T> _threeWayMerge<T extends SyncableData>(
    T local,
    T remote,
    String currentDeviceId,
  ) {
    final localMeta = local.syncMetadata;
    final remoteMeta = remote.syncMetadata;

    // 检查本地是否从 base 修改过
    final localChanged = _hasChangedFromBase(localMeta);
    final remoteChanged = _hasChangedFromBase(remoteMeta);

    print('🔀 [GitMerge] 三方合并分析:');
    print(
        '   本地修改: $localChanged (v${localMeta.version}, base: ${localMeta.baseVersion})');
    print(
        '   远程修改: $remoteChanged (v${remoteMeta.version}, base: ${remoteMeta.baseVersion})');

    // 情况1: 双方都没改 -> 无需合并
    if (!localChanged && !remoteChanged) {
      return MergeResult(
        mergeType: MergeType.noChange,
        description: '本地和远程都未修改',
      );
    }

    // 情况2: 只有远程改了 -> Fast-forward 到远程
    if (!localChanged && remoteChanged) {
      print('✅ [GitMerge] Fast-forward: 接受远程修改');
      return MergeResult(
        mergeType: MergeType.fastForwardLocal,
        mergedData: _updateBase(remote),
        description: 'Fast-forward: 接受远程修改',
      );
    }

    // 情况3: 只有本地改了 -> 保持本地（远程需要更新）
    if (localChanged && !remoteChanged) {
      print('✅ [GitMerge] Fast-forward: 保持本地（推送到远程）');
      return MergeResult(
        mergeType: MergeType.fastForwardRemote,
        description: 'Fast-forward: 本地较新（需推送）',
      );
    }

    // 情况4: 双方都改了 -> 检查是否是同一个修改链
    if (_isLinearHistory(localMeta, remoteMeta)) {
      // 线性历史：一方是另一方的直接后继
      if (localMeta.version > remoteMeta.version) {
        print('✅ [GitMerge] 线性历史: 本地较新');
        return MergeResult(
          mergeType: MergeType.fastForwardRemote,
          description: '线性历史: 本地版本较新',
        );
      } else {
        print('✅ [GitMerge] 线性历史: 远程较新');
        return MergeResult(
          mergeType: MergeType.fastForwardLocal,
          mergedData: _updateBase(remote),
          description: '线性历史: 远程版本较新',
        );
      }
    }

    // 情况5: 并发修改 -> 真正的冲突，需要解决
    print('⚠️ [GitMerge] 检测到并发修改，使用冲突策略: $conflictStrategy');
    return _resolveConflict(local, remote, currentDeviceId);
  }

  /// 无 base 时的合并（退化为简单冲突解决）
  MergeResult<T> _mergWithoutBase<T extends SyncableData>(
    T local,
    T remote,
    String currentDeviceId,
  ) {
    print('⚠️ [GitMerge] 缺少 base 信息，使用传统合并');

    final localMeta = local.syncMetadata;
    final remoteMeta = remote.syncMetadata;

    // 比较版本和时间
    if (localMeta.version == remoteMeta.version &&
        localMeta.lastModifiedAt == remoteMeta.lastModifiedAt) {
      return MergeResult(
        mergeType: MergeType.noChange,
        description: '版本和时间戳相同',
      );
    }

    // 使用冲突策略解决
    return _resolveConflict(local, remote, currentDeviceId);
  }

  /// 解决冲突
  MergeResult<T> _resolveConflict<T extends SyncableData>(
    T local,
    T remote,
    String currentDeviceId,
  ) {
    final T winner;
    final String reason;

    switch (conflictStrategy) {
      case ConflictStrategy.ours:
        winner = local;
        reason = '冲突解决: 采用本地版本';
        break;

      case ConflictStrategy.theirs:
        winner = remote;
        reason = '冲突解决: 采用远程版本';
        break;

      case ConflictStrategy.lastWrite:
        if (remote.syncMetadata.lastModifiedAt
            .isAfter(local.syncMetadata.lastModifiedAt)) {
          winner = remote;
          reason = '冲突解决: 远程写入更晚';
        } else if (local.syncMetadata.lastModifiedAt
            .isAfter(remote.syncMetadata.lastModifiedAt)) {
          winner = local;
          reason = '冲突解决: 本地写入更晚';
        } else {
          // 时间相同，比较版本
          winner = remote.syncMetadata.version >= local.syncMetadata.version
              ? remote
              : local;
          reason = '冲突解决: 时间相同，${winner == remote ? "远程" : "本地"}版本更高';
        }
        break;

      case ConflictStrategy.newerVersion:
        winner = remote.syncMetadata.version >= local.syncMetadata.version
            ? remote
            : local;
        reason = '冲突解决: ${winner == remote ? "远程" : "本地"}版本更高';
        break;
    }

    print('✅ [GitMerge] $reason');

    // 合并元数据：保留胜者的数据，但合并修改者信息
    final mergedMeta = _mergeMetadata(
      winner.syncMetadata,
      winner == local ? remote.syncMetadata : local.syncMetadata,
      currentDeviceId,
    );

    return MergeResult(
      mergeType: MergeType.conflict,
      mergedData: _updateMetadata(winner, mergedMeta) as T,
      description: reason,
    );
  }

  /// 检查是否从 base 修改过
  bool _hasChangedFromBase(SyncMetadata meta) {
    if (meta.baseVersion == null) return true; // 无 base 信息，认为已修改
    return meta.version > meta.baseVersion!;
  }

  /// 检查是否是线性历史（一方是另一方的直接后继）
  bool _isLinearHistory(SyncMetadata local, SyncMetadata remote) {
    // 如果本地的 base 就是远程的当前状态，则是线性的
    if (local.baseVersion != null &&
        local.baseVersion == remote.version &&
        local.baseModifiedAt == remote.lastModifiedAt) {
      return true;
    }

    // 如果远程的 base 就是本地的当前状态，也是线性的
    if (remote.baseVersion != null &&
        remote.baseVersion == local.version &&
        remote.baseModifiedAt == local.lastModifiedAt) {
      return true;
    }

    return false;
  }

  /// 合并元数据
  SyncMetadata _mergeMetadata(
    SyncMetadata winner,
    SyncMetadata loser,
    String currentDeviceId,
  ) {
    return SyncMetadata(
      lastModifiedAt: winner.lastModifiedAt,
      lastModifiedBy: winner.lastModifiedBy,
      version: winner.version + 1, // 合并后版本号递增
      isDeleted: winner.isDeleted,
      // 🆕 更新 base 为当前合并后的状态
      baseModifiedAt: winner.lastModifiedAt,
      baseVersion: winner.version,
      baseModifiedBy: winner.lastModifiedBy,
    );
  }

  /// 更新 base 信息（同步成功后调用）
  T _updateBase<T extends SyncableData>(T data) {
    final updatedMeta = data.syncMetadata.updateBase();
    return _updateMetadata(data, updatedMeta) as T;
  }

  /// 更新数据的元数据（辅助方法）
  SyncableData _updateMetadata(SyncableData data, SyncMetadata newMeta) {
    if (data is SyncableTodoItem) {
      return data.copyWith(syncMetadata: newMeta);
    } else if (data is SyncableTodoList) {
      return data.copyWith(syncMetadata: newMeta);
    } else if (data is SyncableTimeLog) {
      return data.copyWith(syncMetadata: newMeta);
    } else if (data is SyncableTarget) {
      return data.copyWith(syncMetadata: newMeta);
    }
    throw UnimplementedError('Unsupported data type: ${data.runtimeType}');
  }

  /// 批量合并数据
  Map<String, MergeResult<T>> mergeAll<T extends SyncableData>({
    required Map<String, T> localItems,
    required Map<String, T> remoteItems,
    required String currentDeviceId,
  }) {
    final results = <String, MergeResult<T>>{};
    final allIds = {...localItems.keys, ...remoteItems.keys};

    for (final id in allIds) {
      final local = localItems[id];
      final remote = remoteItems[id];
      results[id] = merge(local, remote, currentDeviceId);
    }

    return results;
  }
}
