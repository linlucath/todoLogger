import 'package:flutter/material.dart';
import 'add_todo_dialog.dart';
import 'add_list_dialog.dart';

// TodoItem 数据模型（单个 Todo）
class TodoItem {
  String id;
  String title;
  String? description;
  bool isCompleted;
  DateTime createdAt;
  String? listId; // 所属列表ID（可选，null 表示独立 Todo）

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
    return LongPressDraggable<TodoItem>(
      data: todo,
      onDragStarted: () {
        debugPrint('Todo drag started: ${todo.id} (from list ${todo.listId})');
      },
      onDragEnd: (details) {
        debugPrint(
            'Todo drag ended: ${todo.id}, wasAccepted=${details.wasAccepted}');
      },
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
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
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildTodoContent(context),
      ),
      child: _buildTodoContent(context),
    );
  }

  Widget _buildTodoContent(BuildContext context) {
    return Dismissible(
      key: Key(todo.id),
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
      child: Container(
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
                  color: Colors.black.withOpacity(0.03),
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
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  final List<TodoList> _todoLists = [];
  final List<TodoItem> _standaloneTodos = []; // 独立的 Todo（不属于任何列表）

  @override
  void initState() {
    super.initState();
    // 添加示例数据
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

    // 添加一些独立的 Todo
    _standaloneTodos.addAll([
      TodoItem(
        id: '5',
        title: '快速备忘：买牛奶',
        createdAt: DateTime.now(),
      ),
      TodoItem(
        id: '6',
        title: '给妈妈打电话',
        createdAt: DateTime.now(),
      ),
    ]);
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
        onAdd: (name, color) {
          setState(() {
            _todoLists.add(TodoList(
              id: DateTime.now().toString(),
              name: name,
              color: color,
            ));
          });
        },
      ),
    );
  }

  void _addTodoToList() {
    showDialog(
      context: context,
      builder: (context) => AddTodoDialog(
        todoLists: _todoLists,
        onAdd: (title, description, listId) {
          setState(() {
            if (listId == null) {
              // 添加为独立 Todo
              _standaloneTodos.add(TodoItem(
                id: DateTime.now().toString(),
                title: title,
                description: description,
                createdAt: DateTime.now(),
              ));
            } else {
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
        },
      ),
    );
  }

  void _toggleTodo(String? listId, String todoId) {
    setState(() {
      if (listId == null) {
        final todo = _standaloneTodos.firstWhere((t) => t.id == todoId);
        todo.isCompleted = !todo.isCompleted;
      } else {
        final list = _todoLists.firstWhere((l) => l.id == listId);
        final todo = list.items.firstWhere((t) => t.id == todoId);
        todo.isCompleted = !todo.isCompleted;
      }
    });
  }

  void _deleteTodo(String? listId, String todoId) {
    setState(() {
      if (listId == null) {
        _standaloneTodos.removeWhere((t) => t.id == todoId);
      } else {
        final list = _todoLists.firstWhere((l) => l.id == listId);
        list.items.removeWhere((t) => t.id == todoId);
      }
    });
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
        onAdd: (title, description, newListId) {
          setState(() {
            final oldListId = todo.listId;

            // 如果列表改变了，需要移动 todo
            if (newListId != oldListId) {
              // 从原位置移除
              if (oldListId == null) {
                _standaloneTodos.removeWhere((t) => t.id == todo.id);
              } else {
                final oldList = _todoLists.firstWhere((l) => l.id == oldListId);
                oldList.items.removeWhere((t) => t.id == todo.id);
              }

              // 添加到新位置
              todo.listId = newListId;
              if (newListId == null) {
                _standaloneTodos.add(todo);
              } else {
                final newList = _todoLists.firstWhere((l) => l.id == newListId);
                newList.items.add(todo);
              }
            }

            // 更新内容
            todo.title = title;
            todo.description = description;
          });
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
            onPressed: () {
              setState(() {
                _todoLists.removeWhere((l) => l.id == listId);
              });
              Navigator.pop(context);
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
        onAdd: (name, color) {
          setState(() {
            list.name = name;
            list.color = color;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _todoLists.isEmpty && _standaloneTodos.isEmpty;

    return Scaffold(
      body: isEmpty
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
                // 独立 Todo 区域
                if (_standaloneTodos.isNotEmpty) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.check_box_outline_blank,
                              size: 20, color: Colors.grey),
                          const SizedBox(width: 8),
                          const Text(
                            '独立 Todo',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '${_standaloneTodos.length}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverReorderableList(
                    itemCount: _standaloneTodos.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) {
                          newIndex -= 1;
                        }
                        final moving = _standaloneTodos[oldIndex];
                        debugPrint(
                            'Reordering standalone todo ${moving.id}: $oldIndex -> $newIndex');
                        final todo = _standaloneTodos.removeAt(oldIndex);
                        _standaloneTodos.insert(newIndex, todo);
                      });
                    },
                    itemBuilder: (context, index) {
                      final todo = _standaloneTodos[index];
                      return Padding(
                        key: ValueKey(todo.id),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TodoItemWidget(
                          todo: todo,
                          listColor: Colors.grey,
                          onToggle: () => _toggleTodo(null, todo.id),
                          onDelete: () => _deleteTodo(null, todo.id),
                          onEdit: () => _editTodo(todo),
                          index: index,
                        ),
                      );
                    },
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],

                // 列表区域
                SliverReorderableList(
                  itemCount: _todoLists.length,
                  onReorder: (oldIndex, newIndex) {
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
                  },
                  itemBuilder: (context, index) {
                    final todoList = _todoLists[index];
                    return Padding(
                      key: ValueKey(todoList.id),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: TodoListWidget(
                        index: index,
                        todoList: todoList,
                        onToggleExpand: () {
                          setState(() {
                            todoList.isExpanded = !todoList.isExpanded;
                          });
                        },
                        onToggleTodo: (todoId) =>
                            _toggleTodo(todoList.id, todoId),
                        onDeleteTodo: (todoId) =>
                            _deleteTodo(todoList.id, todoId),
                        onEditTodo: (todo) => _editTodo(todo),
                        onDeleteList: () => _deleteList(todoList.id),
                        onEditList: () => _editList(todoList),
                        onAcceptDrop: (todo) {
                          setState(() {
                            debugPrint(
                                'Dropped todo ${todo.id} onto list ${todoList.id} (from ${todo.listId})');
                            // 从原列表或独立列表移除
                            if (todo.listId == null) {
                              _standaloneTodos
                                  .removeWhere((t) => t.id == todo.id);
                            } else {
                              final oldList = _todoLists
                                  .firstWhere((l) => l.id == todo.listId);
                              oldList.items.removeWhere((t) => t.id == todo.id);
                            }
                            // 添加到新列表
                            todo.listId = todoList.id;
                            todoList.items.add(todo);
                          });
                        },
                        onReorderTodos: (oldIndex, newIndex) {
                          setState(() {
                            if (newIndex > oldIndex) {
                              newIndex -= 1;
                            }
                            final moving = todoList.items[oldIndex];
                            debugPrint(
                                'Reordering todo ${moving.id} in list ${todoList.id}: $oldIndex -> $newIndex');
                            final todo = todoList.items.removeAt(oldIndex);
                            todoList.items.insert(newIndex, todo);
                          });
                        },
                      ),
                    );
                  },
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddOptions,
        child: const Icon(Icons.add),
      ),
    );
  }
}
