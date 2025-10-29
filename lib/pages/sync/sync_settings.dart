import 'package:flutter/material.dart';
import '../../models/sync_models.dart';
import '../../services/sync_service.dart';
import 'sync_history.dart';

/// 同步设置页面
class SyncSettingsPage extends StatefulWidget {
  final SyncService syncService;

  const SyncSettingsPage({
    Key? key,
    required this.syncService,
  }) : super(key: key);

  @override
  State<SyncSettingsPage> createState() => _SyncSettingsPageState();
}

class _SyncSettingsPageState extends State<SyncSettingsPage> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('局域网同步'),
        backgroundColor: const Color(0xFF6C63FF),
        actions: [
          // 查看同步历史
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _viewSyncHistory,
            tooltip: '同步历史',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 同步开关
          _buildSyncSwitch(),
          const SizedBox(height: 24),

          // 当前设备信息
          _buildCurrentDeviceCard(),
          const SizedBox(height: 24),

          // 已连接的设备
          _buildConnectedDevicesSection(),
          const SizedBox(height: 24),

          // 发现的设备
          _buildDiscoveredDevicesSection(),
          const SizedBox(height: 24),

          // 活动的计时器
          _buildActiveTimersSection(),
        ],
      ),
    );
  }

  /// 构建同步开关
  Widget _buildSyncSwitch() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              widget.syncService.isEnabled ? Icons.sync : Icons.sync_disabled,
              color: widget.syncService.isEnabled ? Colors.green : Colors.grey,
              size: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '局域网同步',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.syncService.isEnabled
                        ? '已启用 - 其他设备可以发现并连接到此设备'
                        : '已禁用 - 不会广播或接收同步数据',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: widget.syncService.isEnabled,
              onChanged: _isLoading ? null : _toggleSync,
              activeColor: const Color(0xFF6C63FF),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建当前设备卡片
  Widget _buildCurrentDeviceCard() {
    final device = widget.syncService.currentDevice;
    if (device == null) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.phone_android, color: Color(0xFF6C63FF)),
                const SizedBox(width: 8),
                const Text(
                  '当前设备',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildInfoRow('设备名称', device.deviceName),
            _buildInfoRow('端口', device.port.toString()),
            if (widget.syncService.isServerRunning)
              _buildInfoRow('状态', '正在监听连接', valueColor: Colors.green),
          ],
        ),
      ),
    );
  }

  /// 构建信息行
  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建已连接设备部分
  Widget _buildConnectedDevicesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.link, color: Color(0xFF6C63FF)),
            SizedBox(width: 8),
            Text(
              '已连接的设备',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<DeviceInfo>>(
          stream: widget.syncService.connectedDevicesStream,
          initialData: widget.syncService.connectedDevices,
          builder: (context, snapshot) {
            final devices = snapshot.data ?? [];
            if (devices.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      '暂无已连接的设备',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                ),
              );
            }

            return Column(
              children: devices
                  .map((device) => _buildDeviceCard(device, isConnected: true))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  /// 构建发现的设备部分
  Widget _buildDiscoveredDevicesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.devices, color: Color(0xFF6C63FF)),
            SizedBox(width: 8),
            Text(
              '发现的设备',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<DeviceInfo>>(
          stream: widget.syncService.discoveredDevicesStream,
          initialData: widget.syncService.discoveredDevices,
          builder: (context, snapshot) {
            final devices = snapshot.data ?? [];
            if (devices.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      widget.syncService.isEnabled ? '正在搜索设备...' : '请启用同步以发现设备',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                ),
              );
            }

            return Column(
              children: devices
                  .map((device) => _buildDeviceCard(device, isConnected: false))
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  /// 构建设备卡片
  Widget _buildDeviceCard(DeviceInfo device, {required bool isConnected}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          isConnected ? Icons.link : Icons.phone_android,
          color: isConnected ? Colors.green : Colors.grey,
        ),
        title: Text(
          device.deviceName,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text('${device.ipAddress}:${device.port}'),
        trailing: isConnected
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 同步按钮
                  IconButton(
                    icon: const Icon(Icons.sync, color: Color(0xFF6C63FF)),
                    onPressed: () => _syncAllToDevice(device),
                    tooltip: '同步数据',
                  ),
                  // 断开按钮
                  IconButton(
                    icon: const Icon(Icons.link_off, color: Colors.red),
                    onPressed: () => _disconnectDevice(device),
                    tooltip: '断开连接',
                  ),
                ],
              )
            : ElevatedButton(
                onPressed: () => _connectToDevice(device),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                ),
                child: const Text('连接'),
              ),
      ),
    );
  }

  /// 构建活动计时器部分
  Widget _buildActiveTimersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.timer, color: Color(0xFF6C63FF)),
            SizedBox(width: 8),
            Text(
              '其他设备的计时',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<TimerState>>(
          stream: widget.syncService.activeTimersStream,
          initialData: widget.syncService.activeTimers,
          builder: (context, snapshot) {
            final timers = snapshot.data ?? [];
            if (timers.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      '暂无活动的计时',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                ),
              );
            }

            return Column(
              children: timers.map((timer) => _buildTimerCard(timer)).toList(),
            );
          },
        ),
      ],
    );
  }

  /// 构建计时器卡片
  Widget _buildTimerCard(TimerState timer) {
    final duration = Duration(seconds: timer.currentDuration);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.timer, color: Color(0xFF6C63FF)),
        title: Text(
          timer.todoTitle,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text('来自: ${timer.deviceName}'),
        trailing: Text(
          '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF6C63FF),
          ),
        ),
      ),
    );
  }

  /// 切换同步状态
  Future<void> _toggleSync(bool value) async {
    setState(() => _isLoading = true);

    try {
      if (value) {
        await widget.syncService.enable();
      } else {
        await widget.syncService.disable();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 连接到设备
  Future<void> _connectToDevice(DeviceInfo device) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final success = await widget.syncService.connectToDevice(device);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '连接成功' : '连接失败'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('连接失败: $e')),
        );
      }
    }
  }

  /// 断开设备连接
  Future<void> _disconnectDevice(DeviceInfo device) async {
    try {
      await widget.syncService.disconnectFromDevice(device.deviceId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已断开连接')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('断开失败: $e')),
        );
      }
    }
  }

  /// 查看同步历史
  void _viewSyncHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SyncHistoryPage(
          historyService: widget.syncService.historyService,
        ),
      ),
    );
  }

  /// 同步所有数据到设备
  Future<void> _syncAllToDevice(DeviceInfo device) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在同步...'),
          ],
        ),
      ),
    );

    try {
      final success =
          await widget.syncService.syncAllDataToDevice(device.deviceId);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? '同步成功' : '同步失败'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('同步失败: $e')),
        );
      }
    }
  }
}
