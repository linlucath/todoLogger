import 'dart:async';

/// 同步锁 - 用于控制并发操作
/// 确保同一时间只有一个同步操作在进行
class SyncLock {
  final Map<String, Completer<void>> _locks = {};
  final Map<String, DateTime> _lockTimestamps = {};
  final Map<String, String> _lockOwners = {};

  static const Duration _lockTimeout = Duration(minutes: 5);

  /// 获取锁
  /// [key] - 锁的标识符（如设备ID）
  /// [owner] - 锁的持有者标识（用于调试）
  /// 返回 true 表示成功获取锁，false 表示锁被占用
  Future<bool> acquire(String key, String owner) async {
    // 检查是否已有锁
    if (_locks.containsKey(key)) {
      final timestamp = _lockTimestamps[key];
      final currentOwner = _lockOwners[key];

      // 检查锁是否超时
      if (timestamp != null &&
          DateTime.now().difference(timestamp) > _lockTimeout) {
        print('⚠️  [SyncLock] 锁超时，强制释放: $key (持有者: $currentOwner)');
        await release(key);
      } else {
        print('🔒 [SyncLock] 锁被占用: $key (持有者: $currentOwner, 请求者: $owner)');
        return false;
      }
    }

    // 创建新锁
    final completer = Completer<void>();
    _locks[key] = completer;
    _lockTimestamps[key] = DateTime.now();
    _lockOwners[key] = owner;

    print('🔓 [SyncLock] 锁已获取: $key (持有者: $owner)');
    return true;
  }

  /// 释放锁
  Future<void> release(String key) async {
    final completer = _locks.remove(key);
    _lockTimestamps.remove(key);
    final owner = _lockOwners.remove(key);

    if (completer != null && !completer.isCompleted) {
      completer.complete();
      print('🔓 [SyncLock] 锁已释放: $key (持有者: $owner)');
    }
  }

  /// 尝试执行带锁的操作
  /// 如果无法获取锁，返回 null
  Future<T?> withLock<T>(
    String key,
    String owner,
    Future<T> Function() operation,
  ) async {
    if (!await acquire(key, owner)) {
      return null;
    }

    try {
      return await operation();
    } finally {
      await release(key);
    }
  }

  /// 等待获取锁并执行操作
  /// 会一直等待直到获取锁
  Future<T> waitForLock<T>(
    String key,
    String owner,
    Future<T> Function() operation, {
    Duration checkInterval = const Duration(seconds: 1),
    Duration? timeout,
  }) async {
    final startTime = DateTime.now();

    while (true) {
      if (await acquire(key, owner)) {
        try {
          return await operation();
        } finally {
          await release(key);
        }
      }

      // 检查超时
      if (timeout != null && DateTime.now().difference(startTime) > timeout) {
        throw TimeoutException('等待锁超时: $key');
      }

      // 等待后重试
      await Future.delayed(checkInterval);
    }
  }

  /// 检查锁是否被占用
  bool isLocked(String key) {
    return _locks.containsKey(key);
  }

  /// 获取锁的持有者
  String? getLockOwner(String key) {
    return _lockOwners[key];
  }

  /// 清理所有超时的锁
  Future<void> cleanupTimeoutLocks() async {
    final now = DateTime.now();
    final expiredKeys = <String>[];

    for (final entry in _lockTimestamps.entries) {
      if (now.difference(entry.value) > _lockTimeout) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      final owner = _lockOwners[key];
      print('⚠️  [SyncLock] 清理超时锁: $key (持有者: $owner)');
      await release(key);
    }

    if (expiredKeys.isNotEmpty) {
      print('🧹 [SyncLock] 清理了 ${expiredKeys.length} 个超时锁');
    }
  }

  /// 获取当前活动锁的数量
  int get activeLockCount => _locks.length;

  /// 清除所有锁
  Future<void> clear() async {
    final keys = _locks.keys.toList();
    for (final key in keys) {
      await release(key);
    }
    print('🧹 [SyncLock] 已清除所有锁');
  }
}
