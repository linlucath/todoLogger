import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/time_logger_storage.dart';

class ActivityHistoryPage extends StatefulWidget {
  const ActivityHistoryPage({super.key});

  @override
  State<ActivityHistoryPage> createState() => _ActivityHistoryPageState();
}

class _ActivityHistoryPageState extends State<ActivityHistoryPage> {
  List<ActivityRecordData> _records = [];
  bool _isLoading = true;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    setState(() => _isLoading = true);
    final records = await TimeLoggerStorage.getAllRecords();

    if (mounted) {
      setState(() {
        _records = records;
        _isLoading = false;
      });
    }
  }

  List<ActivityRecordData> get _filteredRecords {
    if (_selectedDate == null) return _records;

    return _records.where((record) {
      final recordDate = DateTime(
        record.startTime.year,
        record.startTime.month,
        record.startTime.day,
      );
      final selectedDateOnly = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
      );
      return recordDate == selectedDateOnly;
    }).toList();
  }

  Map<String, List<ActivityRecordData>> get _groupedRecords {
    final Map<String, List<ActivityRecordData>> grouped = {};

    for (var record in _filteredRecords) {
      final dateKey = DateFormat('yyyy-MM-dd').format(record.startTime);
      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(record);
    }

    // 按日期降序排序
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Map.fromEntries(
      sortedKeys.map((key) => MapEntry(key, grouped[key]!)),
    );
  }

  String _formatDuration(int seconds, {bool showSeconds = false}) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      if (showSeconds && secs > 0) {
        return '${hours}h ${minutes}m ${secs}s';
      } else if (minutes > 0) {
        return '${hours}h ${minutes}m';
      } else {
        return '${hours}h';
      }
    } else if (minutes > 0) {
      if (showSeconds && secs > 0) {
        return '${minutes}m ${secs}s';
      } else {
        return '${minutes}m';
      }
    } else {
      return '${seconds}s';
    }
  }

  Map<String, int> _getDayStatistics(List<ActivityRecordData> records) {
    int totalActivities = records.length;
    int completedActivities = records.where((r) => r.endTime != null).length;
    int ongoingActivities = records.where((r) => r.endTime == null).length;
    int linkedToTodos = records.where((r) => r.linkedTodoId != null).length;

    return {
      'total': totalActivities,
      'completed': completedActivities,
      'ongoing': ongoingActivities,
      'linked': linkedToTodos,
    };
  }

  int _getTotalDuration(List<ActivityRecordData> records) {
    return records.fold(0, (sum, record) {
      if (record.endTime != null) {
        return sum + record.endTime!.difference(record.startTime).inSeconds;
      }
      return sum;
    });
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _clearDateFilter() {
    setState(() {
      _selectedDate = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity History'),
        actions: [
          if (_selectedDate != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearDateFilter,
              tooltip: 'Clear filter',
            ),
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: _pickDate,
            tooltip: 'Filter by date',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? _buildEmptyState()
              : _buildRecordsList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No activity records yet',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start tracking to see your history',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordsList() {
    final grouped = _groupedRecords;

    if (grouped.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No records for this date',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _clearDateFilter,
              child: const Text('Show all records'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: grouped.length,
      // 添加缓存范围以提高性能
      cacheExtent: 500,
      itemBuilder: (context, index) {
        final dateKey = grouped.keys.elementAt(index);
        final records = grouped[dateKey]!;
        final date = DateTime.parse(dateKey);
        final totalDuration = _getTotalDuration(records);

        return Card(
          key: ValueKey(dateKey), // 添加key以优化重建
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 日期头部
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat('EEEE').format(date),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                            Text(
                              DateFormat('MMMM dd, yyyy').format(date),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${records.length} activities',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            Text(
                              _formatDuration(totalDuration, showSeconds: true),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).primaryColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    // 统计信息
                    const SizedBox(height: 12),
                    _buildDayStatistics(records),
                  ],
                ),
              ),

              // 活动列表
              ...records.map((record) => _buildRecordItem(record)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecordItem(ActivityRecordData record) {
    final bool isOngoing = record.endTime == null;

    // 对于已完成的活动，计算实际持续时间
    // 对于正在进行的活动，为了避免频繁重建，使用固定的时间快照
    final duration = record.endTime != null
        ? record.endTime!.difference(record.startTime).inSeconds
        : 0; // 正在进行的活动不显示精确持续时间，避免性能问题, TODO

    // 使用唯一key来优化列表性能
    final itemKey = '${record.startTime.millisecondsSinceEpoch}_${record.name}';

    return Container(
      key: ValueKey(itemKey), // 添加key以优化重建
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(
          color: isOngoing
              ? Colors.amber.withOpacity(0.3)
              : Colors.grey.withOpacity(0.2),
          width: isOngoing ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
        color: isOngoing ? Colors.amber.withOpacity(0.05) : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        // 左边那个icon
        leading: CircleAvatar(
          backgroundColor: isOngoing
              ? Colors.amber.withOpacity(0.2)
              : Theme.of(context).primaryColor.withOpacity(0.1),
          child: Icon(
            isOngoing ? Icons.play_arrow : Icons.check,
            color:
                isOngoing ? Colors.amber[700] : Theme.of(context).primaryColor,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                record.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
            if (isOngoing)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'ONGOING',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            // 时间范围
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 14,
                  color: Colors.grey[600],
                ),
                const SizedBox(width: 4),
                Text(
                  '${DateFormat('h:mm a').format(record.startTime)} - ${record.endTime != null ? DateFormat('h:mm:ss a').format(record.endTime!) : 'ongoing'}',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            // 关联的待办事项（如果有）
            if (record.linkedTodoTitle != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(
                    Icons.link,
                    size: 14,
                    color: Colors.blue[700],
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      ' ${record.linkedTodoTitle!}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue[700],
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 4),
          ],
        ),
        // 右侧持续时间 / 进行中指示. 结构: evaluate isOngoing ? "Running" : duration
        trailing: isOngoing
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.amber[900]!,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Running',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber[900],
                      ),
                    ),
                  ],
                ),
              )
            : Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _formatDuration(duration, showSeconds: false),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildDayStatistics(List<ActivityRecordData> records) {
    final stats = _getDayStatistics(records);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem(
          icon: Icons.task_alt,
          label: 'Completed',
          value: '${stats['completed']}',
          color: Colors.green,
        ),
        _buildStatItem(
          icon: Icons.pending_actions,
          label: 'Ongoing',
          value: '${stats['ongoing']}',
          color: Colors.amber,
        ),
        _buildStatItem(
          icon: Icons.link,
          label: 'Linked',
          value: '${stats['linked']}',
          color: Colors.blue,
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }
}
