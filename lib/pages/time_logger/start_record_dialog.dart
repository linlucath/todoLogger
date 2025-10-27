import 'package:flutter/material.dart';
import '../../widgets/todo_selector_dialog.dart';

// 开始活动对话框
class StartActivityDialog extends StatefulWidget {
  final List<String> activityHistory;

  const StartActivityDialog({
    required this.activityHistory,
  });

  @override
  State<StartActivityDialog> createState() => _StartActivityDialogState();
}

class _StartActivityDialogState extends State<StartActivityDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _selectedTodoId;
  String? _selectedTodoTitle;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;

    Navigator.of(context).pop({
      'name': name,
      'todoId': _selectedTodoId,
      'todoTitle': _selectedTodoTitle,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('What are you doing now?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'e.g., Studying English',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),

          if (widget.activityHistory.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Recent activities:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.activityHistory.map((activity) {
                return ActionChip(
                  label: Text(activity),
                  onPressed: () {
                    _controller.text = activity;
                  },
                );
              }).toList(),
            ),
          ],

          const SizedBox(height: 16),

          // TODO关联（可选）
          OutlinedButton.icon(
            onPressed: () async {
              final result = await showDialog<Map<String, dynamic>>(
                context: context,
                builder: (context) => TodoSelectorDialog(
                  selectedTodoId: _selectedTodoId,
                ),
              );

              if (result != null) {
                setState(() {
                  _selectedTodoId = result['todoId'] as String?;
                  _selectedTodoTitle = result['todoTitle'] as String?;
                });
              }
            },
            icon: Icon(_selectedTodoTitle == null ? Icons.add : Icons.check),
            label: Text(
              _selectedTodoTitle == null
                  ? 'Link to TODO (Optional)'
                  : 'TODO: $_selectedTodoTitle',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Start'),
        ),
      ],
    );
  }
}
