import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'package:intl/intl.dart';
import '../../services/storage/time_logger_storage.dart';
import '../../services/notification_service.dart';
import '../../services/sync/sync_service.dart';
import 'activity_history_page.dart';
import './next_activity_dialog.dart';
import './start_record_dialog.dart';
import './edit_activity_dialog.dart'; // 🆕 导入编辑对话框
import './notification_settings_dialog.dart'; // 🆕 导入通知设置对话框

/// 生成确定性的活动ID
/// 基于开始时间和活动名称生成，确保不同设备对同一活动生成相同ID
String _generateActivityId(DateTime startTime, String activityName) {
  // 使用时间戳（毫秒）+ 活动名称
  // 格式：timestamp_activityName
  final timestamp = startTime.millisecondsSinceEpoch;
  // 清理活动名称中的特殊字符，只保留字母数字和中文
  final cleanName = activityName.replaceAll(RegExp(r'[^\w\u4e00-\u9fa5]'), '_');
  return '${timestamp}_$cleanName';
}

// 记录数据类
class ActivityRecord {
  final String activityId; // 活动的唯一标识符
  String name; // 改为可变，支持编辑
  final DateTime startTime;
  DateTime? endTime;
  String? linkedTodoId;
  String? linkedTodoTitle;

  // 数据类构造函数
  ActivityRecord({
    String? activityId,
    required this.name,
    required this.startTime,
    this.endTime,
    this.linkedTodoId,
    this.linkedTodoTitle,
  }) : activityId = activityId ?? _generateActivityId(startTime, name);

  int get durationSeconds {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime).inSeconds;
  }
}

class TimeLoggerPage extends StatefulWidget {
  final SyncService? syncService; // 🆕 添加同步服务

  const TimeLoggerPage({super.key, this.syncService});

  @override
  State<TimeLoggerPage> createState() => _TimeLoggerPageState();
}

class _TimeLoggerPageState extends State<TimeLoggerPage> {
  Timer? _timer;
  bool _isRecording = false;
  // ignore: unused_field
  bool _isInBackground = false; // 标记应用是否在后台，预留用于未来功能

  // 当前活动
  ActivityRecord? _currentActivity;

  // 连续记录的开始时间
  DateTime? _continuousStartTime;

  // 所有记录的活动历史
  final List<ActivityRecord> _allRecords = [];

  // 用户使用过的活动名称（用于快速选择）
  final Set<String> _activityHistory = {};

  // 🆕 同步数据更新监听
  StreamSubscription? _dataUpdateSubscription;

  // 当前活动的经过秒数（基于实际时间计算）
  int get _currentActivitySeconds {
    if (_currentActivity == null) return 0;
    return DateTime.now().difference(_currentActivity!.startTime).inSeconds;
  }

  @override
  void initState() {
    super.initState();
    _loadSavedData();
    _setupSyncListener(); // 🆕 设置同步监听
  }

  // 🆕 设置同步服务监听
  void _setupSyncListener() {
    if (widget.syncService != null) {
      print('🔔 [TimeLogger] 设置同步数据更新监听');
      _dataUpdateSubscription =
          widget.syncService!.dataUpdatedStream.listen((event) {
        // 当接收到时间日志更新时，重新加载当前活动
        if (event.dataType == 'timeLogs') {
          print('🔄 [TimeLogger] 收到时间日志更新通知，重新加载数据');
          _reloadCurrentActivity();
        }
      });
    }
  }

