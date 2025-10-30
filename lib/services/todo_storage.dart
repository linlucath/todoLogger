import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sync_data_models.dart';

// TodoItem 数据类（用于序列化）
class TodoItemData {
  final String id;
  final String title;
  final String? description;
  final bool isCompleted;
  final DateTime createdAt;
  final String? listId;

  TodoItemData({
    required this.id,
    required this.title,
    this.description,
    this.isCompleted = false,
    required this.createdAt,
    this.listId,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'isCompleted': isCompleted,
        'createdAt': createdAt.toIso8601String(),
        'listId': listId,
      };

  factory TodoItemData.fromJson(Map<String, dynamic> json) => TodoItemData(
        id: json['id'] as String,
        title: json['title'] as String,
        description: json['description'] as String?,
        isCompleted: json['isCompleted'] as bool? ?? false,
        createdAt: DateTime.parse(json['createdAt'] as String),
        listId: json['listId'] as String?,
      );
}

// TodoList 数据类（用于序列化）
class TodoListData {
  final String id;
  final String name;
  final bool isExpanded;
  final int colorValue; // 存储颜色的值
  final List<String> itemIds; // 存储 item 的 ID 列表

  TodoListData({
    required this.id,
    required this.name,
    this.isExpanded = true,
    this.colorValue = 0xFF2196F3, // 默认蓝色
    List<String>? itemIds,
  }) : itemIds = itemIds ?? [];

  Color get color => Color(colorValue);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isExpanded': isExpanded,
        'colorValue': colorValue,
        'itemIds': itemIds,
      };

  factory TodoListData.fromJson(Map<String, dynamic> json) => TodoListData(
        id: json['id'] as String,
        name: json['name'] as String,
        isExpanded: json['isExpanded'] as bool? ?? true,
        colorValue: json['colorValue'] as int? ?? 0xFF2196F3,
        itemIds: (json['itemIds'] as List<dynamic>?)?.cast<String>() ?? [],
      );
}

class TodoStorage {
  static const String _keyTodoItems = 'todo_items';
  static const String _keyTodoLists = 'todo_lists';
  static const String _keyIndependentTodos =
      'independent_todos'; // 不属于任何列表的 TODO
  static const String _keySyncMetadata = 'todo_sync_metadata'; // 同步元数据

  // 保存所有 TodoItems（按 ID 存储）
  static Future<void> saveTodoItems(Map<String, TodoItemData> items) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonMap = items.map((key, value) => MapEntry(key, value.toJson()));
    await prefs.setString(_keyTodoItems, jsonEncode(jsonMap));
    debugPrint('💾 TodoStorage: Saved ${items.length} items');
  }

  // 获取所有 TodoItems
  static Future<Map<String, TodoItemData>> getTodoItems() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyTodoItems);
    if (jsonStr == null) {
      debugPrint('📂 TodoStorage: No items found');
      return {};
    }

    final Map<String, dynamic> jsonMap = jsonDecode(jsonStr);
    final items = jsonMap.map(
      (key, value) => MapEntry(key, TodoItemData.fromJson(value)),
    );
    debugPrint('📂 TodoStorage: Loaded ${items.length} items');
    return items;
  }

  // 保存所有 TodoLists
  static Future<void> saveTodoLists(List<TodoListData> lists) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = lists.map((list) => list.toJson()).toList();
    await prefs.setString(_keyTodoLists, jsonEncode(jsonList));
    debugPrint('💾 TodoStorage: Saved ${lists.length} lists');
  }

  // 获取所有 TodoLists
  static Future<List<TodoListData>> getTodoLists() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keyTodoLists);
    if (jsonStr == null) {
      debugPrint('📂 TodoStorage: No lists found');
      return [];
    }

    final List<dynamic> jsonList = jsonDecode(jsonStr);
    final lists = jsonList.map((json) => TodoListData.fromJson(json)).toList();
    debugPrint('📂 TodoStorage: Loaded ${lists.length} lists');
    return lists;
  }

  // 保存独立 TODOs 的 ID 列表
  static Future<void> saveIndependentTodoIds(List<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyIndependentTodos, ids);
  }

  // 获取独立 TODOs 的 ID 列表
  static Future<List<String>> getIndependentTodoIds() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_keyIndependentTodos) ?? [];
  }

  // 清除所有 TODO 数据
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyTodoItems);
    await prefs.remove(_keyTodoLists);
    await prefs.remove(_keyIndependentTodos);
  }

  // 便捷方法：保存完整的 TODO 数据结构
  static Future<void> saveAllData({
    required Map<String, TodoItemData> items,
    required List<TodoListData> lists,
    required List<String> independentTodoIds,
  }) async {
    await Future.wait([
      saveTodoItems(items),
      saveTodoLists(lists),
      saveIndependentTodoIds(independentTodoIds),
    ]);
  }

  // 便捷方法：获取完整的 TODO 数据结构
  static Future<Map<String, dynamic>> getAllData() async {
    final results = await Future.wait([
      getTodoItems(),
      getTodoLists(),
      getIndependentTodoIds(),
    ]);

    return {
      'items': results[0] as Map<String, TodoItemData>,
      'lists': results[1] as List<TodoListData>,
      'independentTodoIds': results[2] as List<String>,
    };
  }

  // === 同步元数据方法 ===

  /// 保存同步元数据（按项目ID存储）
  static Future<void> saveSyncMetadata(
      Map<String, SyncMetadata> metadata) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonMap = metadata.map((key, value) => MapEntry(key, value.toJson()));
    await prefs.setString(_keySyncMetadata, jsonEncode(jsonMap));
    debugPrint(
        '💾 TodoStorage: Saved sync metadata for ${metadata.length} items');
  }

  /// 获取所有同步元数据
  static Future<Map<String, SyncMetadata>> getSyncMetadata() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_keySyncMetadata);
    if (jsonStr == null) {
      debugPrint('📂 TodoStorage: No sync metadata found');
      return {};
    }

    final Map<String, dynamic> jsonMap = jsonDecode(jsonStr);
    final metadata = jsonMap.map(
      (key, value) => MapEntry(key, SyncMetadata.fromJson(value)),
    );
    debugPrint(
        '📂 TodoStorage: Loaded sync metadata for ${metadata.length} items');
    return metadata;
  }

  /// 获取单个项目的同步元数据
  static Future<SyncMetadata?> getItemSyncMetadata(String itemId) async {
    final allMetadata = await getSyncMetadata();
    return allMetadata[itemId];
  }

  /// 保存单个项目的同步元数据
  static Future<void> saveItemSyncMetadata(
      String itemId, SyncMetadata metadata) async {
    final allMetadata = await getSyncMetadata();
    allMetadata[itemId] = metadata;
    await saveSyncMetadata(allMetadata);
  }

  /// 删除项目的同步元数据
  static Future<void> deleteItemSyncMetadata(String itemId) async {
    final allMetadata = await getSyncMetadata();
    allMetadata.remove(itemId);
    await saveSyncMetadata(allMetadata);
  }
}
