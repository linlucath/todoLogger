import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:async';

/// SQLite 数据库服务
/// 用于高效存储和查询时间记录和 TODO 数据
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
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// 创建数据库表
  Future<void> _onCreate(Database db, int version) async {
    // 时间记录表
    await db.execute('''
      CREATE TABLE activity_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        linked_todo_id TEXT,
        linked_todo_title TEXT,
        created_at INTEGER NOT NULL,
        INDEX idx_start_time (start_time),
        INDEX idx_name (name)
      )
    ''');

    // TODO 列表表
    await db.execute('''
      CREATE TABLE todo_lists (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color INTEGER NOT NULL,
        is_expanded INTEGER NOT NULL DEFAULT 1,
        display_order INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // TODO 项目表
    await db.execute('''
      CREATE TABLE todo_items (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT,
        is_completed INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        list_id TEXT,
        display_order INTEGER NOT NULL,
        FOREIGN KEY (list_id) REFERENCES todo_lists (id) ON DELETE CASCADE,
        INDEX idx_list_id (list_id),
        INDEX idx_completed (is_completed)
      )
    ''');

    // 活动历史表 (用于自动完成)
    await db.execute('''
      CREATE TABLE activity_history (
        name TEXT PRIMARY KEY,
        last_used INTEGER NOT NULL,
        use_count INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // 应用设置表
    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  /// 数据库升级
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 未来版本升级时使用
    if (oldVersion < 2) {
      // 添加新字段或表
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

  // ==================== TODO 相关 ====================

  /// 插入 TODO 列表
  Future<int> insertTodoList(Map<String, dynamic> list) async {
    final db = await database;
    return await db.insert('todo_lists', list);
  }

  /// 更新 TODO 列表
  Future<int> updateTodoList(String id, Map<String, dynamic> list) async {
    final db = await database;
    return await db.update(
      'todo_lists',
      list,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 获取所有 TODO 列表
  Future<List<Map<String, dynamic>>> getTodoLists() async {
    final db = await database;
    return await db.query('todo_lists', orderBy: 'display_order ASC');
  }

  /// 删除 TODO 列表
  Future<int> deleteTodoList(String id) async {
    final db = await database;
    return await db.delete(
      'todo_lists',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 插入 TODO 项目
  Future<int> insertTodoItem(Map<String, dynamic> item) async {
    final db = await database;
    return await db.insert('todo_items', item);
  }

  /// 更新 TODO 项目
  Future<int> updateTodoItem(String id, Map<String, dynamic> item) async {
    final db = await database;
    return await db.update(
      'todo_items',
      item,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 获取所有 TODO 项目
  Future<List<Map<String, dynamic>>> getTodoItems({String? listId}) async {
    final db = await database;

    if (listId != null) {
      return await db.query(
        'todo_items',
        where: 'list_id = ?',
        whereArgs: [listId],
        orderBy: 'display_order ASC',
      );
    }

    return await db.query('todo_items', orderBy: 'display_order ASC');
  }

  /// 获取独立的 TODO 项目 (不属于任何列表)
  Future<List<Map<String, dynamic>>> getIndependentTodoItems() async {
    final db = await database;
    return await db.query(
      'todo_items',
      where: 'list_id IS NULL',
      orderBy: 'display_order ASC',
    );
  }

  /// 删除 TODO 项目
  Future<int> deleteTodoItem(String id) async {
    final db = await database;
    return await db.delete(
      'todo_items',
      where: 'id = ?',
      whereArgs: [id],
    );
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

  // ==================== 设置相关 ====================

  /// 保存设置
  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'app_settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 获取设置
  Future<String?> getSetting(String key) async {
    final db = await database;
    final results = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
    );

    if (results.isEmpty) return null;
    return results.first['value'] as String;
  }

  // ==================== 数据迁移 ====================

  /// 从 SharedPreferences 迁移数据到 SQLite
  Future<void> migrateFromSharedPreferences() async {
    // 这个方法将在 time_logger_storage_v2.dart 中实现
    // 用于一次性数据迁移
  }

  // ==================== 数据库维护 ====================

  /// 清空所有数据
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('activity_records');
    await db.delete('todo_lists');
    await db.delete('todo_items');
    await db.delete('activity_history');
    await db.delete('app_settings');
  }

  /// 关闭数据库
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