  // 🆕 重新加载当前活动（同步后调用）
  Future<void> _reloadCurrentActivity() async {
    print('📂 [TimeLogger] 重新加载当前活动...');

    try {
      final currentActivity = await TimeLoggerStorage.getCurrentActivity();

      print('📂 [TimeLogger] 从存储加载的活动: ${currentActivity?.name ?? "null"}');
      if (currentActivity != null) {
        print('   - activityId: ${currentActivity.activityId}');
        print('   - 开始时间: ${currentActivity.startTime}');
        print('   - linkedTodoId: ${currentActivity.linkedTodoId}');
      }
      print('📂 [TimeLogger] 当前UI显示的活动: ${_currentActivity?.name ?? "null"}');
      if (_currentActivity != null) {
        print('   - activityId: ${_currentActivity!.activityId}');
        print('   - 开始时间: ${_currentActivity!.startTime}');
      }

      if (!mounted) {
        print('⚠️  [TimeLogger] 组件已卸载，跳过更新');
        return;
      }

      setState(() {
        if (currentActivity != null) {
          // 检查是否需要更新当前活动（比较 activityId 和开始时间）
          final needsUpdate = _currentActivity == null ||
              _currentActivity!.activityId != currentActivity.activityId ||
              _currentActivity!.startTime != currentActivity.startTime ||
              _currentActivity!.name != currentActivity.name;

          if (needsUpdate) {
            print('🔄 [TimeLogger] 更新当前活动: ${currentActivity.name}');
            print('   开始时间: ${currentActivity.startTime}');
            print('   activityId: ${currentActivity.activityId}');

            // 停止旧的计时器
            _timer?.cancel();

            _currentActivity = ActivityRecord(
              activityId: currentActivity.activityId,
              name: currentActivity.name,
              startTime: currentActivity.startTime,
              endTime: currentActivity.endTime,
              linkedTodoId: currentActivity.linkedTodoId,
              linkedTodoTitle: currentActivity.linkedTodoTitle,
            );
            _isRecording = true;

            // 启动新的计时器
            _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
              if (mounted) {
                setState(() {});
              }
            });

            print('✅ [TimeLogger] 活动更新完成，计时器已启动');
            print('   当前显示: ${_currentActivity!.name}');
            print('   _isRecording: $_isRecording');
          } else {
            print('✅ [TimeLogger] 活动相同，无需更新');
          }
        } else {
          // 当前活动被清除（可能被远程设备结束）
          if (_currentActivity != null) {
            print('⏹️  [TimeLogger] 当前活动已被结束，停止计时');
            _timer?.cancel();
            _currentActivity = null;
            _isRecording = false;
            print('✅ [TimeLogger] 已停止计时并清除活动');
          } else {
            print('✅ [TimeLogger] 当前无活动，保持空闲状态');
          }
        }
      });

