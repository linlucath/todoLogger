import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/statistics_service.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  String _selectedPeriod = 'Week';
  final List<String> _periods = ['Day', 'Week', 'Month', 'Year'];

  StatisticsData? _statisticsData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStatistics();
  }

  /// 加载统计数据
  Future<void> _loadStatistics() async {
    setState(() => _isLoading = true);

    try {
      final data = await _getStatisticsForPeriod(_selectedPeriod);
      setState(() {
        _statisticsData = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load statistics: $e')),
        );
      }
    }
  }

  /// 根据时间段获取统计数据
  Future<StatisticsData> _getStatisticsForPeriod(String period) async {
    switch (period) {
      case 'Day':
        return StatisticsService.getTodayStatistics();
      case 'Week':
        return StatisticsService.getWeekStatistics();
      case 'Month':
        return StatisticsService.getMonthStatistics();
      case 'Year':
        return StatisticsService.getYearStatistics();
      default:
        return StatisticsService.getWeekStatistics();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: () {
              // TODO: 导出数据
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Export feature coming soon')),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _statisticsData == null || _statisticsData!.activityCount == 0
              ? _buildEmptyState()
              : _buildStatisticsContent(),
    );
  }

  /// 构建空状态
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.insert_chart_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No data available',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start logging activities to see statistics',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建统计内容
  Widget _buildStatisticsContent() {
    final data = _statisticsData!;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 时间范围选择
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  'Period:',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _periods.map((period) {
                        final isSelected = period == _selectedPeriod;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(period),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                _selectedPeriod = period;
                              });
                              _loadStatistics(); // 重新加载数据
                            },
                            selectedColor: Theme.of(context).primaryColor,
                            labelStyle: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 总计卡片
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text(
                          'Total Time',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${data.totalHours.toStringAsFixed(1)}h',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      width: 1,
                      height: 50,
                      color: Colors.grey[300],
                    ),
                    Column(
                      children: [
                        const Text(
                          'Activities',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${data.activityCount}',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF4CAF50),
                          ),
                        ),
                      ],
                    ),
                    Container(
                      width: 1,
                      height: 50,
                      color: Colors.grey[300],
                    ),
                    Column(
                      children: [
                        const Text(
                          'Avg/Day',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${data.avgHoursPerDay.toStringAsFixed(1)}h',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFF9800),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 饼图
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Time Distribution',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      height: 250,
                      child: PieChart(
                        PieChartData(
                          sections: data.activityStats.entries.map((entry) {
                            final stats = entry.value;
                            final percentage =
                                (stats.hours / data.totalHours * 100);
                            final color = Color(
                                StatisticsService.getColorForActivity(
                                    entry.key));

                            return PieChartSectionData(
                              value: stats.hours,
                              title: '${percentage.toStringAsFixed(0)}%',
                              color: color,
                              radius: 100,
                              titleStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            );
                          }).toList(),
                          sectionsSpace: 2,
                          centerSpaceRadius: 40,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 图例
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: data.activityStats.entries.map((entry) {
                final color =
                    Color(StatisticsService.getColorForActivity(entry.key));
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      entry.key,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 24),

          // 趋势图
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getTrendTitle(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      height: 200,
                      child: data.dailyStats.isEmpty
                          ? Center(
                              child: Text(
                                'No trend data available',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            )
                          : BarChart(
                              BarChartData(
                                alignment: BarChartAlignment.spaceAround,
                                maxY: _getMaxY(data.dailyStats),
                                barTouchData: BarTouchData(enabled: true),
                                titlesData: FlTitlesData(
                                  show: true,
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (value, meta) {
                                        return _getBottomTitle(
                                            value.toInt(), data.dailyStats);
                                      },
                                    ),
                                  ),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 30,
                                      getTitlesWidget: (value, meta) {
                                        return Text(
                                          '${value.toInt()}h',
                                          style: const TextStyle(fontSize: 10),
                                        );
                                      },
                                    ),
                                  ),
                                  topTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                  rightTitles: const AxisTitles(
                                    sideTitles: SideTitles(showTitles: false),
                                  ),
                                ),
                                gridData: FlGridData(
                                  show: true,
                                  drawVerticalLine: false,
                                  horizontalInterval:
                                      _getMaxY(data.dailyStats) / 4,
                                ),
                                borderData: FlBorderData(show: false),
                                barGroups: List.generate(
                                  data.dailyStats.length,
                                  (index) => BarChartGroupData(
                                    x: index,
                                    barRods: [
                                      BarChartRodData(
                                        toY: data.dailyStats[index].hours,
                                        color: Theme.of(context).primaryColor,
                                        width: 20,
                                        borderRadius:
                                            const BorderRadius.vertical(
                                          top: Radius.circular(4),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 详细数据列表
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Activity Details',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ..._buildActivityDetailsList(data),
              ],
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// 获取趋势图标题
  String _getTrendTitle() {
    switch (_selectedPeriod) {
      case 'Day':
        return 'Today\'s Activity';
      case 'Week':
        return 'Weekly Trend';
      case 'Month':
        return 'Monthly Trend';
      case 'Year':
        return 'Yearly Trend';
      default:
        return 'Trend';
    }
  }

  /// 构建活动详情列表
  List<Widget> _buildActivityDetailsList(StatisticsData data) {
    final sortedEntries = data.activityStats.entries.toList()
      ..sort((a, b) => b.value.hours.compareTo(a.value.hours));

    return sortedEntries.map((entry) {
      final stats = entry.value;
      final percentage = (stats.hours / data.totalHours * 100);
      final color = Color(StatisticsService.getColorForActivity(entry.key));

      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.access_time,
              color: color,
            ),
          ),
          title: Text(
            entry.key,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: LinearProgressIndicator(
            value: percentage / 100,
            backgroundColor: color.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${stats.hours.toStringAsFixed(1)}h',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${percentage.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  /// 获取Y轴最大值
  double _getMaxY(List<DailyStats> dailyStats) {
    if (dailyStats.isEmpty) return 10;
    final maxHours =
        dailyStats.map((s) => s.hours).reduce((a, b) => a > b ? a : b);
    // 向上取整到最近的5
    return ((maxHours / 5).ceil() * 5).toDouble().clamp(5, double.infinity);
  }

  /// 获取底部标签
  Widget _getBottomTitle(int index, List<DailyStats> dailyStats) {
    if (index < 0 || index >= dailyStats.length) {
      return const Text('');
    }

    final date = dailyStats[index].date;
    String label;

    switch (_selectedPeriod) {
      case 'Day':
        // 显示小时（如果有细分数据的话，目前按天统计所以显示日期）
        label = '${date.hour}:00';
        break;
      case 'Week':
        // 显示星期几
        const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        label = weekdays[date.weekday - 1];
        break;
      case 'Month':
        // 显示日期
        label = '${date.day}';
        break;
      case 'Year':
        // 显示月份
        const months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec'
        ];
        label = months[date.month - 1];
        break;
      default:
        label = '${date.day}';
    }

    return Text(
      label,
      style: const TextStyle(fontSize: 12),
    );
  }
}
