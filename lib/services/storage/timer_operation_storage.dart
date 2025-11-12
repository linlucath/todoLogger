import 'package:sqflite/sqflite.dart';
import '../../models/timer_operation_models.dart';
import 'database_service.dart';

/// 计时器操作记录存储服务
///
/// 负责存储和查询计时器的启动/停止操作记录
/// 用于跨设备同步时的冲突检测和解决
class TimerOperationStorage {
  static final TimerOperationStorage _instance =
      TimerOperationStorage._internal();

  factory TimerOperationStorage() => _instance;

  TimerOperationStorage._internal();

  final DatabaseService _dbService = DatabaseService();

  // ==================== 操作记录管理 ====================

  /// 保存计时器操作记录
  Future<void> saveOperation(TimerOperationRecord operation) async {
    final db = await _dbService.database;

    await db.insert(
      'timer_operations',
      {
        'operation_id': operation.operationId,
        'activity_id': operation.activityId,
        'activity_name': operation.activityName,
        'operation_type': operation.operationType.name,
        'operation_time': operation.operationTime.millisecondsSinceEpoch,
        'device_id': operation.deviceId,
        'device_name': operation.deviceName,
        'actual_time': operation.actualTime?.millisecondsSinceEpoch,
        'linked_todo_id': operation.linkedTodoId,
        'sequence_number': operation.sequenceNumber,
        'is_synced': operation.isSynced ? 1 : 0,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // 更新快照
    await _updateSnapshot(operation);

    print('💾 [TimerStorage] 保存操作记录: ${operation.toString()}');
  }

  /// 批量保存操作记录
  Future<void> saveOperations(List<TimerOperationRecord> operations) async {
    final db = await _dbService.database;
    final batch = db.batch();

    for (final operation in operations) {
      batch.insert(
        'timer_operations',
        {
          'operation_id': operation.operationId,
          'activity_id': operation.activityId,
          'activity_name': operation.activityName,
          'operation_type': operation.operationType.name,
          'operation_time': operation.operationTime.millisecondsSinceEpoch,
          'device_id': operation.deviceId,
          'device_name': operation.deviceName,
          'actual_time': operation.actualTime?.millisecondsSinceEpoch,
          'linked_todo_id': operation.linkedTodoId,
          'sequence_number': operation.sequenceNumber,
          'is_synced': operation.isSynced ? 1 : 0,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);

    // 批量更新快照
    for (final operation in operations) {
      await _updateSnapshot(operation);
    }

    print('💾 [TimerStorage] 批量保存 ${operations.length} 条操作记录');
  }

  /// 获取某个活动的所有操作记录
  Future<List<TimerOperationRecord>> getOperationsByActivity(
      String activityId) async {
    final db = await _dbService.database;

    final results = await db.query(
      'timer_operations',
      where: 'activity_id = ?',
      whereArgs: [activityId],
      orderBy: 'sequence_number ASC, operation_time ASC',
    );

    return results.map(_recordFromMap).toList();
  }

  /// 获取某个设备的所有操作记录
  Future<List<TimerOperationRecord>> getOperationsByDevice(
      String deviceId) async {
    final db = await _dbService.database;

    final results = await db.query(
      'timer_operations',
      where: 'device_id = ?',
      whereArgs: [deviceId],
      orderBy: 'operation_time DESC',
    );

    return results.map(_recordFromMap).toList();
  }

  /// 获取最近的操作记录
  Future<List<TimerOperationRecord>> getRecentOperations({
    int limit = 100,
    DateTime? since,
  }) async {
    final db = await _dbService.database;

    String? where;
    List<dynamic>? whereArgs;

    if (since != null) {
      where = 'operation_time >= ?';
      whereArgs = [since.millisecondsSinceEpoch];
    }

    final results = await db.query(
      'timer_operations',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'operation_time DESC',
      limit: limit,
    );

    return results.map(_recordFromMap).toList();
  }

  /// 获取未同步的操作记录
  Future<List<TimerOperationRecord>> getUnsyncedOperations() async {
    final db = await _dbService.database;

    final results = await db.query(
      'timer_operations',
      where: 'is_synced = ?',
      whereArgs: [0],
      orderBy: 'operation_time ASC',
    );

    return results.map(_recordFromMap).toList();
  }

  /// 标记操作为已同步
  Future<void> markAsSynced(String operationId) async {
    final db = await _dbService.database;

    await db.update(
      'timer_operations',
      {'is_synced': 1},
      where: 'operation_id = ?',
      whereArgs: [operationId],
    );
  }

  /// 批量标记为已同步
  Future<void> markMultipleAsSynced(List<String> operationIds) async {
    final db = await _dbService.database;
    final batch = db.batch();

    for (final id in operationIds) {
      batch.update(
        'timer_operations',
        {'is_synced': 1},
        where: 'operation_id = ?',
        whereArgs: [id],
      );
    }

    await batch.commit(noResult: true);
  }

  // ==================== 快照管理 ====================

  /// 更新快照
  Future<void> _updateSnapshot(TimerOperationRecord operation) async {
    final db = await _dbService.database;

    // 检查是否需要更新快照
    final existing = await db.query(
      'timer_snapshots',
      where: 'activity_id = ?',
      whereArgs: [operation.activityId],
    );

    bool shouldUpdate = false;

    if (existing.isEmpty) {
      shouldUpdate = true;
    } else {
      final existingSeq = existing.first['last_sequence_number'] as int;
      final existingTime = existing.first['last_operation_time'] as int;

      // 如果新操作的序列号更大，或者序列号相同但时间更新，则更新
      if (operation.sequenceNumber > existingSeq ||
          (operation.sequenceNumber == existingSeq &&
              operation.operationTime.millisecondsSinceEpoch > existingTime)) {
        shouldUpdate = true;
      }
    }

    if (shouldUpdate) {
      await db.insert(
        'timer_snapshots',
        {
          'activity_id': operation.activityId,
          'last_operation': operation.operationType.name,
          'last_operation_time': operation.operationTime.millisecondsSinceEpoch,
          'last_operation_device': operation.deviceId,
          'last_sequence_number': operation.sequenceNumber,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  /// 获取活动的快照
  Future<TimerStateSnapshot?> getSnapshot(String activityId) async {
    final db = await _dbService.database;

    final results = await db.query(
      'timer_snapshots',
      where: 'activity_id = ?',
      whereArgs: [activityId],
    );

    if (results.isEmpty) return null;

    final map = results.first;
    return TimerStateSnapshot(
      activityId: map['activity_id'] as String,
      lastOperation: TimerOperationType.values.firstWhere(
        (e) => e.name == map['last_operation'],
      ),
      lastOperationTime: DateTime.fromMillisecondsSinceEpoch(
        map['last_operation_time'] as int,
      ),
      lastOperationDevice: map['last_operation_device'] as String,
      lastSequenceNumber: map['last_sequence_number'] as int,
    );
  }

  /// 获取所有正在运行的活动快照
  Future<List<TimerStateSnapshot>> getRunningSnapshots() async {
    final db = await _dbService.database;

    final results = await db.query(
      'timer_snapshots',
      where: 'last_operation = ?',
      whereArgs: ['start'],
      orderBy: 'last_operation_time DESC',
    );

    return results.map((map) {
      return TimerStateSnapshot(
        activityId: map['activity_id'] as String,
        lastOperation: TimerOperationType.values.firstWhere(
          (e) => e.name == map['last_operation'],
        ),
        lastOperationTime: DateTime.fromMillisecondsSinceEpoch(
          map['last_operation_time'] as int,
        ),
        lastOperationDevice: map['last_operation_device'] as String,
        lastSequenceNumber: map['last_sequence_number'] as int,
      );
    }).toList();
  }

  // ==================== 辅助方法 ====================

  /// 从 Map 转换为 TimerOperationRecord
  TimerOperationRecord _recordFromMap(Map<String, dynamic> map) {
    return TimerOperationRecord(
      operationId: map['operation_id'] as String,
      activityId: map['activity_id'] as String,
      activityName: map['activity_name'] as String,
      operationType: TimerOperationType.values.firstWhere(
        (e) => e.name == map['operation_type'],
      ),
      operationTime: DateTime.fromMillisecondsSinceEpoch(
        map['operation_time'] as int,
      ),
      deviceId: map['device_id'] as String,
      deviceName: map['device_name'] as String,
      actualTime: map['actual_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['actual_time'] as int)
          : null,
      linkedTodoId: map['linked_todo_id'] as String?,
      sequenceNumber: map['sequence_number'] as int,
      isSynced: (map['is_synced'] as int) == 1,
    );
  }

  // ==================== 数据清理 ====================

  /// 清理旧的操作记录（保留最近30天）
  Future<void> cleanOldOperations({int daysToKeep = 30}) async {
    final db = await _dbService.database;
    final cutoffTime = DateTime.now()
        .subtract(Duration(days: daysToKeep))
        .millisecondsSinceEpoch;

    final deletedCount = await db.delete(
      'timer_operations',
      where: 'operation_time < ?',
      whereArgs: [cutoffTime],
    );

    print('🧹 [TimerStorage] 清理了 $deletedCount 条旧操作记录');
  }

  /// 清空所有数据（仅用于测试/重置）
  Future<void> clearAll() async {
    final db = await _dbService.database;
    await db.delete('timer_operations');
    await db.delete('timer_snapshots');
    print('🧹 [TimerStorage] 已清空所有计时器操作记录');
  }

  // ==================== 统计信息 ====================

  /// 获取操作记录总数
  Future<int> getOperationCount() async {
    final db = await _dbService.database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as count FROM timer_operations');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 获取某个活动的操作次数
  Future<int> getActivityOperationCount(String activityId) async {
    final db = await _dbService.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM timer_operations WHERE activity_id = ?',
      [activityId],
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }
}
