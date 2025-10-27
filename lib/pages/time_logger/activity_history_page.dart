import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/time_logger_storage_v2.dart';
import '../../services/time_logger_storage.dart';

/// 优化版活动历史页面 - 支持分页和懒加载
class ActivityHistoryPage extends StatefulWidget {
  const ActivityHistoryPage({super.key});

  @override
  State<ActivityHistoryPage> createState() => _ActivityHistoryPageState();
}

class _ActivityHistoryPageState extends State<ActivityHistoryPage> {
  List<ActivityRecordData> _records = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  DateTime? _selectedDate;

  // 分页相关
  int _currentPage = 0;
  static const int _pageSize = 30;
  bool _hasMore = true;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadInitialRecords();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 监听滚动,实现无限加载
  void _onScroll() {
    if (_isLoadingMore || !_hasMore) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    // 滚动到底部前 200px 时加载更多
    if (currentScroll >= maxScroll - 200) {
      _loadMoreRecords();
    }
  }

  /// 首次加载 - 只加载最近 30 天
  Future<void> _loadInitialRecords() async {
    setState(() => _isLoading = true);

    try {
      // 优化: 首次只加载最近 30 天的数据
      final records = await TimeLoggerStorageV2.getRecentRecords(30);

      if (mounted) {
        setState(() {
          _records = records;
          _isLoading = false;
          _hasMore = records.length >= _pageSize;
        });
      }
    } catch (e) {
      print('加载记录失败: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 加载更多记录 (分页)
  Future<void> _loadMoreRecords() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);

    try {
      _currentPage++;
      final newRecords = await TimeLoggerStorageV2.getPagedRecords(
        page: _currentPage,
        pageSize: _pageSize,
      );

      if (mounted) {
        setState(() {
          _records.addAll(newRecords);
          _isLoadingMore = false;
          _hasMore = newRecords.length >= _pageSize;
        });
      }
    } catch (e) {
      print('加载更多失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingMore = false;
          _currentPage--; // 回退页码
        });
      }
    }
  }

  /// 下拉刷新
  Future<void> _refreshRecords() async {
    _currentPage = 0;
    _hasMore = true;
    TimeLoggerStorageV2.clearCache();
    await _loadInitialRecords();
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
          : RefreshIndicator(
              onRefresh: _refreshRecords,
              child:
                  _records.isEmpty ? _buildEmptyState() : _buildRecordsList(),
            ),
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
            color: Colors.grey[300],
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
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecordsList() {
    final grouped = _groupedRecords;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: grouped.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        // 加载更多指示器
        if (index == grouped.length) {
          return _buildLoadingMoreIndicator();
        }

        final dateKey = grouped.keys.elementAt(index);
        final dayRecords = grouped[dateKey]!;

        return _buildDaySection(dateKey, dayRecords);
      },
    );
  }

  Widget _buildLoadingMoreIndicator() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: _isLoadingMore
            ? const CircularProgressIndicator()
            : TextButton(
                onPressed: _loadMoreRecords,
                child: const Text('Load More'),
              ),
      ),
    );
  }

  Widget _buildDaySection(String dateKey, List<ActivityRecordData> records) {
    final date = DateTime.parse(dateKey);
    final totalDuration = _getTotalDuration(records);
    final isToday = DateFormat('yyyy-MM-dd').format(DateTime.now()) == dateKey;
    final isYesterday = DateFormat('yyyy-MM-dd')
            .format(DateTime.now().subtract(const Duration(days: 1))) ==
        dateKey;

    String dateLabel;
    if (isToday) {
      dateLabel = 'Today';
    } else if (isYesterday) {
      dateLabel = 'Yesterday';
    } else {
      dateLabel = DateFormat('EEEE, MMM d').format(date);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 日期标题栏
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  dateLabel,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      Icons.timer,
                      size: 16,
                      color: Colors.grey[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDuration(totalDuration),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${records.length}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 活动记录列表
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: records.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              return _buildRecordItem(records[index]);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRecordItem(ActivityRecordData record) {
    final duration = record.endTime != null
        ? record.endTime!.difference(record.startTime).inSeconds
        : 0;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: record.endTime != null
            ? Colors.green.withValues(alpha: 0.2)
            : Colors.orange.withValues(alpha: 0.2),
        child: Icon(
          record.endTime != null ? Icons.check : Icons.play_arrow,
          color: record.endTime != null ? Colors.green : Colors.orange,
        ),
      ),
      title: Text(
        record.name,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                '${DateFormat('HH:mm').format(record.startTime)} - ${record.endTime != null ? DateFormat('HH:mm').format(record.endTime!) : 'Ongoing'}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          if (record.linkedTodoTitle != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.link, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    record.linkedTodoTitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      trailing: record.endTime != null
          ? Text(
              _formatDuration(duration),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.green,
              ),
            )
          : const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
    );
  }
}
