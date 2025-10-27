import 'package:flutter/material.dart';
import 'dart:async';

class PomodoroSession {
  final DateTime startTime;
  final DateTime? endTime;
  final int durationMinutes;
  final bool isBreak;

  PomodoroSession({
    required this.startTime,
    this.endTime,
    required this.durationMinutes,
    this.isBreak = false,
  });
}

class ImmersiveWorkPage extends StatefulWidget {
  const ImmersiveWorkPage({super.key});

  @override
  State<ImmersiveWorkPage> createState() => _ImmersiveWorkPageState();
}

class _ImmersiveWorkPageState extends State<ImmersiveWorkPage>
    with TickerProviderStateMixin {
  Timer? _timer;
  int _remainingSeconds = 25 * 60; // 默认25分钟
  bool _isRunning = false;
  bool _isBreak = false;
  int _completedPomodoros = 0;

  final List<PomodoroSession> _todaySessions = [];

  // 番茄钟设置
  int _workMinutes = 25;
  int _shortBreakMinutes = 5;
  int _longBreakMinutes = 15;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  void _startTimer() {
    setState(() {
      _isRunning = true;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          _onTimerComplete();
        }
      });
    });
  }

  void _pauseTimer() {
    setState(() {
      _isRunning = false;
    });
    _timer?.cancel();
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _remainingSeconds = _isBreak
          ? (_completedPomodoros % 4 == 0
                  ? _longBreakMinutes
                  : _shortBreakMinutes) *
              60
          : _workMinutes * 60;
    });
  }

  void _onTimerComplete() {
    _timer?.cancel();

    // 保存会话
    _todaySessions.add(PomodoroSession(
      startTime: DateTime.now().subtract(Duration(
        minutes: _isBreak
            ? (_completedPomodoros % 4 == 0
                ? _longBreakMinutes
                : _shortBreakMinutes)
            : _workMinutes,
      )),
      endTime: DateTime.now(),
      durationMinutes: _isBreak
          ? (_completedPomodoros % 4 == 0
              ? _longBreakMinutes
              : _shortBreakMinutes)
          : _workMinutes,
      isBreak: _isBreak,
    ));

    setState(() {
      _isRunning = false;

      if (!_isBreak) {
        _completedPomodoros++;
        // 切换到休息时间
        _isBreak = true;
        _remainingSeconds = (_completedPomodoros % 4 == 0
                ? _longBreakMinutes
                : _shortBreakMinutes) *
            60;
      } else {
        // 切换到工作时间
        _isBreak = false;
        _remainingSeconds = _workMinutes * 60;
      }
    });

    // 显示完成提示
    _showCompletionDialog();
  }

  void _showCompletionDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title:
            Text(_isBreak ? '🎉 Work Session Complete!' : '☕ Break Time Over!'),
        content: Text(
          _isBreak
              ? 'Great job! Time for a ${_completedPomodoros % 4 == 0 ? 'long' : 'short'} break.'
              : 'Break is over. Ready to focus again?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('OK'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _startTimer();
            },
            child: const Text('Start Now'),
          ),
        ],
      ),
    );
  }

  void _showSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pomodoro Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildTimeSetting('Work Duration', _workMinutes, (value) {
              setState(() {
                _workMinutes = value;
                if (!_isBreak && !_isRunning) {
                  _remainingSeconds = _workMinutes * 60;
                }
              });
            }),
            const SizedBox(height: 16),
            _buildTimeSetting('Short Break', _shortBreakMinutes, (value) {
              setState(() {
                _shortBreakMinutes = value;
              });
            }),
            const SizedBox(height: 16),
            _buildTimeSetting('Long Break', _longBreakMinutes, (value) {
              setState(() {
                _longBreakMinutes = value;
              });
            }),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeSetting(String label, int minutes, Function(int) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove),
              onPressed: minutes > 1 ? () => onChanged(minutes - 1) : null,
            ),
            SizedBox(
              width: 40,
              child: Text(
                '$minutes',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: minutes < 60 ? () => onChanged(minutes + 1) : null,
            ),
          ],
        ),
      ],
    );
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final progress = 1 -
        (_remainingSeconds /
            ((_isBreak
                    ? (_completedPomodoros % 4 == 0
                        ? _longBreakMinutes
                        : _shortBreakMinutes)
                    : _workMinutes) *
                60));

    return Scaffold(
      backgroundColor:
          _isBreak ? const Color(0xFF4CAF50) : const Color(0xFF6C63FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(_isBreak ? 'Break Time' : 'Focus Mode'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 番茄钟计数器
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (index) {
                  final isCompleted = index < _completedPomodoros % 4;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCompleted
                          ? Colors.white
                          : Colors.white.withOpacity(0.3),
                    ),
                    child: Center(
                      child: Opacity(
                        opacity: isCompleted ? 1.0 : 0.3,
                        child: const Text(
                          '🍅',
                          style: TextStyle(fontSize: 20),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),

            const Spacer(),

            // 大型计时器
            AnimatedBuilder(
              animation: _isRunning
                  ? _pulseAnimation
                  : const AlwaysStoppedAnimation(1.0),
              builder: (context, child) {
                return Transform.scale(
                  scale: _isRunning ? _pulseAnimation.value : 1.0,
                  child: child,
                );
              },
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.2),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 260,
                      height: 260,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 12,
                        backgroundColor: Colors.white.withOpacity(0.3),
                        valueColor:
                            const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _formatTime(_remainingSeconds),
                          style: const TextStyle(
                            fontSize: 64,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isBreak ? 'Take a break' : 'Stay focused',
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // 控制按钮
            Padding(
              padding: const EdgeInsets.all(32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (!_isRunning) ...[
                    FloatingActionButton.extended(
                      onPressed: _startTimer,
                      backgroundColor: Colors.white,
                      foregroundColor: _isBreak
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFF6C63FF),
                      icon: const Icon(Icons.play_arrow, size: 32),
                      label: const Text(
                        'Start',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    FloatingActionButton(
                      onPressed: _resetTimer,
                      backgroundColor: Colors.white.withOpacity(0.3),
                      foregroundColor: Colors.white,
                      child: const Icon(Icons.refresh),
                    ),
                  ] else ...[
                    FloatingActionButton.extended(
                      onPressed: _pauseTimer,
                      backgroundColor: Colors.white,
                      foregroundColor: _isBreak
                          ? const Color(0xFF4CAF50)
                          : const Color(0xFF6C63FF),
                      icon: const Icon(Icons.pause, size: 32),
                      label: const Text(
                        'Pause',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    FloatingActionButton(
                      onPressed: _resetTimer,
                      backgroundColor: Colors.white.withOpacity(0.3),
                      foregroundColor: Colors.white,
                      child: const Icon(Icons.stop),
                    ),
                  ],
                ],
              ),
            ),

            // 今日统计
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text(
                        'Completed',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$_completedPomodoros',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: 1,
                    height: 50,
                    color: Colors.white.withOpacity(0.3),
                  ),
                  Column(
                    children: [
                      const Text(
                        'Total Time',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${(_completedPomodoros * _workMinutes / 60).toStringAsFixed(1)}h',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
