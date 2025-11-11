import 'package:flutter/material.dart';

/// 编辑活动名称对话框
class EditActivityDialog extends StatefulWidget {
  final String currentName;
  final List<String> activityHistory;

  const EditActivityDialog({
    super.key,
    required this.currentName,
    required this.activityHistory,
  });

  @override
  State<EditActivityDialog> createState() => _EditActivityDialogState();
}

class _EditActivityDialogState extends State<EditActivityDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
    // 自动选中所有文本，方便快速修改
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.currentName.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      // 如果为空，显示提示
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Activity name cannot be empty'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.edit, size: 24),
          SizedBox(width: 8),
          Text('Edit Activity Name'),
        ],
      ),
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
              labelText: 'Activity Name',
            ),
            onSubmitted: (_) => _submit(),
          ),

          // 历史活动建议
          if (widget.activityHistory.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              'Recent activities:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            // 限制高度，最多显示3行标签
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 120, // 约3行的高度：(32 + 8) * 3
              ),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.activityHistory
                      .where((activity) => activity != widget.currentName)
                      .map((activity) {
                    return ActionChip(
                      label: Text(activity),
                      onPressed: () {
                        _controller.text = activity;
                        _controller.selection = TextSelection(
                          baseOffset: 0,
                          extentOffset: activity.length,
                        );
                      },
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