      print('✅ [TimeLogger] 重新加载完成，_isRecording: $_isRecording');
    } catch (e) {
      print('❌ [TimeLogger] 重新加载当前活动失败: $e');
    }
  }

  // 加载保存的数据
  Future<void> _loadSavedData() async {
    final currentActivity = await TimeLoggerStorage.getCurrentActivity();
    final continuousStart = await TimeLoggerStorage.getContinuousStartTime();
    final activityHistory = await TimeLoggerStorage.getActivityHistory();

    if (mounted) {
      setState(() {
        if (currentActivity != null) {
          _currentActivity = ActivityRecord(
            activityId: currentActivity.activityId,
            name: currentActivity.name,
            startTime: currentActivity.startTime,
            endTime: currentActivity.endTime,
            linkedTodoId: currentActivity.linkedTodoId,
            linkedTodoTitle: currentActivity.linkedTodoTitle,
          );
          _isRecording = true;

          // 恢复计时器
          _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
            setState(() {});
          });
        }

        _continuousStartTime = continuousStart;
        _activityHistory.addAll(activityHistory);

        // _allRecords 不需要恢复历史记录
        // 它只用于临时存储本次会话中完成的记录
      });
    }
  }

  // 保存当前状态
  Future<void> _saveCurrentState() async {
    // 保存当前活动状态
    if (_currentActivity != null) {
      await TimeLoggerStorage.saveCurrentActivity(ActivityRecordData(
        activityId: _currentActivity!.activityId,
        name: _currentActivity!.name,
        startTime: _currentActivity!.startTime,
        endTime: _currentActivity!.endTime,
        linkedTodoId: _currentActivity!.linkedTodoId,
        linkedTodoTitle: _currentActivity!.linkedTodoTitle,
      ));
    } else {
      await TimeLoggerStorage.saveCurrentActivity(null);
    }

    // 保存连续记录开始时间
    await TimeLoggerStorage.saveContinuousStartTime(_continuousStartTime);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dataUpdateSubscription?.cancel(); // 🆕 取消同步监听
    // 清理通知
    if (Platform.isAndroid || Platform.isIOS) {
      NotificationService().stopBackgroundNotifications();
    }
    super.dispose();
  }

  // 应用进入后台时调用
  void onAppPaused() {
    if (!mounted) return;

    // 只在移动端且正在计时时启动后台通知
    if ((Platform.isAndroid || Platform.isIOS) &&
        _isRecording &&
        _currentActivity != null) {
      _isInBackground = true;
      NotificationService().startBackgroundNotifications(
        _currentActivity!.name,
        startTime: _currentActivity!.startTime, // 🆕 传递开始时间
      );
    }
  }

  // 应用回到前台时调用
  void onAppResumed() {
    if (!mounted) return;

    // 停止后台通知并取消所有通知
    if (Platform.isAndroid || Platform.isIOS) {
      _isInBackground = false;
      NotificationService().stopBackgroundNotifications();
      NotificationService().cancelAllNotifications();
    }
  }

  void _startRecording(String activityName,
      {String? todoId, String? todoTitle}) {
    final now = DateTime.now();
    final activityId = _generateActivityId(now, activityName); // 基于时间和名称生成确定性ID

    setState(() {
      _currentActivity = ActivityRecord(
        activityId: activityId,
        name: activityName,
        startTime: now,
        linkedTodoId: todoId,
        linkedTodoTitle: todoTitle,
      );
      _isRecording = true;

      // 如果是第一次开始记录，设置连续记录开始时间
      _continuousStartTime ??= now;

      _activityHistory.add(activityName);
    });

    // 保存状态
    _saveCurrentState();

    // 广播计时开始（使用稳定的activityId）
    if (widget.syncService != null) {
      widget.syncService!.broadcastTimerStart(
        activityId,
        activityName,
        now,
        todoId,
        todoTitle,
      );
    }

    // 每秒更新界面（各设备根据收到的开始时间独立计时）
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_currentActivity != null) {
        setState(() {
          // 通过 getter 计算实际时间差
        });
      }
    });
  }

  void _finishAndStartNext() async {
    if (_currentActivity == null) return;

    // 暂停计时器
    _timer?.cancel();

    final endedActivity = _currentActivity!;

    // 结束当前活动
    setState(() {
      _currentActivity!.endTime = DateTime.now();
      _allRecords.add(_currentActivity!);
    });

    // 立即保存已完成的活动记录到数据库
    await TimeLoggerStorage.addRecord(ActivityRecordData(
      activityId: _currentActivity!.activityId,
      name: _currentActivity!.name,
      startTime: _currentActivity!.startTime,
      endTime: _currentActivity!.endTime,
      linkedTodoId: _currentActivity!.linkedTodoId,
      linkedTodoTitle: _currentActivity!.linkedTodoTitle,
    ));

    // 广播计时停止（使用稳定的activityId）
    if (widget.syncService != null && endedActivity.endTime != null) {
      final duration =
          endedActivity.endTime!.difference(endedActivity.startTime).inSeconds;
      widget.syncService!.broadcastTimerStop(
        endedActivity.activityId,
        endedActivity.startTime,
        endedActivity.endTime!,
        duration,
      );
    }

    // 弹出对话框：接下来做什么
    final result = await _showNextActivityDialog();

    if (result != null) {
      // 开始新活动
      _startRecording(
        result['name'] as String,
        todoId: result['todoId'] as String?,
        todoTitle: result['todoTitle'] as String?,
      );
    } else {
      // 用户取消，停止记录
      setState(() {
        _isRecording = false;
        _currentActivity = null;
        _continuousStartTime = null;
      });

      // 保存停止状态
      await _saveCurrentState();
    }
  }

  Future<Map<String, dynamic>?> _showNextActivityDialog() async {
    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return NextActivityDialog(
          activityHistory: _activityHistory.toList(),
        );
      },
    );
  }

  // 🆕 根据最近两天的使用频率获取活动历史
  Future<List<String>> _getFrequentActivities() async {
    // 获取最近两天的所有活动记录
    final recentRecords = await TimeLoggerStorage.getRecentRecords(7);

    // 统计每个活动的使用频率
    final Map<String, int> frequencyMap = {};
    for (var record in recentRecords) {
      frequencyMap[record.name] = (frequencyMap[record.name] ?? 0) + 1;
    }

    // 也包含当前会话中使用过的活动
    for (var activityName in _activityHistory) {
      frequencyMap[activityName] = (frequencyMap[activityName] ?? 0) + 1;
    }

    // 按频率排序（频率高的在前）
    final sortedActivities = frequencyMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // 返回活动名称列表
    return sortedActivities.map((e) => e.key).toList();
  }

  void _showStartActivityDialog() async {
    final frequentActivities = await _getFrequentActivities();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (BuildContext context) {
        return StartActivityDialog(
          activityHistory: frequentActivities,
        );
      },
    );

    if (result != null) {
      _startRecording(
        result['name'] as String,
        todoId: result['todoId'] as String?,
        todoTitle: result['todoTitle'] as String?,
      );
    }
  }

  // 🆕 编辑当前活动名称
  void _editCurrentActivityName() async {
    if (_currentActivity == null) return;

    final frequentActivities = await _getFrequentActivities();

    final result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return EditActivityDialog(
          currentName: _currentActivity!.name,
          activityHistory: frequentActivities,
        );
      },
    );

    if (result != null && result != _currentActivity!.name) {
      setState(() {
        _currentActivity!.name = result;
        // 将新名称添加到历史记录
        _activityHistory.add(result);
      });

      // 保存修改后的状态
      await _saveCurrentState();

      // 更新后台通知（如果正在后台）
      if ((Platform.isAndroid || Platform.isIOS) &&
          _isRecording &&
          _isInBackground) {
        NotificationService().startBackgroundNotifications(
          _currentActivity!.name,
          startTime: _currentActivity!.startTime,
        );
      }

      // 显示提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Activity renamed to "$result"'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  int get _continuousTotalSeconds {
    if (_continuousStartTime == null) return 0;
    return DateTime.now().difference(_continuousStartTime!).inSeconds;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Time Logger'),
        actions: [
          // 🆕 通知设置按钮（仅移动端显示）
          if (Platform.isAndroid || Platform.isIOS)
            IconButton(
              icon: const Icon(Icons.notifications_outlined),
              tooltip: '通知设置',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const NotificationSettingsDialog(),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '历史记录',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const ActivityHistoryPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: _isRecording ? _buildRecordingView() : _buildIdleView(),
    );
  }

  // 未开始记录的视图
  Widget _buildIdleView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 24),
          Text(
            'Ready to start?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Begin tracking your activities',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: _showStartActivityDialog,
            icon: const Icon(Icons.play_arrow, size: 28),
            label: const Text(
              'Start Recording',
              style: TextStyle(fontSize: 18),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 32,
                vertical: 16,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 记录中的视图
  Widget _buildRecordingView() {
    return Column(
      children: [
        // 连续记录时间卡片
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).primaryColor,
                Theme.of(context).primaryColor.withValues(alpha: 0.8),
              ],
            ),
          ),
          child: Column(
            children: [
              const Text(
                '🎯 Continuous Tracking',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (_continuousStartTime != null)
                Text(
                  'Started at ${DateFormat('h:mm a').format(_continuousStartTime!)}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                _formatTime(_continuousTotalSeconds),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.bold,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '✨ Keep going!',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),

        // 当前活动卡片
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 活动名称
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).primaryColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 12,
                          color: Theme.of(context).primaryColor,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _currentActivity?.name ?? '',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 🆕 编辑按钮
                        InkWell(
                          onTap: _editCurrentActivityName,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.edit,
                              size: 18,
                              color: Theme.of(context)
                                  .primaryColor
                                  .withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 当前活动时长
                  Text(
                    _formatTime(_currentActivitySeconds),
                    style: TextStyle(
                      fontSize: 56,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 关联的TODO
                  if (_currentActivity?.linkedTodoTitle != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.check_box_outlined,
                            size: 16,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _currentActivity!.linkedTodoTitle!,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.amber,
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 40),

                  // 提示文字
                  Text(
                    '👉 Finish this to start next',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 结束并开始下一个按钮
                  ElevatedButton.icon(
                    onPressed: _finishAndStartNext,
                    icon: const Icon(Icons.skip_next, size: 24),
                    label: const Text(
                      'Finish & Start Next',
                      style: TextStyle(fontSize: 16),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
