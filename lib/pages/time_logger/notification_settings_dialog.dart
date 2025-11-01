import 'package:flutter/material.dart';
import 'dart:io';
import '../../services/notification_service.dart';
import 'notification_history_page.dart';

/// 通知设置对话框
class NotificationSettingsDialog extends StatefulWidget {
  const NotificationSettingsDialog({super.key});

  @override
  State<NotificationSettingsDialog> createState() =>
      _NotificationSettingsDialogState();
}

class _NotificationSettingsDialogState
    extends State<NotificationSettingsDialog> {
  final NotificationService _notificationService = NotificationService();
  late bool _notificationsEnabled;
  late int _notificationInterval;
  late bool _notificationSound;
  late bool _notificationVibration;
  late bool _doNotDisturbEnabled;
  late int _doNotDisturbStartHour;
  late int _doNotDisturbEndHour;

  // 可选的通知间隔（分钟）
  final List<int> _intervalOptions = [1, 3, 5, 10, 15, 30];

  @override
  void initState() {
    super.initState();
    _notificationsEnabled = _notificationService.notificationsEnabled;
    _notificationInterval = _notificationService.notificationIntervalMinutes;
    _notificationSound = _notificationService.notificationSound;
    _notificationVibration = _notificationService.notificationVibration;
    _doNotDisturbEnabled = _notificationService.doNotDisturbEnabled;
    _doNotDisturbStartHour = _notificationService.doNotDisturbStartHour;
    _doNotDisturbEndHour = _notificationService.doNotDisturbEndHour;
  }

  @override
  Widget build(BuildContext context) {
    // 只在移动端显示通知设置
    if (!Platform.isAndroid && !Platform.isIOS) {
      return AlertDialog(
        title: const Text('通知设置'),
        content: const Text('通知功能仅在移动端（Android/iOS）可用'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.notifications_active, color: Color(0xFF6C63FF)),
          SizedBox(width: 8),
          Text('通知设置'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 启用/禁用通知
            SwitchListTile(
              title: const Text('启用后台通知'),
              subtitle: const Text('在应用切换到后台时定期提醒计时状态'),
              value: _notificationsEnabled,
              activeTrackColor: const Color(0xFF6C63FF).withOpacity(0.5),
              activeThumbColor: const Color(0xFF6C63FF),
              onChanged: (value) {
                setState(() {
                  _notificationsEnabled = value;
                });
              },
            ),
            const SizedBox(height: 16),

            // 通知间隔设置
            if (_notificationsEnabled) ...[
              const Text(
                '通知间隔',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '选择后台通知的发送间隔',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 12),

              // 间隔选项
              ..._intervalOptions.map((minutes) {
                return RadioListTile<int>(
                  title: Text(_getIntervalText(minutes)),
                  value: minutes,
                  groupValue: _notificationInterval,
                  toggleable: false,
                  activeColor: const Color(0xFF6C63FF),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _notificationInterval = value;
                      });
                    }
                  },
                );
              }),
            ],

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),

            // 🆕 音效和震动设置
            const Text(
              '通知效果',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),

            // 声音开关
            SwitchListTile(
              title: const Text('通知声音'),
              subtitle: const Text('播放通知声音'),
              value: _notificationSound,
              activeTrackColor: const Color(0xFF6C63FF).withOpacity(0.5),
              activeThumbColor: const Color(0xFF6C63FF),
              secondary: const Icon(Icons.volume_up),
              onChanged: _notificationsEnabled
                  ? (value) {
                      setState(() {
                        _notificationSound = value;
                      });
                    }
                  : null,
            ),

            // 震动开关
            SwitchListTile(
              title: const Text('通知震动'),
              subtitle: const Text('震动提醒'),
              value: _notificationVibration,
              activeTrackColor: const Color(0xFF6C63FF).withOpacity(0.5),
              activeThumbColor: const Color(0xFF6C63FF),
              secondary: const Icon(Icons.vibration),
              onChanged: _notificationsEnabled
                  ? (value) {
                      setState(() {
                        _notificationVibration = value;
                      });
                    }
                  : null,
            ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),

            // 🆕 免打扰设置
            const Text(
              '免打扰时段',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '在指定时段内不发送通知',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 12),

            // 免打扰开关
            SwitchListTile(
              title: const Text('启用免打扰'),
              subtitle: Text(_doNotDisturbEnabled
                  ? '${_doNotDisturbStartHour.toString().padLeft(2, '0')}:00 - ${_doNotDisturbEndHour.toString().padLeft(2, '0')}:00'
                  : '未启用'),
              value: _doNotDisturbEnabled,
              activeTrackColor: const Color(0xFF6C63FF).withOpacity(0.5),
              activeThumbColor: const Color(0xFF6C63FF),
              secondary: const Icon(Icons.bedtime),
              onChanged: _notificationsEnabled
                  ? (value) {
                      setState(() {
                        _doNotDisturbEnabled = value;
                      });
                    }
                  : null,
            ),

            // 时间选择
            if (_doNotDisturbEnabled && _notificationsEnabled) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      title: const Text('开始时间', style: TextStyle(fontSize: 14)),
                      subtitle: Text(
                        '${_doNotDisturbStartHour.toString().padLeft(2, '0')}:00',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      onTap: () async {
                        final hour = await _showHourPicker(
                            context, _doNotDisturbStartHour);
                        if (hour != null) {
                          setState(() {
                            _doNotDisturbStartHour = hour;
                          });
                        }
                      },
                    ),
                  ),
                  const Icon(Icons.arrow_forward),
                  Expanded(
                    child: ListTile(
                      title: const Text('结束时间', style: TextStyle(fontSize: 14)),
                      subtitle: Text(
                        '${_doNotDisturbEndHour.toString().padLeft(2, '0')}:00',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      onTap: () async {
                        final hour = await _showHourPicker(
                            context, _doNotDisturbEndHour);
                        if (hour != null) {
                          setState(() {
                            _doNotDisturbEndHour = hour;
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),

            // 🆕 通知预览按钮
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _notificationsEnabled
                    ? () async {
                        await _notificationService.previewNotification(
                          '示例活动',
                          durationText: '已记录 25分钟',
                          progressPercent: 25,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已发送预览通知，请查看通知栏'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      }
                    : null,
                icon: const Icon(Icons.preview),
                label: const Text('预览通知效果'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6C63FF),
                  side: const BorderSide(color: Color(0xFF6C63FF)),
                ),
              ),
            ),

            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 12),

            // 🆕 统计信息
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.notifications_active,
                      color: Colors.green.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '已发送通知: ${_notificationService.notificationCount} 次\n'
                      '历史记录: ${_notificationService.notificationHistory.length} 条',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
                  // 清除历史按钮
                  if (_notificationService.notificationHistory.isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        await _notificationService.clearNotificationHistory();
                        setState(() {}); // 刷新显示
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已清除通知历史'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                      child: const Text('清除'),
                    ),
                ],
              ),
            ),

            // 🆕 查看历史按钮
            if (_notificationService.notificationHistory.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const NotificationHistoryPage(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.history),
                    label: const Text('查看通知历史'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6C63FF),
                      side: const BorderSide(color: Color(0xFF6C63FF)),
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // 提示信息
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '通知会在应用切换到后台且正在计时时自动发送，返回应用前台时通知会自动停止',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () async {
            // 保存设置
            await _notificationService
                .setNotificationsEnabled(_notificationsEnabled);
            await _notificationService
                .setNotificationInterval(_notificationInterval);
            await _notificationService.setNotificationSound(_notificationSound);
            await _notificationService
                .setNotificationVibration(_notificationVibration);
            await _notificationService.setDoNotDisturb(
              _doNotDisturbEnabled,
              startHour: _doNotDisturbStartHour,
              endHour: _doNotDisturbEndHour,
            );

            if (context.mounted) {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('通知设置已保存'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6C63FF),
            foregroundColor: Colors.white,
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }

  String _getIntervalText(int minutes) {
    if (minutes < 60) {
      return '$minutes 分钟';
    } else {
      final hours = minutes ~/ 60;
      return '$hours 小时';
    }
  }

  /// 显示小时选择器
  Future<int?> _showHourPicker(BuildContext context, int initialHour) async {
    int selectedHour = initialHour;

    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('选择小时'),
        content: SizedBox(
          width: 300,
          height: 300,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 1.5,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: 24,
            itemBuilder: (context, index) {
              final isSelected = index == selectedHour;
              return InkWell(
                onTap: () {
                  Navigator.of(context).pop(index);
                },
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF6C63FF)
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${index.toString().padLeft(2, '0')}:00',
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}
