import 'package:flutter/material.dart';
import 'dart:async';
import 'add_todo_dialog.dart';
import 'add_list_dialog.dart';
import '../../services/todo_storage.dart';
import '../../services/sync_service.dart';

// TodoItem 数据模型（单个 Todo）
class TodoItem {
  String id;
  String title;
  String? description;
  bool isCompleted;
  DateTime createdAt;
  String? listId; // 所属列表ID

  // 构造函数
  TodoItem({
    required this.id,
    required this.title,
    this.description,
    this.isCompleted = false,
    required this.createdAt,
    this.listId,
  });
}

// 可拖拽的 TodoItem 组件
class TodoItemWidget extends StatelessWidget {
  final TodoItem todo;
  final Color listColor;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final int index; // index for ReorderableDragStartListener

  const TodoItemWidget({
    super.key,
    required this.todo,
    required this.listColor,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: const TextScaler.linear(1.0)),
      child: LongPressDraggable<TodoItem>(
        data: todo,
        delay: const Duration(milliseconds: 300),
        onDragStarted: () {
          debugPrint(
              'Todo drag started: ${todo.id} (from list ${todo.listId})');
        },
        onDragEnd: (details) {
          debugPrint(
              'Todo drag ended: ${todo.id}, wasAccepted=${details.wasAccepted}');
        },
        // 拖的效果
        feedback: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          // 拖出来的框
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: listColor, width: 2),
            ),
            child: Text(
              todo.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        // 拖动时原位置的效果
        childWhenDragging: Opacity(
          opacity: 0.3,
          child: _buildTodoContent(context),
        ),
        child: _buildTodoContent(context),
      ),
    );
  }

  Widget _buildTodoContent(BuildContext context) {
    return Dismissible(
      key: Key(todo.id),
      // 完成的背景 (向右滑动)
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.green,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerLeft,
        child: const Icon(Icons.check, color: Colors.white),
      ),
      // 删除的背景 (向左滑动)
      secondaryBackground: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      // 确认删除
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onToggle();
          return false;
        } else {
          return await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('删除任务'),
              content: const Text('确定要删除这个任务吗？'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('删除', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
        }
      },
      onDismissed: (direction) {
        if (direction == DismissDirection.endToStart) {
          onDelete();
        }
      },
      // 单个 Todo 内容
      child: Container(
        // Insets: 内边距
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // 圆形复选框（更接近 Microsoft To Do）
                GestureDetector(
                  onTap: onToggle,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: todo.isCompleted ? listColor : Colors.transparent,
                      border: Border.all(
                        color: todo.isCompleted ? listColor : Colors.grey[350]!,
                        width: 2,
                      ),
                    ),
                    child: todo.isCompleted
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                // 任务内容
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        todo.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          decoration: todo.isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          color: todo.isCompleted ? Colors.grey : null,
                        ),
                      ),
                      if (todo.description != null &&
                          todo.description!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          todo.description!,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            decoration: todo.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // 拖拽手柄（仅用于列表内拖拽）
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Icon(Icons.drag_handle, color: Colors.grey[400]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// TodoList 数据模型（列表组）
class TodoList {
  String id;
  String name;
  bool isExpanded;
  Color color;
  List<TodoItem> items;

  TodoList({
    required this.id,
    required this.name,
    this.isExpanded = true,
    this.color = Colors.blue,
    List<TodoItem>? items,
  }) : items = items ?? [];
}

// TodoList 列表组件（可折叠的列表）
class TodoListWidget extends StatelessWidget {
  final TodoList todoList;
  final int index; // index for list reorder handle
  final VoidCallback onToggleExpand;
  final Function(String todoId) onToggleTodo;
  final Function(String todoId) onDeleteTodo;
  final Function(TodoItem todo) onEditTodo;
  final VoidCallback onDeleteList;
  final VoidCallback onEditList;
  final Function(TodoItem todo) onAcceptDrop;
  final Function(int oldIndex, int newIndex) onReorderTodos;

  const TodoListWidget({
    super.key,
    required this.todoList,
    required this.index,
    required this.onToggleExpand,
    required this.onToggleTodo,
    required this.onDeleteTodo,
    required this.onEditTodo,
    required this.onDeleteList,
    required this.onEditList,
    required this.onAcceptDrop,
    required this.onReorderTodos,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<TodoItem>(
      onAcceptWithDetails: (details) => onAcceptDrop(details.data),
      builder: (context, candidateData, rejectedData) {
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          color: candidateData.isNotEmpty
              ? todoList.color.withValues(alpha: 0.1)
              : null,
          child: Column(
            children: [
              // 列表标题栏
              InkWell(
                onTap: onToggleExpand,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      // 折叠图标
                      Icon(
                        todoList.isExpanded
                            ? Icons.expand_more
                            : Icons.chevron_right,
                        color: todoList.color,
                      ),
                      const SizedBox(width: 8),
                      // 颜色标记
                      Container(
                        width: 4,
                        height: 20,
                        decoration: BoxDecoration(
                          color: todoList.color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 列表名称
                      Expanded(
                        child: Text(
                          todoList.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // Todo 数量
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: todoList.color.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${todoList.items.length}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: todoList.color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 更多选项
                      // 拖拽手柄（长按 0.5s 开始拖动，用于列表重排）
                      ReorderableDelayedDragStartListener(
                        index: index,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child:
                              Icon(Icons.drag_handle, color: Colors.grey[600]),
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, color: Colors.grey[600]),
                        onSelected: (value) {
                          if (value == 'edit') {
                            onEditList();
                          } else if (value == 'delete') {
                            onDeleteList();
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 20),
                                SizedBox(width: 8),
                                Text('编辑'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 20, color: Colors.red),
                                SizedBox(width: 8),
                                Text('删除', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Todo 列表
              if (todoList.isExpanded)
                if (todoList.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '暂无 Todo',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                  )
                else
                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false, // 禁用默认拖拽手柄，使用自定义手柄
                    itemCount: todoList.items.length,
                    onReorder: onReorderTodos,
                    itemBuilder: (context, index) {
                      final todo = todoList.items[index];
                      return TodoItemWidget(
                        key: ValueKey(todo.id),
                        todo: todo,
                        listColor: todoList.color,
                        onToggle: () => onToggleTodo(todo.id),
                        onDelete: () => onDeleteTodo(todo.id),
                        onEdit: () => onEditTodo(todo),
                        index: index,
                      );
                    },
                  ),
            ],
          ),
        );
      },
    );
  }
}

// Todo 页面主组件
class TodoPage extends StatefulWidget {
  final SyncService? syncService; // 🆕 添加同步服务

  const TodoPage({super.key, this.syncService});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  final List<TodoList> _todoLists = [];
  bool _isLoading = true;
  StreamSubscription? _dataUpdateSubscription; // 🆕 监听同步数据更新

  @override
  void initState() {
    super.initState();
    _loadData();
    _setupSyncListener(); // 🆕 设置同步监听
  }

  @override
  void dispose() {
    _dataUpdateSubscription?.cancel(); // 🆕 取消监听
    super.dispose();
  }

  // 🆕 设置同步监听器
  void _setupSyncListener() {
    if (widget.syncService != null) {
      _dataUpdateSubscription =
          widget.syncService!.dataUpdatedStream.listen((event) {
        // 当收到 todos 数据更新时刷新页面
        if (event.dataType == 'todos' && mounted) {
          debugPrint('🔄 [TodoPage] 收到远程数据更新，刷新页面');
          _loadData();
        }
      });
    }
  }

  // 从存储加载数据
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    debugPrint('📂 Loading TODO data...');

    final data = await TodoStorage.getAllData();
    final itemsMap = data['items'] as Map<String, TodoItemData>;
    final listsData = data['lists'] as List<TodoListData>;

    debugPrint(
        '📊 Loaded: ${itemsMap.length} items, ${listsData.length} lists');

    if (mounted) {
      setState(() {
        _todoLists.clear();

        // 重建 TodoList 对象
        for (var listData in listsData) {
          final items = listData.itemIds
              .where((id) => itemsMap.containsKey(id))
              .map((id) {
            final itemData = itemsMap[id]!;
            return TodoItem(
              id: itemData.id,
              title: itemData.title,
              description: itemData.description,
              isCompleted: itemData.isCompleted,
              createdAt: itemData.createdAt,
              listId: itemData.listId,
            );
          }).toList();

          _todoLists.add(TodoList(
            id: listData.id,
            name: listData.name,
            isExpanded: listData.isExpanded,
            color: listData.color,
            items: items,
          ));
        }

        // 如果没有数据，添加示例数据
        if (_todoLists.isEmpty) {
          debugPrint('⚠️ No data found, adding sample data');
          _addSampleData();
        }

        _isLoading = false;
      });
    }
  }

  // 添加示例数据
  void _addSampleData() {
    _todoLists.addAll([
      TodoList(
        id: '1',
        name: '工作',
        color: Colors.blue,
        items: [
          TodoItem(
            id: '1',
            title: '完成项目报告',
            description: '准备本周项目进度报告',
            createdAt: DateTime.now(),
            listId: '1',
          ),
          TodoItem(
            id: '2',
            title: '团队会议',
            createdAt: DateTime.now(),
            listId: '1',
          ),
        ],
      ),
      TodoList(
        id: '2',
        name: '个人',
        color: Colors.green,
        items: [
          TodoItem(
            id: '3',
            title: '健身打卡',
            description: '跑步30分钟',
            createdAt: DateTime.now(),
            listId: '2',
          ),
        ],
      ),
      TodoList(
        id: '3',
        name: '学习',
        color: Colors.orange,
        items: [
          TodoItem(
            id: '4',
            title: '阅读《Flutter实战》',
            createdAt: DateTime.now(),
            listId: '3',
          ),
        ],
      ),
    ]);

    // 保存示例数据
    _saveData();
  }

  // 保存数据到存储
  Future<void> _saveData() async {
    debugPrint('💾 Saving TODO data...');

    // 构建 items map
    final Map<String, TodoItemData> itemsMap = {};
    for (var list in _todoLists) {
      for (var item in list.items) {
        itemsMap[item.id] = TodoItemData(
          id: item.id,
          title: item.title,
          description: item.description,
          isCompleted: item.isCompleted,
          createdAt: item.createdAt,
          listId: item.listId,
        );
      }
    }

    // 构建 lists data
    final listsData = _todoLists
        .map((list) => TodoListData(
              id: list.id,
              name: list.name,
              isExpanded: list.isExpanded,
              colorValue: list.color.toARGB32(),
              itemIds: list.items.map((item) => item.id).toList(),
            ))
        .toList();

    await TodoStorage.saveAllData(
      items: itemsMap,
      lists: listsData,
      independentTodoIds: [], // 暂时不支持独立 TODO
    );

    debugPrint(
        '✅ TODO data saved: ${itemsMap.length} items, ${listsData.length} lists');

    // 🆕 触发同步到所有已连接设备
    _triggerSync();
  }

  // 🆕 触发同步到所有已连接设备
  void _triggerSync() {
    if (widget.syncService != null && widget.syncService!.isEnabled) {
      final connectedDevices = widget.syncService!.connectedDevices;
      if (connectedDevices.isNotEmpty) {
        debugPrint('🔄 [TodoPage] 触发同步到 ${connectedDevices.length} 个设备');
        for (var device in connectedDevices) {
          widget.syncService!.syncAllDataToDevice(device.deviceId);
        }
      }
    }
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('新建列表'),
              onTap: () {
                Navigator.pop(context);
                _addTodoList();
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_task),
              title: const Text('新建 Todo'),
              onTap: () {
                Navigator.pop(context);
                _addTodoToList();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _addTodoList() {
    showDialog(
      context: context,
      builder: (context) => AddListDialog(
        onAdd: (name, color) async {
          setState(() {
            _todoLists.add(TodoList(
              id: DateTime.now().toString(),
              name: name,
              color: color,
            ));
          });
          await _saveData(); // 保存数据
        },
      ),
    );
  }

  void _addTodoToList() {
    showDialog(
      context: context,
      builder: (context) => AddTodoDialog(
        todoLists: _todoLists,
        onAdd: (title, description, listId) async {
          setState(() {
            if (listId != null) {
              // 添加到指定列表
              final list = _todoLists.firstWhere((l) => l.id == listId);
              list.items.add(TodoItem(
                id: DateTime.now().toString(),
                title: title,
                description: description,
                createdAt: DateTime.now(),
                listId: listId,
              ));
            }
          });
          await _saveData(); // 保存数据
        },
      ),
    );
  }

  void _toggleTodo(String listId, String todoId) async {
    setState(() {
      final list = _todoLists.firstWhere((l) => l.id == listId);
      final todo = list.items.firstWhere((t) => t.id == todoId);
      todo.isCompleted = !todo.isCompleted;
    });
    await _saveData(); // 保存数据
  }

  void _deleteTodo(String listId, String todoId) async {
    // 🆕 标记为已删除（用于同步）
    final syncMetadata = await TodoStorage.getSyncMetadata();
    final deviceId = widget.syncService?.currentDevice?.deviceId ?? 'local';
    final itemMetadata = syncMetadata[todoId];
    if (itemMetadata != null) {
      // 更新元数据为已删除状态
      syncMetadata[todoId] = itemMetadata.markDeleted(deviceId);
      await TodoStorage.saveSyncMetadata(syncMetadata);
      debugPrint('🗑️ [TodoPage] 标记待办项为已删除: $todoId');
    }

    setState(() {
      final list = _todoLists.firstWhere((l) => l.id == listId);
      list.items.removeWhere((t) => t.id == todoId);
    });
    await _saveData(); // 保存数据
  }

  void _editTodo(TodoItem todo) {
    showDialog(
      context: context,
      builder: (context) => AddTodoDialog(
        todoLists: _todoLists,
        initialTitle: todo.title,
        initialDescription: todo.description,
        initialListId: todo.listId,
        isEdit: true,
        onAdd: (title, description, newListId) async {
          setState(() {
            final oldListId = todo.listId;

            // 如果列表改变了，需要移动 todo
            if (newListId != oldListId && newListId != null) {
              // 从原位置移除
              if (oldListId != null) {
                final oldList = _todoLists.firstWhere((l) => l.id == oldListId);
                oldList.items.removeWhere((t) => t.id == todo.id);
              }

              // 添加到新位置
              todo.listId = newListId;
              final newList = _todoLists.firstWhere((l) => l.id == newListId);
              newList.items.add(todo);
            }

            // 更新内容
            todo.title = title;
            todo.description = description;
          });
          await _saveData(); // 保存数据
        },
      ),
    );
  }

  void _deleteList(String listId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除列表'),
        content: const Text('确定要删除这个列表吗？列表中的所有 Todo 也将被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              // 🆕 标记列表为已删除（用于同步）
              final syncMetadata = await TodoStorage.getSyncMetadata();
              final deviceId =
                  widget.syncService?.currentDevice?.deviceId ?? 'local';
              final listMetadataId = 'list_$listId';
              final listMetadata = syncMetadata[listMetadataId];
              if (listMetadata != null) {
                // 更新元数据为已删除状态
                syncMetadata[listMetadataId] =
                    listMetadata.markDeleted(deviceId);
                await TodoStorage.saveSyncMetadata(syncMetadata);
                debugPrint('🗑️ [TodoPage] 标记列表为已删除: $listId');
              }

              // 🆕 同时标记列表中的所有待办项为已删除
              final list = _todoLists.firstWhere((l) => l.id == listId);
              for (var item in list.items) {
                final itemMetadata = syncMetadata[item.id];
                if (itemMetadata != null) {
                  syncMetadata[item.id] = itemMetadata.markDeleted(deviceId);
                  debugPrint('🗑️ [TodoPage] 标记待办项为已删除: ${item.id}');
                }
              }
              await TodoStorage.saveSyncMetadata(syncMetadata);

              setState(() {
                _todoLists.removeWhere((l) => l.id == listId);
              });
              await _saveData(); // 保存数据
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _editList(TodoList list) {
    showDialog(
      context: context,
      builder: (context) => AddListDialog(
        initialName: list.name,
        initialColor: list.color,
        isEdit: true,
        onAdd: (name, color) async {
          setState(() {
            list.name = name;
            list.color = color;
          });
          await _saveData(); // 保存数据
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _todoLists.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('To Do'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.only(top: 40),
              child: isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.checklist,
                            size: 80,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '还没有任何任务',
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.grey[400],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '点击 + 开始添加',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[400],
                            ),
                          ),
                        ],
                      ),
                    )
                  : CustomScrollView(
                      slivers: [
                        // 列表区域
                        SliverReorderableList(
                          itemCount: _todoLists.length,
                          onReorder: (oldIndex, newIndex) async {
                            setState(() {
                              if (newIndex > oldIndex) {
                                newIndex -= 1;
                              }
                              final movingList = _todoLists[oldIndex];
                              debugPrint(
                                  'Reordering lists ${movingList.id}: $oldIndex -> $newIndex');
                              final list = _todoLists.removeAt(oldIndex);
                              _todoLists.insert(newIndex, list);
                            });
                            await _saveData(); // 保存数据
                          },
                          itemBuilder: (context, index) {
                            final todoList = _todoLists[index];
                            return Padding(
                              key: ValueKey(todoList.id),
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              child: TodoListWidget(
                                index: index,
                                todoList: todoList,
                                onToggleExpand: () async {
                                  setState(() {
                                    todoList.isExpanded = !todoList.isExpanded;
                                  });
                                  await _saveData(); // 保存数据
                                },
                                onToggleTodo: (todoId) =>
                                    _toggleTodo(todoList.id, todoId),
                                onDeleteTodo: (todoId) =>
                                    _deleteTodo(todoList.id, todoId),
                                onEditTodo: (todo) => _editTodo(todo),
                                onDeleteList: () => _deleteList(todoList.id),
                                onEditList: () => _editList(todoList),
                                onAcceptDrop: (todo) async {
                                  setState(() {
                                    debugPrint(
                                        'Dropped todo ${todo.id} onto list ${todoList.id} (from ${todo.listId})');
                                    // 从原列表移除
                                    if (todo.listId != null &&
                                        todo.listId != todoList.id) {
                                      final oldList = _todoLists.firstWhere(
                                          (l) => l.id == todo.listId);
                                      oldList.items
                                          .removeWhere((t) => t.id == todo.id);
                                    }
                                    // 添加到新列表
                                    todo.listId = todoList.id;
                                    if (!todoList.items
                                        .any((t) => t.id == todo.id)) {
                                      todoList.items.add(todo);
                                    }
                                  });
                                  await _saveData(); // 保存数据
                                },
                                onReorderTodos: (oldIndex, newIndex) async {
                                  setState(() {
                                    if (newIndex > oldIndex) {
                                      newIndex -= 1;
                                    }
                                    final moving = todoList.items[oldIndex];
                                    debugPrint(
                                        'Reordering todo ${moving.id} in list ${todoList.id}: $oldIndex -> $newIndex');
                                    final todo =
                                        todoList.items.removeAt(oldIndex);
                                    todoList.items.insert(newIndex, todo);
                                  });
                                  await _saveData(); // 保存数据
                                },
                              ),
                            );
                          },
                        ),
                      ],
                    ),
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'todoFAB',
        onPressed: _showAddOptions,
        child: const Icon(Icons.add),
      ),
    );
  }
}
