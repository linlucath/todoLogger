import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';

class ActivityCategory {
  final String id;
  final String name;
  final IconData icon;
  final Color color;
  int todaySeconds;

  ActivityCategory({
    required this.id,
    required this.name,
    required this.icon,
    required this.color,
    this.todaySeconds = 0,
  });
}

class TimeEntry {
  final String id;
  final String activityId;
  final DateTime startTime;
  DateTime? endTime;
  int durationSeconds;

  TimeEntry({
    required this.id,
    required this.activityId,
    required this.startTime,
    this.endTime,
    this.durationSeconds = 0,
  });
}

class TimeLoggerPage extends StatefulWidget {
  const TimeLoggerPage({super.key});

  @override
  State<TimeLoggerPage> createState() => _TimeLoggerPageState();
}

class _TimeLoggerPageState extends State<TimeLoggerPage> {
  Timer? _timer;
  int _elapsedSeconds = 0;
  bool _isRunning = false;
  String? _currentActivityId;
  DateTime? _startTime;

  final List<ActivityCategory> _activities = [
    ActivityCategory(
      id: '1',
      name: 'Work',
      icon: Icons.work,
      color: const Color(0xFF6C63FF),
      todaySeconds: 7200, // 2小时
    ),
    ActivityCategory(
      id: '2',
      name: 'Study',
      icon: Icons.school,
      color: const Color(0xFF4CAF50),
      todaySeconds: 5400, // 1.5小时
    ),
    ActivityCategory(
      id: '3',
      name: 'Exercise',
      icon: Icons.fitness_center,
      color: const Color(0xFFFF6584),
      todaySeconds: 1800, // 30分钟
    ),
    ActivityCategory(
      id: '4',
      name: 'Reading',
      icon: Icons.menu_book,
      color: const Color(0xFFFF9800),
      todaySeconds: 3600, // 1小时
    ),
    ActivityCategory(
      id: '5',
      name: 'Entertainment',
      icon: Icons.movie,
      color: const Color(0xFF9C27B0),
      todaySeconds: 2700, // 45分钟
    ),
    ActivityCategory(
      id: '6',
      name: 'Sleep',
      icon: Icons.bed,
      color: const Color(0xFF607D8B),
      todaySeconds: 28800, // 8小时
    ),
  ];

  final List<TimeEntry> _todayEntries = [];

  @override
  void initState() {
    super.initState();
    // 添加一些示例数据
    _todayEntries.addAll([
      TimeEntry(
        id: '1',
        activityId: '1',
        startTime: DateTime.now().subtract(const Duration(hours: 2)),
        endTime: DateTime.now().subtract(const Duration(hours: 1)),
        durationSeconds: 3600,
      ),
      TimeEntry(
        id: '2',
        activityId: '2',
        startTime: DateTime.now().subtract(const Duration(hours: 1)),
        endTime: DateTime.now().subtract(const Duration(minutes: 30)),
        durationSeconds: 1800,
      ),
    ]);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer(String activityId) {
    setState(() {
      _isRunning = true;
      _currentActivityId = activityId;
      _startTime = DateTime.now();
      _elapsedSeconds = 0;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedSeconds++;
      });
    });
  }

  void _pauseTimer() {
    setState(() {
      _isRunning = false;
    });
    _timer?.cancel();
  }

  void _stopTimer() {
    if (_currentActivityId != null && _startTime != null) {
      // 保存记录
      final entry = TimeEntry(
        id: DateTime.now().toString(),
        activityId: _currentActivityId!,
        startTime: _startTime!,
        endTime: DateTime.now(),
        durationSeconds: _elapsedSeconds,
      );

      setState(() {
        _todayEntries.add(entry);
        // 更新活动的今日总时长
        final activity =
            _activities.firstWhere((a) => a.id == _currentActivityId);
        activity.todaySeconds += _elapsedSeconds;

        _isRunning = false;
        _currentActivityId = null;
        _startTime = null;
        _elapsedSeconds = 0;
      });
      _timer?.cancel();
    }
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${secs}s';
    } else {
      return '${secs}s';
    }
  }

  String _formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  int get _totalTodaySeconds {
    return _activities.fold(0, (sum, activity) => sum + activity.todaySeconds);
  }

  @override
  Widget build(BuildContext context) {
    final currentActivity = _currentActivityId != null
        ? _activities.firstWhere((a) => a.id == _currentActivityId)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Time Logger'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              // TODO: 显示历史记录
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 今日总计时间卡片
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor,
                  Theme.of(context).primaryColor.withOpacity(0.8),
                ],
              ),
            ),
            child: Column(
              children: [
                Text(
                  DateFormat('EEEE, MMMM dd').format(DateTime.now()),
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Today\'s Total',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatDuration(_totalTodaySeconds),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // 当前活动的大型计时器
          if (_isRunning && currentActivity != null)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: currentActivity.color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: currentActivity.color.withOpacity(0.3),
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        currentActivity.icon,
                        color: currentActivity.color,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        currentActivity.name,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: currentActivity.color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _formatTime(_elapsedSeconds),
                    style: TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: currentActivity.color,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _pauseTimer,
                        icon: const Icon(Icons.pause),
                        label: const Text('Pause'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: _stopTimer,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
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

          // 活动分类网格
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Activities',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 1.3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: _activities.length,
                      itemBuilder: (context, index) {
                        final activity = _activities[index];
                        final isActive = _currentActivityId == activity.id;

                        return InkWell(
                          onTap: () {
                            if (!_isRunning) {
                              _startTimer(activity.id);
                            } else if (isActive) {
                              _pauseTimer();
                            } else {
                              // 切换到新活动
                              _stopTimer();
                              _startTimer(activity.id);
                            }
                          },
                          child: Card(
                            elevation: isActive ? 8 : 2,
                            color: isActive
                                ? activity.color.withOpacity(0.2)
                                : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: isActive
                                    ? activity.color
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    activity.icon,
                                    size: 32,
                                    color: activity.color,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    activity.name,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: isActive
                                          ? activity.color
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatDuration(activity.todaySeconds),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  if (isActive && _isRunning)
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: activity.color,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'Running',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
