import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:async';

/// SQLite 数据库服务
/// 用于高效存储和查询时间记录数据
///
/// 设计说明：
/// - 时间记录 (activity_records): 使用 SQLite，支持大量历史数据的复杂查询
/// - 活动历史 (activity_history): 使用 SQLite，利用索引优化频率排序
/// - Todo数据/目标/设置: 使用 SharedPreferences，数据量小且读写频繁
class DatabaseService {
  static Database? _database;
  static final DatabaseService _instance = DatabaseService._internal();

  factory DatabaseService() => _instance;

  DatabaseService._internal();

  /// 获取数据库实例
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// 初始化数据库
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'time_logger.db');

    return await openDatabase(
      path,
      version: 2, // 升级到版本 2
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// 创建数据库表
  Future<void> _onCreate(Database db, int version) async {
    // ==================== 时间记录表 ====================
    await db.execute('''
      CREATE TABLE activity_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        linked_todo_id TEXT,
        linked_todo_title TEXT,
        created_at INTEGER NOT NULL
      )
    ''');

    // 优化索引 - 支持各种查询场景
    await db.execute(
        'CREATE INDEX idx_start_time ON activity_records (start_time)');
    await db.execute('CREATE INDEX idx_name ON activity_records (name)');
    await db.execute(
        'CREATE INDEX idx_start_end_time ON activity_records (start_time, end_time)');
    await db.execute(
        'CREATE INDEX idx_linked_todo ON activity_records (linked_todo_id)');
    await db.execute(
        'CREATE INDEX idx_name_start ON activity_records (name, start_time)');

    // ==================== 活动历史表 ====================
    // 用于活动名称的自动完成和使用频率统计
    await db.execute('''
      CREATE TABLE activity_history (
        name TEXT PRIMARY KEY,
        last_used INTEGER NOT NULL,
        use_count INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // 优化索引 - 支持按使用频率和最近使用排序
    await db.execute(
        'CREATE INDEX idx_last_used ON activity_history (last_used DESC)');
    await db.execute(
        'CREATE INDEX idx_use_count ON activity_history (use_count DESC)');

    // ==================== 计时器操作记录表 (v2) ====================
    // 用于跨设备同步时的计时器冲突检测和解决
    await db.execute('''
      CREATE TABLE timer_operations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        operation_id TEXT NOT NULL UNIQUE,
        activity_id TEXT NOT NULL,
        activity_name TEXT NOT NULL,
        operation_type TEXT NOT NULL,
        operation_time INTEGER NOT NULL,
        device_id TEXT NOT NULL,
        device_name TEXT NOT NULL,
        actual_time INTEGER,
        linked_todo_id TEXT,
        sequence_number INTEGER NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    // 索引优化 - 支持按活动ID、设备ID、时间查询
    await db.execute(
        'CREATE INDEX idx_activity_id ON timer_operations (activity_id)');
    await db
        .execute('CREATE INDEX idx_device_id ON timer_operations (device_id)');
    await db.execute(
        'CREATE INDEX idx_operation_time ON timer_operations (operation_time DESC)');
    await db.execute(
        'CREATE INDEX idx_activity_seq ON timer_operations (activity_id, sequence_number)');
    await db.execute(
        'CREATE UNIQUE INDEX idx_operation_id ON timer_operations (operation_id)');

    // ==================== 计时器状态快照表 (v2) ====================
    // 缓存每个活动的最新状态，避免频繁查询操作记录
    await db.execute('''
      CREATE TABLE timer_snapshots (
        activity_id TEXT PRIMARY KEY,
        last_operation TEXT NOT NULL,
        last_operation_time INTEGER NOT NULL,
        last_operation_device TEXT NOT NULL,
        last_sequence_number INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_snapshot_time ON timer_snapshots (last_operation_time DESC)');
  }

  /// 数据库升级
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // 升级到版本 2: 添加计时器操作记录表
      await db.execute('''
        CREATE TABLE timer_operations (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          operation_id TEXT NOT NULL UNIQUE,
          activity_id TEXT NOT NULL,
          activity_name TEXT NOT NULL,
          operation_type TEXT NOT NULL,
          operation_time INTEGER NOT NULL,
          device_id TEXT NOT NULL,
          device_name TEXT NOT NULL,
          actual_time INTEGER,
          linked_todo_id TEXT,
          sequence_number INTEGER NOT NULL,
          is_synced INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        )
      ''');

      await db.execute(
          'CREATE INDEX idx_activity_id ON timer_operations (activity_id)');
      await db.execute(
          'CREATE INDEX idx_device_id ON timer_operations (device_id)');
      await db.execute(
          'CREATE INDEX idx_operation_time ON timer_operations (operation_time DESC)');
      await db.execute(
          'CREATE INDEX idx_activity_seq ON timer_operations (activity_id, sequence_number)');
      await db.execute(
          'CREATE UNIQUE INDEX idx_operation_id ON timer_operations (operation_id)');

      await db.execute('''
        CREATE TABLE timer_snapshots (
          activity_id TEXT PRIMARY KEY,
          last_operation TEXT NOT NULL,
          last_operation_time INTEGER NOT NULL,
          last_operation_device TEXT NOT NULL,
          last_sequence_number INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');

      await db.execute(
          'CREATE INDEX idx_snapshot_time ON timer_snapshots (last_operation_time DESC)');

      print('✅ [Database] 升级到版本 2: 计时器操作记录表已创建');
    }
  }

  // ==================== 时间记录相关 ====================

  /// 插入活动记录
  Future<int> insertActivityRecord(Map<String, dynamic> record) async {
    final db = await database;
    return await db.insert('activity_records', record);
  }

  /// 更新活动记录
  Future<int> updateActivityRecord(int id, Map<String, dynamic> record) async {
    final db = await database;
    return await db.update(
      'activity_records',
      record,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 获取所有活动记录 (分页)
  Future<List<Map<String, dynamic>>> getActivityRecords({
    int? limit,
    int? offset,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final db = await database;

    String? where;
    List<dynamic>? whereArgs;

    if (startDate != null || endDate != null) {
      final conditions = <String>[];
      whereArgs = [];

      if (startDate != null) {
        conditions.add('start_time >= ?');
        whereArgs.add(startDate.millisecondsSinceEpoch);
      }
      if (endDate != null) {
        conditions.add('start_time <= ?');
        whereArgs.add(endDate.millisecondsSinceEpoch);
      }

      where = conditions.join(' AND ');
    }

    return await db.query(
      'activity_records',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'start_time DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// 获取最近 N 天的记录
  Future<List<Map<String, dynamic>>> getRecentActivityRecords(int days) async {
    final startDate = DateTime.now().subtract(Duration(days: days));
    return await getActivityRecords(startDate: startDate);
  }

  /// 删除活动记录
  Future<int> deleteActivityRecord(int id) async {
    final db = await database;
    return await db.delete(
      'activity_records',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 统计活动记录数量
  Future<int> getActivityRecordCount() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as count FROM activity_records');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ==================== 活动历史相关 ====================

  /// 记录活动使用
  Future<void> recordActivityUsage(String name) async {
    final db = await database;
    final existing = await db.query(
      'activity_history',
      where: 'name = ?',
      whereArgs: [name],
    );

    if (existing.isEmpty) {
      await db.insert('activity_history', {
        'name': name,
        'last_used': DateTime.now().millisecondsSinceEpoch,
        'use_count': 1,
      });
    } else {
      await db.update(
        'activity_history',
        {
          'last_used': DateTime.now().millisecondsSinceEpoch,
          'use_count': (existing.first['use_count'] as int) + 1,
        },
        where: 'name = ?',
        whereArgs: [name],
      );
    }
  }

  /// 获取活动历史 (按使用频率排序)
  Future<List<String>> getActivityHistory({int limit = 20}) async {
    final db = await database;
    final results = await db.query(
      'activity_history',
      orderBy: 'use_count DESC, last_used DESC',
      limit: limit,
    );

    return results.map((r) => r['name'] as String).toList();
  }

  // ==================== 数据库维护 ====================

  /// 清空所有数据
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('activity_records');
    await db.delete('activity_history');
  }

  /// 关闭数据库
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
