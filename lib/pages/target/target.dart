import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class Target {
  String id;
  String title;
  String? description;
  int targetHours;
  int completedMinutes;
  DateTime startDate;
  DateTime endDate;
  String category;
  Color color;

  Target({
    required this.id,
    required this.title,
    this.description,
    required this.targetHours,
    this.completedMinutes = 0,
    required this.startDate,
    required this.endDate,
    this.category = 'General',
    required this.color,
  });

  double get progress => completedMinutes / (targetHours * 60);
  int get remainingMinutes => (targetHours * 60) - completedMinutes;
  int get daysRemaining => endDate.difference(DateTime.now()).inDays;
}

class TargetPage extends StatefulWidget {
  const TargetPage({super.key});

  @override
  State<TargetPage> createState() => _TargetPageState();
}

class _TargetPageState extends State<TargetPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<Target> _weeklyTargets = [];
  final List<Target> _monthlyTargets = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // 添加示例数据
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);

    _weeklyTargets.addAll([
      Target(
        id: '1',
        title: 'Study Flutter',
        description: '每周学习 Flutter 开发',
        targetHours: 20,
        completedMinutes: 720, // 12小时
        startDate: weekStart,
        endDate: weekEnd,
        category: 'Learning',
        color: const Color(0xFF6C63FF),
      ),
      Target(
        id: '2',
        title: 'Exercise',
        description: '每周运动时间',
        targetHours: 5,
        completedMinutes: 180, // 3小时
        startDate: weekStart,
        endDate: weekEnd,
        category: 'Health',
        color: const Color(0xFF4CAF50),
      ),
      Target(
        id: '3',
        title: 'Reading',
        description: '阅读技术书籍',
        targetHours: 10,
        completedMinutes: 360, // 6小时
        startDate: weekStart,
        endDate: weekEnd,
        category: 'Learning',
        color: const Color(0xFFFF9800),
      ),
    ]);

    _monthlyTargets.addAll([
      Target(
        id: '4',
        title: 'Project Development',
        description: '完成项目开发',
        targetHours: 80,
        completedMinutes: 3000, // 50小时
        startDate: monthStart,
        endDate: monthEnd,
        category: 'Work',
        color: const Color(0xFF2196F3),
      ),
      Target(
        id: '5',
        title: 'Learning Goals',
        description: '每月学习目标',
        targetHours: 60,
        completedMinutes: 2400, // 40小时
        startDate: monthStart,
        endDate: monthEnd,
        category: 'Learning',
        color: const Color(0xFF9C27B0),
      ),
    ]);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _addTarget(bool isWeekly) {
    showDialog(
      context: context,
      builder: (context) => AddTargetDialog(
        isWeekly: isWeekly,
        onAdd: (target) {
          setState(() {
            if (isWeekly) {
              _weeklyTargets.add(target);
            } else {
              _monthlyTargets.add(target);
            }
          });
        },
      ),
    );
  }

  void _editTarget(Target target, bool isWeekly) {
    showDialog(
      context: context,
      builder: (context) => AddTargetDialog(
        isWeekly: isWeekly,
        initialTarget: target,
        onAdd: (updatedTarget) {
          setState(() {
            target.title = updatedTarget.title;
            target.description = updatedTarget.description;
            target.targetHours = updatedTarget.targetHours;
            target.category = updatedTarget.category;
            target.color = updatedTarget.color;
          });
        },
      ),
    );
  }

  void _deleteTarget(String id, bool isWeekly) {
    setState(() {
      if (isWeekly) {
        _weeklyTargets.removeWhere((t) => t.id == id);
      } else {
        _monthlyTargets.removeWhere((t) => t.id == id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Targets'),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(text: 'Weekly'),
            Tab(text: 'Monthly'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTargetList(_weeklyTargets, true),
          _buildTargetList(_monthlyTargets, false),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addTarget(_tabController.index == 0),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildTargetList(List<Target> targets, bool isWeekly) {
    if (targets.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.flag_outlined,
              size: 80,
              color: Colors.grey[300],
            ),
            const SizedBox(height: 16),
            Text(
              'No ${isWeekly ? 'weekly' : 'monthly'} targets yet',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to add a new target',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[400],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: targets.length,
      itemBuilder: (context, index) {
        final target = targets[index];
        return TargetCard(
          target: target,
          onEdit: () => _editTarget(target, isWeekly),
          onDelete: () => _deleteTarget(target.id, isWeekly),
        );
      },
    );
  }
}

class TargetCard extends StatelessWidget {
  final Target target;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const TargetCard({
    super.key,
    required this.target,
    required this.onEdit,
    required this.onDelete,
  });

  String _formatMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours > 0) {
      return '${hours}h ${mins}m';
    } else {
      return '${mins}m';
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = target.progress.clamp(0.0, 1.0);
    final isCompleted = progress >= 1.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 40,
                    decoration: BoxDecoration(
                      color: target.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                target.title,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (isCompleted)
                              const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 24,
                              ),
                          ],
                        ),
                        if (target.description != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            target.description!,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  PopupMenuButton(
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 20),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      if (value == 'edit') {
                        onEdit();
                      } else if (value == 'delete') {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Delete Target'),
                            content: const Text(
                                'Are you sure you want to delete this target?'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  onDelete();
                                },
                                child: const Text('Delete',
                                    style: TextStyle(color: Colors.red)),
                              ),
                            ],
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // 进度条
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_formatMinutes(target.completedMinutes)} / ${target.targetHours}h',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: target.color,
                        ),
                      ),
                      Text(
                        '${(progress * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: target.color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: target.color.withOpacity(0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(target.color),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 底部信息
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    '${DateFormat('MMM dd').format(target.startDate)} - ${DateFormat('MMM dd').format(target.endDate)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const Spacer(),
                  if (!isCompleted) ...[
                    Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '${target.daysRemaining} days left',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AddTargetDialog extends StatefulWidget {
  final bool isWeekly;
  final Target? initialTarget;
  final Function(Target) onAdd;

  const AddTargetDialog({
    super.key,
    required this.isWeekly,
    this.initialTarget,
    required this.onAdd,
  });

  @override
  State<AddTargetDialog> createState() => _AddTargetDialogState();
}

class _AddTargetDialogState extends State<AddTargetDialog> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _hoursController;
  late String _selectedCategory;
  late Color _selectedColor;

  final List<String> _categories = [
    'General',
    'Work',
    'Health',
    'Learning',
    'Personal'
  ];
  final List<Color> _colors = [
    const Color(0xFF6C63FF),
    const Color(0xFF4CAF50),
    const Color(0xFFFF6584),
    const Color(0xFFFF9800),
    const Color(0xFF9C27B0),
    const Color(0xFF2196F3),
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initialTarget?.title);
    _descriptionController =
        TextEditingController(text: widget.initialTarget?.description);
    _hoursController = TextEditingController(
      text: widget.initialTarget?.targetHours.toString() ?? '10',
    );
    _selectedCategory = widget.initialTarget?.category ?? 'General';
    _selectedColor = widget.initialTarget?.color ?? _colors[0];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _hoursController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startDate = widget.isWeekly
        ? now.subtract(Duration(days: now.weekday - 1))
        : DateTime(now.year, now.month, 1);
    final endDate = widget.isWeekly
        ? startDate.add(const Duration(days: 6))
        : DateTime(now.year, now.month + 1, 0);

    return AlertDialog(
      title: Text(widget.initialTarget == null ? 'Add Target' : 'Edit Target'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (Optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _hoursController,
              decoration: const InputDecoration(
                labelText: 'Target Hours',
                border: OutlineInputBorder(),
                suffixText: 'hours',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: const InputDecoration(
                labelText: 'Category',
                border: OutlineInputBorder(),
              ),
              items: _categories.map((category) {
                return DropdownMenuItem(
                  value: category,
                  child: Text(category),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCategory = value!;
                });
              },
            ),
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Color', style: TextStyle(fontSize: 14)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _colors.map((color) {
                    final isSelected = color == _selectedColor;
                    return InkWell(
                      onTap: () {
                        setState(() {
                          _selectedColor = color;
                        });
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color:
                                isSelected ? Colors.black : Colors.transparent,
                            width: 3,
                          ),
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_titleController.text.isNotEmpty &&
                _hoursController.text.isNotEmpty) {
              final target = Target(
                id: widget.initialTarget?.id ?? DateTime.now().toString(),
                title: _titleController.text,
                description: _descriptionController.text.isEmpty
                    ? null
                    : _descriptionController.text,
                targetHours: int.parse(_hoursController.text),
                completedMinutes: widget.initialTarget?.completedMinutes ?? 0,
                startDate: widget.initialTarget?.startDate ?? startDate,
                endDate: widget.initialTarget?.endDate ?? endDate,
                category: _selectedCategory,
                color: _selectedColor,
              );
              widget.onAdd(target);
              Navigator.pop(context);
            }
          },
          child: Text(widget.initialTarget == null ? 'Add' : 'Save'),
        ),
      ],
    );
  }
}
