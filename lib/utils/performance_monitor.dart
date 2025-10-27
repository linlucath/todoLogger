import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// 性能监控工具
class PerformanceMonitor {
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();
  factory PerformanceMonitor() => _instance;
  PerformanceMonitor._internal();

  // 启动时间
  DateTime? _appStartTime;
  DateTime? _firstFrameTime;

  // 帧率监控
  int _frameCount = 0;
  DateTime _lastFpsCheck = DateTime.now();
  double _currentFps = 0.0;

  /// 记录应用启动时间
  void recordAppStart() {
    _appStartTime = DateTime.now();
  }

  /// 记录首帧渲染时间
  void recordFirstFrame() {
    if (_firstFrameTime != null) return;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      _firstFrameTime = DateTime.now();

      if (_appStartTime != null) {
        final startupTime = _firstFrameTime!.difference(_appStartTime!);
        _logStartupTime(startupTime);
      }
    });
  }

  /// 开始监控帧率
  void startFpsMonitoring() {
    if (!kDebugMode) return;

    SchedulerBinding.instance.addPersistentFrameCallback((_) {
      _frameCount++;

      final now = DateTime.now();
      final elapsed = now.difference(_lastFpsCheck);

      // 每秒计算一次 FPS
      if (elapsed.inSeconds >= 1) {
        _currentFps = _frameCount / elapsed.inSeconds;
        _frameCount = 0;
        _lastFpsCheck = now;

        // FPS 低于 55 时警告
        if (_currentFps < 55) {
          debugPrint(
              '⚠️ Low FPS detected: ${_currentFps.toStringAsFixed(1)} FPS');
        }
      }
    });
  }

  /// 测量函数执行时间
  static Future<T> measure<T>(
    String label,
    Future<T> Function() function,
  ) async {
    final startTime = DateTime.now();

    developer.Timeline.startSync(label);
    try {
      return await function();
    } finally {
      developer.Timeline.finishSync();

      final duration = DateTime.now().difference(startTime);
      _logExecution(label, duration);
    }
  }

  /// 测量同步函数执行时间
  static T measureSync<T>(
    String label,
    T Function() function,
  ) {
    final startTime = DateTime.now();

    developer.Timeline.startSync(label);
    try {
      return function();
    } finally {
      developer.Timeline.finishSync();

      final duration = DateTime.now().difference(startTime);
      _logExecution(label, duration);
    }
  }

  /// 获取当前 FPS
  double get currentFps => _currentFps;

  /// 获取启动时间
  Duration? get startupTime {
    if (_appStartTime == null || _firstFrameTime == null) return null;
    return _firstFrameTime!.difference(_appStartTime!);
  }

  // ==================== 日志输出 ====================

  static void _logStartupTime(Duration duration) {
    final ms = duration.inMilliseconds;

    if (ms < 500) {
      debugPrint('✅ App startup: ${ms}ms (Excellent)');
    } else if (ms < 1000) {
      debugPrint('✅ App startup: ${ms}ms (Good)');
    } else if (ms < 2000) {
      debugPrint('⚠️ App startup: ${ms}ms (Slow)');
    } else {
      debugPrint('❌ App startup: ${ms}ms (Very Slow - needs optimization)');
    }
  }

  static void _logExecution(String label, Duration duration) {
    final ms = duration.inMilliseconds;

    if (ms < 16) {
      // 60 FPS 的一帧时间
      debugPrint('✅ $label: ${ms}ms');
    } else if (ms < 100) {
      debugPrint('⚠️ $label: ${ms}ms (Noticeable delay)');
    } else {
      debugPrint('❌ $label: ${ms}ms (Significant delay)');
    }
  }

  /// 打印性能报告
  void printReport() {
    debugPrint('');
    debugPrint('========== Performance Report ==========');

    if (startupTime != null) {
      debugPrint('Startup Time: ${startupTime!.inMilliseconds}ms');
    }

    debugPrint('Current FPS: ${_currentFps.toStringAsFixed(1)}');
    debugPrint('========================================');
    debugPrint('');
  }
}

/// 性能标记扩展
extension PerformanceExt on Future {
  /// 为 Future 添加性能测量
  Future<T> withPerformanceTracking<T>(String label) async {
    return await PerformanceMonitor.measure(label, () async => await this as T);
  }
}
