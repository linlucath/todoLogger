import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/sync_history_service.dart';

/// 同步历史页面
class SyncHistoryPage extends StatefulWidget {
  final SyncHistoryService historyService;

  const SyncHistoryPage({
    Key? key,
    required this.historyService,
  }) : super(key: key);

  @override
  State<SyncHistoryPage> createState() => _SyncHistoryPageState();
}

class _SyncHistoryPageState extends State<SyncHistoryPage> {
  List<SyncHistoryRecord> _records = [];
  Map<String, dynamic>? _statistics;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final records = await widget.historyService.getAllRecords();
      final stats = await widget.historyService.getStatistics();

      setState(() {
        _records = records;
        _statistics = stats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('同步历史'),
        backgroundColor: const Color(0xFF6C63FF),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _showClearDialog,
            tooltip: '清除历史',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    if (_statistics != null) _buildStatisticsCard(),
                    Expanded(child: _buildHistoryList()),
                  ],
                ),
    );
  }

  /// 构建空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 80,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            '暂无同步历史',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建统计卡片
  Widget _buildStatisticsCard() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '同步统计',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  '总记录',
                  _statistics!['totalRecords'].toString(),
                  Icons.list,
                  Colors.blue,
                ),
                _buildStatItem(
                  '成功',
                  _statistics!['successCount'].toString(),
                  Icons.check_circle,
                  Colors.green,
                ),
                _buildStatItem(
                  '失败',
                  _statistics!['failureCount'].toString(),
                  Icons.error,
                  Colors.red,
                ),
                _buildStatItem(
                  '冲突',
                  _statistics!['totalConflicts'].toString(),
                  Icons.warning,
                  Colors.orange,
                ),
              ],
            ),
            if (_statistics!['lastSync'] != null) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.access_time, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    '最后同步: ${_formatDateTime(DateTime.parse(_statistics!['lastSync']))}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建统计项
  Widget _buildStatItem(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  /// 构建历史列表
  Widget _buildHistoryList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _records.length,
      itemBuilder: (context, index) {
        return _buildHistoryCard(_records[index]);
      },
    );
  }

  /// 构建历史卡片
  Widget _buildHistoryCard(SyncHistoryRecord record) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _getOperationIcon(record),
        title: Text(
          '${record.operationTypeText} ${record.dataTypeText}',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            if (record.deviceName != null) Text('设备: ${record.deviceName}'),
            if (record.itemCount > 0) Text('项目: ${record.itemCount}'),
            if (record.conflictCount > 0)
              Text(
                '冲突: ${record.conflictCount}',
                style: const TextStyle(color: Colors.orange),
              ),
            if (record.description != null)
              Text(
                record.description!,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            if (record.errorMessage != null)
              Text(
                '错误: ${record.errorMessage}',
                style: const TextStyle(color: Colors.red),
              ),
            const SizedBox(height: 4),
            Text(
              _formatDateTime(record.timestamp),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
        trailing: record.success
            ? const Icon(Icons.check_circle, color: Colors.green)
            : const Icon(Icons.error, color: Colors.red),
      ),
    );
  }

  /// 获取操作图标
  Widget _getOperationIcon(SyncHistoryRecord record) {
    IconData icon;
    Color color;

    switch (record.operationType) {
      case SyncOperationType.push:
        icon = Icons.cloud_upload;
        color = Colors.blue;
        break;
      case SyncOperationType.pull:
        icon = Icons.cloud_download;
        color = Colors.green;
        break;
      case SyncOperationType.conflict:
        icon = Icons.warning;
        color = Colors.orange;
        break;
      case SyncOperationType.merge:
        icon = Icons.merge_type;
        color = Colors.purple;
        break;
    }

    return Icon(icon, color: color);
  }

  /// 格式化日期时间
  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return '刚刚';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}小时前';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else {
      return DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
    }
  }

  /// 显示清除对话框
  void _showClearDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清除同步历史'),
        content: const Text('确定要清除所有同步历史记录吗?此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearHistory();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清除'),
          ),
        ],
      ),
    );
  }

  /// 清除历史
  Future<void> _clearHistory() async {
    try {
      await widget.historyService.clearAllRecords();
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('历史记录已清除')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('清除失败: $e')),
        );
      }
    }
  }
}
