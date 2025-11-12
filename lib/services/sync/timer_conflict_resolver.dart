import '../../models/timer_operation_models.dart';
import '../storage/timer_operation_storage.dart';

/// 计时器冲突解决器
///
/// 负责检测和解决跨设备的计时器冲突
/// 考虑设备时间差、网络延迟等因素
class TimerConflictResolver {
  final TimerOperationStorage _storage;

  // 配置参数
  static const Duration _timeDiffTolerance = Duration(seconds: 5); // 时间差容忍度
  static const Duration _networkDelayTolerance =
      Duration(seconds: 2); // 网络延迟容忍度
  static const Duration _recentOperationWindow =
      Duration(minutes: 30); // 最近操作时间窗口

  TimerConflictResolver(this._storage);

  /// 检测活动冲突
  ///
  /// 检查某个活动在多个设备上的状态是否冲突
  /// 返回冲突检测结果和建议的解决方案
  Future<TimerConflictResult> detectConflict({
    required String activityId,
    required String currentDeviceId,
    required bool isLocalRunning,
  }) async {
    print('🔍 [ConflictResolver] 检测活动冲突: $activityId');

    try {
      // 1. 获取活动的快照
      final snapshot = await _storage.getSnapshot(activityId);

      if (snapshot == null) {
        // 没有历史记录，无冲突
        return TimerConflictResult.noConflict();
      }

      print('📊 [ConflictResolver] 快照状态: ${snapshot.toString()}');

      // 2. 获取最近的操作记录（用于详细分析）
      final operations = await _storage.getOperationsByActivity(activityId);

      if (operations.isEmpty) {
        return TimerConflictResult.noConflict();
      }

      // 3. 按序列号和时间排序
      operations.sort((a, b) {
        // 先按序列号排序
        final seqCompare = a.sequenceNumber.compareTo(b.sequenceNumber);
        if (seqCompare != 0) return seqCompare;
        // 序列号相同则按时间排序
        return a.operationTime.compareTo(b.operationTime);
      });

      final lastOperation = operations.last;

      print('📝 [ConflictResolver] 最后操作: ${lastOperation.toString()}');
      print('   本地状态: ${isLocalRunning ? "运行中" : "已停止"}');
      print('   远程状态: ${snapshot.isRunning ? "运行中" : "已停止"}');

      // 4. 检测冲突类型

      // 情况1: 本地运行，但远程已停止
      if (isLocalRunning && !snapshot.isRunning) {
        // 检查是否是远程设备停止的
        if (lastOperation.deviceId != currentDeviceId) {
          // 检查时间差，确保不是旧的停止操作
          final timeSinceStop =
              DateTime.now().difference(lastOperation.operationTime);

          if (timeSinceStop < _recentOperationWindow) {
            print('⚠️  [ConflictResolver] 冲突: 远程已停止，本地仍在运行');
            return TimerConflictResult.remoteStopped(lastOperation);
          }
        }
      }

      // 情况2: 本地未运行，但远程正在运行
      if (!isLocalRunning && snapshot.isRunning) {
        // 远程设备正在运行
        if (lastOperation.deviceId != currentDeviceId) {
          print('ℹ️  [ConflictResolver] 远程设备正在运行此活动');
          return TimerConflictResult.remoteRunning(lastOperation);
        }
      }

      // 情况3: 检查是否有多个设备同时启动（通过序列号判断）
      final recentStarts = operations
          .where((op) =>
              op.operationType == TimerOperationType.start &&
              DateTime.now().difference(op.operationTime) <
                  _recentOperationWindow)
          .toList();

      if (recentStarts.length > 1) {
        // 多个设备启动了相同活动
        final devices = recentStarts.map((op) => op.deviceId).toSet();
        if (devices.length > 1) {
          print('⚠️  [ConflictResolver] 冲突: 多个设备同时运行');
          return TimerConflictResult.multipleRunning(recentStarts);
        }
      }

      // 5. 无冲突
      return TimerConflictResult.noConflict();
    } catch (e) {
      print('❌ [ConflictResolver] 检测冲突失败: $e');
      return TimerConflictResult.noConflict();
    }
  }

