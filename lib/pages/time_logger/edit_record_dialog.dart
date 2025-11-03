import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/time_logger_storage.dart';

/// 编辑或创建活动记录对话框
class EditRecordDialog extends StatefulWidget {
  final ActivityRecordData? record; // null 表示创建新记录
  final Function()? onSaved; // 保存成功后的回调

  const EditRecordDialog({
    super.key,
    this.record,
    this.onSaved,
  });

  @override
  State<EditRecordDialog> createState() => _EditRecordDialogState();
}

class _EditRecordDialogState extends State<EditRecordDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late DateTime _startTime;
  late DateTime? _endTime;
  bool _isOngoing = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();

    if (widget.record != null) {
      // 编辑模式
      _nameController = TextEditingController(text: widget.record!.name);
      _startTime = widget.record!.startTime;
      _endTime = widget.record!.endTime;
      _isOngoing = _endTime == null;
    } else {
      // 创建模式
      _nameController = TextEditingController();
      _startTime = DateTime.now().subtract(const Duration(hours: 1));
      _endTime = DateTime.now();
      _isOngoing = false;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _selectDateTime(BuildContext context, bool isStartTime) async {
    final initialDate = isStartTime ? _startTime : (_endTime ?? DateTime.now());

    // 选择日期
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );

    if (date == null || !mounted) return;

    // 选择时间
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );

    if (time == null || !mounted) return;

    final newDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );

    setState(() {
      if (isStartTime) {
        _startTime = newDateTime;
        // 确保结束时间在开始时间之后
        if (_endTime != null && _endTime!.isBefore(_startTime)) {
          _endTime = _startTime.add(const Duration(minutes: 30));
        }
      } else {
        _endTime = newDateTime;
        // 确保结束时间在开始时间之后
        if (_endTime!.isBefore(_startTime)) {
          _endTime = _startTime.add(const Duration(minutes: 30));
        }
      }
    });
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
  }

  String _formatDuration(DateTime start, DateTime? end) {
    if (end == null) return 'Ongoing';

    final duration = end.difference(start);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // 验证时间逻辑
    if (!_isOngoing && _endTime != null && _endTime!.isBefore(_startTime)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final record = ActivityRecordData(
        id: widget.record?.id,
        name: _nameController.text.trim(),
        startTime: _startTime,
        endTime: _isOngoing ? null : _endTime,
        linkedTodoId: widget.record?.linkedTodoId,
        linkedTodoTitle: widget.record?.linkedTodoTitle,
      );

      if (widget.record != null) {
        // 更新现有记录
        await TimeLoggerStorage.updateRecord(widget.record!.id!, record);
      } else {
        // 创建新记录
        await TimeLoggerStorage.addRecord(record);
      }

      if (mounted) {
        Navigator.pop(context, true); // 返回 true 表示保存成功
        widget.onSaved?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditMode = widget.record != null;

    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题
                  Row(
                    children: [
                      Icon(
                        isEditMode ? Icons.edit : Icons.add,
                        color: Theme.of(context).primaryColor,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isEditMode ? 'Edit Activity' : 'New Activity',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 活动名称
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Activity Name',
                      hintText: 'Enter activity name',
                      prefixIcon: Icon(Icons.label),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter activity name';
                      }
                      return null;
                    },
                    autofocus: !isEditMode,
                  ),
                  const SizedBox(height: 20),

                  // 开始时间
                  _buildDateTimeField(
                    label: 'Start Time',
                    dateTime: _startTime,
                    onTap: () => _selectDateTime(context, true),
                  ),
                  const SizedBox(height: 16),

                  // 进行中开关
                  SwitchListTile(
                    title: const Text('Ongoing Activity'),
                    subtitle: const Text('Activity is still in progress'),
                    value: _isOngoing,
                    onChanged: (value) {
                      setState(() {
                        _isOngoing = value;
                        if (!value && _endTime == null) {
                          _endTime = DateTime.now();
                        }
                      });
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 8),

                  // 结束时间（只有在非进行中时显示）
                  if (!_isOngoing) ...[
                    _buildDateTimeField(
                      label: 'End Time',
                      dateTime: _endTime,
                      onTap: () => _selectDateTime(context, false),
                    ),
                    const SizedBox(height: 16),

                    // 显示时长
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.blue.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.timer, size: 20, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(
                            'Duration: ${_formatDuration(_startTime, _endTime)}',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // 按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed:
                            _isSaving ? null : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _isSaving ? null : _save,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Icon(Icons.save),
                        label: Text(_isSaving ? 'Saving...' : 'Save'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateTimeField({
    required String label,
    required DateTime? dateTime,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.access_time),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              dateTime != null ? _formatDateTime(dateTime) : 'Select',
              style: const TextStyle(fontSize: 16),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}
