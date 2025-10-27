import 'package:flutter/material.dart';
import 'todo.dart';

// 添加/编辑 Todo 对话框
class AddTodoDialog extends StatefulWidget {
  final List<TodoList> todoLists;
  final Function(String title, String? description, String? listId) onAdd;
  final String? initialTitle;
  final String? initialDescription;
  final String? initialListId;
  final bool isEdit;

  const AddTodoDialog({
    super.key,
    required this.todoLists,
    required this.onAdd,
    this.initialTitle,
    this.initialDescription,
    this.initialListId,
    this.isEdit = false,
  });

  @override
  State<AddTodoDialog> createState() => _AddTodoDialogState();
}

class _AddTodoDialogState extends State<AddTodoDialog> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late String? _selectedListId;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTitle);
    _descriptionController =
        TextEditingController(text: widget.initialDescription);
    _selectedListId = widget.initialListId ??
        (widget.todoLists.isEmpty ? null : widget.todoLists.first.id);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isEdit ? '编辑任务' : '新建任务'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '标题',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: '描述（可选）',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _selectedListId,
              decoration: const InputDecoration(
                labelText: '选择列表',
                border: OutlineInputBorder(),
              ),
              items: [
                // 独立 Todo 选项
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Row(
                    children: [
                      Icon(Icons.check_box_outline_blank,
                          size: 16, color: Colors.grey),
                      SizedBox(width: 8),
                      Text('独立 Todo（不属于任何列表）'),
                    ],
                  ),
                ),
                // 各个列表选项
                ...widget.todoLists.map((list) {
                  return DropdownMenuItem<String?>(
                    value: list.id,
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: list.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(list.name),
                      ],
                    ),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedListId = value;
                });
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_titleController.text.isNotEmpty) {
              widget.onAdd(
                _titleController.text,
                _descriptionController.text.isEmpty
                    ? null
                    : _descriptionController.text,
                _selectedListId,
              );
              Navigator.pop(context);
            }
          },
          child: Text(widget.isEdit ? '保存' : '添加'),
        ),
      ],
    );
  }
}