  /// 解决冲突 - 基于"最后操作优先"原则
  ///
  /// 考虑时间差和序列号，返回应该保留的设备ID
  Future<ConflictResolution> resolveConflict({
    required List<TimerOperationRecord> conflictingOperations,
    required String currentDeviceId,
  }) async {
    if (conflictingOperations.isEmpty) {
      return ConflictResolution(
        keepDeviceId: currentDeviceId,
        reason: '无冲突操作',
      );
    }

    print('🔧 [ConflictResolver] 解决冲突，操作数: ${conflictingOperations.length}');

    // 1. 按序列号和时间排序
    final sorted = List<TimerOperationRecord>.from(conflictingOperations);
    sorted.sort((a, b) {
      // 优先使用序列号
      final seqCompare = b.sequenceNumber.compareTo(a.sequenceNumber);
      if (seqCompare != 0) return seqCompare;

      // 序列号相同时使用时间戳
      return b.operationTime.compareTo(a.operationTime);
    });

    // 2. 找到最新的操作
    final latestOp = sorted.first;

    // 3. 检查最新操作的类型
    if (latestOp.operationType == TimerOperationType.stop) {
      // 最新操作是停止，所有设备都应该停止
      return ConflictResolution(
        keepDeviceId: null, // null 表示所有设备都应停止
        reason:
            '活动已在设备 ${latestOp.deviceName} 停止 (seq: ${latestOp.sequenceNumber})',
        shouldStopAll: true,
        stopTime: latestOp.actualTime ?? latestOp.operationTime,
      );
    }

    // 4. 最新操作是启动，保留该设备的活动
    return ConflictResolution(
      keepDeviceId: latestOp.deviceId,
      reason:
          '设备 ${latestOp.deviceName} 的操作最新 (seq: ${latestOp.sequenceNumber})',
      shouldStopAll: false,
      winner: latestOp,
    );
  }

  /// 检查两个时间戳是否在容忍范围内
  bool _isWithinTolerance(DateTime time1, DateTime time2, Duration tolerance) {
    return time1.difference(time2).abs() <= tolerance;
  }

  /// 判断操作是否是最近的
  bool _isRecentOperation(DateTime operationTime) {
    return DateTime.now().difference(operationTime) < _recentOperationWindow;
  }

  /// 比较两个操作的优先级
  /// 返回 > 0 表示 op1 优先，< 0 表示 op2 优先，0 表示相同
  int _compareOperationPriority(
    TimerOperationRecord op1,
    TimerOperationRecord op2,
  ) {
    // 1. 序列号高的优先
    final seqDiff = op1.sequenceNumber - op2.sequenceNumber;
    if (seqDiff.abs() > 0) return seqDiff;

    // 2. 序列号相同，看时间差
    final timeDiff = op1.operationTime.difference(op2.operationTime);

    // 如果时间差在容忍范围内，认为同时发生
    if (_isWithinTolerance(
        op1.operationTime, op2.operationTime, _timeDiffTolerance)) {
      // 同时发生，使用设备ID字典序（确保一致性）
      return op1.deviceId.compareTo(op2.deviceId);
    }

    // 时间新的优先
    return timeDiff.inMilliseconds;
  }
}

/// 冲突解决方案
class ConflictResolution {
  /// 应该保留的设备ID（null 表示所有设备都应停止）
  final String? keepDeviceId;

  /// 解决原因
  final String reason;

  /// 是否应该停止所有设备
  final bool shouldStopAll;

  /// 停止时间（如果需要停止）
  final DateTime? stopTime;

  /// 获胜的操作记录
  final TimerOperationRecord? winner;

  ConflictResolution({
    required this.keepDeviceId,
    required this.reason,
    this.shouldStopAll = false,
    this.stopTime,
    this.winner,
  });

  @override
  String toString() {
    if (shouldStopAll) {
      return 'ConflictResolution(停止所有设备: $reason)';
    }
    return 'ConflictResolution(保留设备: $keepDeviceId, 原因: $reason)';
  }
}
