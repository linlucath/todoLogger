import 'package:flutter/material.dart';
import 'models.dart';
import '../../services/todo_storage.dart';

/// 目标编辑对话框
class TargetEditDialog extends StatefulWidget {
  final Target? target; // null 表示新建

  const TargetEditDialog({super.key, this.target});

  @override
  State<TargetEditDialog> createState() => _TargetEditDialogState();
}

class _TargetEditDialogState extends State<TargetEditDialog> {
  late TextEditingController _nameController;
  late TargetType _selectedType;
  late TimePeriod _selectedPeriod;
  late int _targetHours;
  late int _targetMinutes;
  late List<String> _selectedTodoIds;
  late Color _selectedColor;

  List<TodoItemData> _allTodos = [];
  Map<String, String> _todoListNames = {}; // TODO ID -> List Name
  bool _isLoadingTodos = true;

  @override
  void initState() {
    super.initState();
    final target = widget.target;

    _nameController = TextEditingController(text: target?.name ?? '');
    _selectedType = target?.type ?? TargetType.achievement;
    _selectedPeriod = target?.period ?? TimePeriod.daily;

    final targetSeconds = target?.targetSeconds ?? 3600; // 默认1小时
    _targetHours = targetSeconds ~/ 3600;
    _targetMinutes = (targetSeconds % 3600) ~/ 60;

    _selectedTodoIds = target?.linkedTodoIds ?? [];
    _selectedColor = target?.color ?? Colors.blue;

    _loadTodos();
  }

  Future<void> _loadTodos() async {
    final data = await TodoStorage.getAllData();
    final items = data['items'] as Map<String, TodoItemData>;
    final lists = data['lists'] as List<TodoListData>;

    // 构建 TODO -> List 映射
    final Map<String, String> listNames = {};
    for (final list in lists) {
      for (final itemId in list.itemIds) {
        listNames[itemId] = list.name;
      }
    }

    setState(() {
      _allTodos = items.values.toList();
      _todoListNames = listNames;
      _isLoadingTodos = false;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入目标名称')),
      );
      return;
    }

    final targetSeconds = _targetHours * 3600 + _targetMinutes * 60;
    if (targetSeconds == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('目标时长不能为0')),
      );
      return;
    }

    final target = widget.target?.copyWith(
          name: _nameController.text.trim(),
          type: _selectedType,
          period: _selectedPeriod,
          targetSeconds: targetSeconds,
          linkedTodoIds: _selectedTodoIds,
          color: _selectedColor,
        ) ??
        Target(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          name: _nameController.text.trim(),
          type: _selectedType,
          period: _selectedPeriod,
          targetSeconds: targetSeconds,
          linkedTodoIds: _selectedTodoIds,
          color: _selectedColor,
        );

    Navigator.of(context).pop(target);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _selectedColor.withOpacity(0.1),
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.flag, color: _selectedColor),
                  const SizedBox(width: 8),
                  Text(
                    widget.target == null ? '新建目标' : '编辑目标',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // 表单内容
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 目标名称
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: '目标名称',
                        hintText: '例如：学习时长',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 目标类型
                    const Text('目标类型',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: RadioListTile<TargetType>(
                            title: const Text('达成目标'),
                            subtitle: const Text('越多越好'),
                            value: TargetType.achievement,
                            groupValue: _selectedType,
                            onChanged: (value) {
                              setState(() => _selectedType = value!);
                            },
                          ),
                        ),
                        Expanded(
                          child: RadioListTile<TargetType>(
                            title: const Text('限制目标'),
                            subtitle: const Text('不要超过'),
                            value: TargetType.limit,
                            groupValue: _selectedType,
                            onChanged: (value) {
                              setState(() => _selectedType = value!);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 时间周期
                    const Text('时间周期',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: TimePeriod.values.map((period) {
                        final isSelected = _selectedPeriod == period;
                        return ChoiceChip(
                          label: Text(_getPeriodText(period)),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() => _selectedPeriod = period);
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),

                    // 目标时长
                    const Text('目标时长',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: '小时',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            controller: TextEditingController(
                                text: _targetHours.toString()),
                            onChanged: (value) {
                              _targetHours = int.tryParse(value) ?? 0;
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              labelText: '分钟',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            controller: TextEditingController(
                                text: _targetMinutes.toString()),
                            onChanged: (value) {
                              _targetMinutes = int.tryParse(value) ?? 0;
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // 关联 TODO
                    const Text('关联 TODO',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _isLoadingTodos
                        ? const Center(child: CircularProgressIndicator())
                        : _buildTodoSelector(),
                    const SizedBox(height: 16),

                    // 主题颜色
                    const Text('主题颜色',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        Colors.blue,
                        Colors.green,
                        Colors.orange,
                        Colors.red,
                        Colors.purple,
                        Colors.teal,
                        Colors.pink,
                        Colors.indigo,
                      ].map((color) {
                        final isSelected = _selectedColor == color;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedColor = color),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? Border.all(color: Colors.black, width: 3)
                                  : null,
                            ),
                            child: isSelected
                                ? const Icon(Icons.check, color: Colors.white)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),

            // 底部按钮
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _save,
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTodoSelector() {
    if (_allTodos.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('暂无 TODO 项目', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          CheckboxListTile(
            title: const Text('选择全部'),
            value: _selectedTodoIds.length == _allTodos.length,
            tristate: true,
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  _selectedTodoIds = _allTodos.map((t) => t.id).toList();
                } else {
                  _selectedTodoIds = [];
                }
              });
            },
          ),
          const Divider(height: 1),
          ..._allTodos.map((todo) {
            final isSelected = _selectedTodoIds.contains(todo.id);
            final listName = _todoListNames[todo.id];
            return CheckboxListTile(
              title: Text(todo.title),
              subtitle: listName != null ? Text(listName) : null,
              value: isSelected,
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedTodoIds.add(todo.id);
                  } else {
                    _selectedTodoIds.remove(todo.id);
                  }
                });
              },
            );
          }).toList(),
        ],
      ),
    );
  }

  String _getPeriodText(TimePeriod period) {
    switch (period) {
      case TimePeriod.daily:
        return '每日';
      case TimePeriod.weekly:
        return '每周';
      case TimePeriod.monthly:
        return '每月';
      case TimePeriod.yearly:
        return '每年';
    }
  }
}
