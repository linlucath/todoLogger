import 'package:flutter/material.dart';
import '../../services/todo_storage.dart';

class TodoSelectorDialog extends StatefulWidget {
  final String? selectedTodoId;

  const TodoSelectorDialog({
    super.key,
    this.selectedTodoId,
  });

  @override
  State<TodoSelectorDialog> createState() => _TodoSelectorDialogState();
}

class _TodoSelectorDialogState extends State<TodoSelectorDialog> {
  Map<String, TodoItemData> _allTodos = {};
  List<TodoListData> _todoLists = [];
  bool _isLoading = true;
  String? _selectedTodoId;

  @override
  void initState() {
    super.initState();
    _selectedTodoId = widget.selectedTodoId;
    _loadTodos();
  }

  Future<void> _loadTodos() async {
    setState(() => _isLoading = true);

    final data = await TodoStorage.getAllData();
    final items = data['items'] as Map<String, TodoItemData>;
    final lists = data['lists'] as List<TodoListData>;

    if (mounted) {
      setState(() {
        _allTodos = items;
        _todoLists = lists;
        _isLoading = false;
      });
    }
  }

  // 获取某个列表中的未完成TODO
  List<TodoItemData> _getTodosForList(String listId) {
    return _allTodos.values
        .where((todo) => todo.listId == listId && !todo.isCompleted)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)); // 最新的在前
  }

  // 获取所有未完成的TODO（按列表分组）
  Map<TodoListData, List<TodoItemData>> get _groupedTodos {
    final Map<TodoListData, List<TodoItemData>> grouped = {};

    for (var list in _todoLists) {
      final todos = _getTodosForList(list.id);
      if (todos.isNotEmpty) {
        grouped[list] = todos;
      }
    }

    return grouped;
  }

  void _selectTodo(String? todoId, String? todoTitle) {
    Navigator.of(context).pop({
      'todoId': todoId,
      'todoTitle': todoTitle,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(
          maxHeight: 600,
          maxWidth: 400,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.link,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Link to a TODO',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // 内容区域
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildTodoList(),
            ),

            // 底部按钮
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_selectedTodoId != null)
                    TextButton(
                      onPressed: () => _selectTodo(null, null),
                      child: const Text('Remove link'),
                    ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodoList() {
    final grouped = _groupedTodos;

    if (grouped.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No active TODOs',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create some TODOs first',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final list = grouped.keys.elementAt(index);
        final todos = grouped[list]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 列表名称
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 16,
                    decoration: BoxDecoration(
                      color: list.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    list.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(${todos.length})',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),

            // TODO 列表
            ...todos.map((todo) => _buildTodoItem(todo, list.color)),

            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _buildTodoItem(TodoItemData todo, Color listColor) {
    final isSelected = _selectedTodoId == todo.id;

    return InkWell(
      onTap: () => _selectTodo(todo.id, todo.title),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? listColor.withValues(alpha: 0.1) : null,
          border: Border(
            left: BorderSide(
              color: isSelected ? listColor : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          children: [
            // 选中指示器
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? listColor : Colors.grey[400]!,
                  width: 2,
                ),
                color: isSelected ? listColor : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check,
                      size: 14,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(width: 12),

            // TODO内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    todo.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  if (todo.description != null &&
                      todo.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      todo.description!,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            // 选中图标
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: listColor,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
