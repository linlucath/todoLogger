import 'package:flutter/material.dart';
import 'models.dart';
import 'target_storage.dart';
import 'target_calculator.dart' as target_calc;
import 'target_edit_dialog.dart';

/// Target 主页面
class TargetPage extends StatefulWidget {
  const TargetPage({super.key});

  @override
  State<TargetPage> createState() => _TargetPageState();
}

class _TargetPageState extends State<TargetPage> {
  final TargetStorage _storage = TargetStorage();
  final target_calc.TargetCalculator _calculator =
      target_calc.TargetCalculator();

  List<Target> _targets = [];
  Map<String, TargetProgress> _progressMap = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTargets();
  }

  /// 加载所有目标
  Future<void> _loadTargets() async {
    setState(() => _isLoading = true);

    try {
      final targets = await _storage.loadTargets();
      final progressList = await _calculator.calculateMultipleProgress(targets);

      // 构建进度映射
      final Map<String, TargetProgress> progressMap = {};
      for (final progress in progressList) {
        progressMap[progress.target.id] = progress;
      }

      setState(() {
        _targets = targets;
        _progressMap = progressMap;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 加载目标失败: $e');
      setState(() => _isLoading = false);
    }
  }

  /// 添加新目标
  Future<void> _addTarget() async {
    final result = await showDialog<Target>(
      context: context,
      builder: (context) => const TargetEditDialog(),
    );

    if (result != null) {
      await _storage.addTarget(result, _targets);
      await _loadTargets();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('目标 "${result.name}" 已添加')),
        );
      }
    }
  }

  /// 编辑目标
  Future<void> _editTarget(Target target) async {
    final result = await showDialog<Target>(
      context: context,
      builder: (context) => TargetEditDialog(target: target),
    );

    if (result != null) {
      await _storage.updateTarget(result, _targets);
      await _loadTargets();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('目标 "${result.name}" 已更新')),
        );
      }
    }
  }

  /// 删除目标
  Future<void> _deleteTarget(Target target) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除目标 "${target.name}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storage.deleteTarget(target.id, _targets);
      await _loadTargets();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('目标 "${target.name}" 已删除')),
        );
      }
    }
  }

  /// 切换目标启用状态
  Future<void> _toggleTargetActive(Target target) async {
    await _storage.toggleTargetActive(target.id, _targets);
    await _loadTargets();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('目标管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadTargets,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _targets.isEmpty
              ? _buildEmptyState()
              : _buildTargetList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTarget,
        tooltip: '添加目标',
        child: const Icon(Icons.add),
      ),
    );
  }

  /// 空状态提示
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.track_changes,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            '还没有目标',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右下角 + 按钮添加第一个目标',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  /// 目标列表
  Widget _buildTargetList() {
    // 按状态和类型分组
    final activeAchievements = _targets
        .where((t) => t.isActive && t.type == TargetType.achievement)
        .toList();
    final activeLimits = _targets
        .where((t) => t.isActive && t.type == TargetType.limit)
        .toList();
    final inactive = _targets.where((t) => !t.isActive).toList();

    return RefreshIndicator(
      onRefresh: _loadTargets,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (activeAchievements.isNotEmpty) ...[
            _buildSectionHeader('达成目标', Icons.check_circle_outline),
            ...activeAchievements.map((target) => _buildTargetCard(target)),
            const SizedBox(height: 16),
          ],
          if (activeLimits.isNotEmpty) ...[
            _buildSectionHeader('限制目标', Icons.warning_amber_outlined),
            ...activeLimits.map((target) => _buildTargetCard(target)),
            const SizedBox(height: 16),
          ],
          if (inactive.isNotEmpty) ...[
            _buildSectionHeader('已禁用', Icons.visibility_off),
            ...inactive.map((target) => _buildTargetCard(target)),
          ],
        ],
      ),
    );
  }

  /// 分组标题
  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[700]),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  /// 目标卡片
  Widget _buildTargetCard(Target target) {
    final progress = _progressMap[target.id];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _editTarget(target),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Row(
                children: [
                  // 颜色指示器
                  Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      color: target.color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 目标名称
                  Expanded(
                    child: Text(
                      target.name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: target.isActive ? Colors.black87 : Colors.grey,
                      ),
                    ),
                  ),
                  // 启用/禁用开关
                  Switch(
                    value: target.isActive,
                    onChanged: (_) => _toggleTargetActive(target),
                    activeColor: target.color,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 周期和目标信息
              Row(
                children: [
                  _buildInfoChip(
                    target.periodText,
                    Icons.calendar_today,
                    Colors.blue[100]!,
                    Colors.blue[700]!,
                  ),
                  const SizedBox(width: 8),
                  _buildInfoChip(
                    target.targetTimeText,
                    target.typeIcon,
                    target.type == TargetType.achievement
                        ? Colors.green[100]!
                        : Colors.orange[100]!,
                    target.type == TargetType.achievement
                        ? Colors.green[700]!
                        : Colors.orange[700]!,
                  ),
                ],
              ),

              // 关联的 TODO 数量
              if (target.linkedTodoIds.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.link, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '关联 ${target.linkedTodoIds.length} 个 TODO',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ],

              // 进度条和进度信息
              if (progress != null && target.isActive) ...[
                const SizedBox(height: 16),
                _buildProgressSection(progress),
              ],

              // 操作按钮
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _editTarget(target),
                    icon: const Icon(Icons.edit, size: 18),
                    label: const Text('编辑'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _deleteTarget(target),
                    icon: const Icon(Icons.delete, size: 18),
                    label: const Text('删除'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 信息标签
  Widget _buildInfoChip(
    String label,
    IconData icon,
    Color bgColor,
    Color textColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 进度区域
  Widget _buildProgressSection(TargetProgress progress) {
    final percentage = (progress.progressPercentage * 100).clamp(0, 100);
    final target = progress.target;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 进度条
        Stack(
          children: [
            // 背景
            Container(
              height: 8,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            // 进度
            FractionallySizedBox(
              widthFactor: (progress.progressPercentage).clamp(0.0, 1.0),
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  color: progress.progressColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 进度文本
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // 当前进度
            RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                children: [
                  TextSpan(
                    text: progress.currentTimeText,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: progress.progressColor,
                    ),
                  ),
                  TextSpan(text: ' / ${target.targetTimeText}'),
                ],
              ),
            ),

            // 百分比或剩余时间
            Text(
              target.type == TargetType.achievement
                  ? '${percentage.toStringAsFixed(0)}%'
                  : progress.remainingTimeText,
              style: TextStyle(
                fontSize: 13,
                color: progress.progressColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),

        // 周期信息
        const SizedBox(height: 4),
        Text(
          _calculator.formatPeriod(
            target_calc.DateTimeRange(
              start: progress.periodStart,
              end: progress.periodEnd,
            ),
            target.period,
          ),
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[500],
          ),
        ),
      ],
    );
  }
}
