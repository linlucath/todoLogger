import 'package:flutter/material.dart';
import 'dart:io';
import '../../services/notification_service.dart';
import 'package:intl/intl.dart';

/// 通知历史记录页面
class NotificationHistoryPage extends StatelessWidget {
  const NotificationHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final notificationService = NotificationService();

    // 只在移动端显示
    if (!Platform.isAndroid && !Platform.isIOS) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('通知历史'),
        ),
        body: const Center(
          child: Text('通知功能仅在移动端（Android/iOS）可用'),
        ),
      );
    }

    final history = notificationService.notificationHistory;

    return Scaffold(
      appBar: AppBar(
        title: const Text('通知历史'),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '清除所有历史',
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('确认清除'),
                    content: const Text('确定要清除所有通知历史记录吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('取消'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('清除'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true && context.mounted) {
                  await notificationService.clearNotificationHistory();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已清除所有通知历史')),
                    );
                    Navigator.of(context).pop(); // 返回上一页
                  }
                }
              },
            ),
        ],
      ),
      body: history.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.notifications_none,
                    size: 80,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '暂无通知历史',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '开始计时后切换到后台将自动发送通知',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: history.length,
              reverse: true, // 最新的在前面
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final item = history[history.length - 1 - index];
                return _NotificationHistoryCard(item: item);
              },
            ),
    );
  }
}

/// 通知历史卡片
class _NotificationHistoryCard extends StatelessWidget {
  final NotificationHistoryItem item;

  const _NotificationHistoryCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm:ss');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 时间戳
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(
                  dateFormat.format(item.timestamp),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
                const Spacer(),
                // 进度指示器
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getProgressColor(item.progressPercent),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${item.progressPercent}%',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 活动名称
            Row(
              children: [
                const Icon(Icons.label, size: 18, color: Color(0xFF6C63FF)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.activityName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 时长
            Row(
              children: [
                Icon(Icons.timer, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text(
                  item.durationText,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getProgressColor(int progress) {
    if (progress < 30) {
      return Colors.orange;
    } else if (progress < 70) {
      return Colors.blue;
    } else {
      return Colors.green;
    }
  }
}
