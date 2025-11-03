import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cc/models/sync_models.dart';

/// 设备ID持久化功能测试
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DeviceInfo Persistence Tests', () {
    setUp(() async {
      // 每次测试前清空 SharedPreferences
      SharedPreferences.setMockInitialValues({});
    });

    test('首次启动应生成新的设备ID', () async {
      // 验证初始状态为空
      var savedId = await DeviceInfo.getSavedDeviceId();
      expect(savedId, isNull);

      // 获取设备信息
      var device = await DeviceInfo.getCurrentDevice(8765);

      // 验证生成了ID
      expect(device.deviceId, isNotEmpty);
      expect(device.deviceId.length, 36); // UUID v4 格式

      // 验证ID已保存
      savedId = await DeviceInfo.getSavedDeviceId();
      expect(savedId, equals(device.deviceId));
    });

    test('重复调用应返回相同的设备ID', () async {
      // 第一次调用
      var device1 = await DeviceInfo.getCurrentDevice(8765);

      // 第二次调用
      var device2 = await DeviceInfo.getCurrentDevice(8765);

      // 验证ID相同
      expect(device1.deviceId, equals(device2.deviceId));
    });

    test('设备名称应该持久化', () async {
      // 首次启动应生成设备名称
      var device = await DeviceInfo.getCurrentDevice(8765);
      expect(device.deviceName, isNotEmpty);

      // 验证名称已保存
      var savedName = await DeviceInfo.getSavedDeviceName();
      expect(savedName, equals(device.deviceName));
    });

    test('应该能够更新设备名称', () async {
      // 生成初始设备信息
      var device1 = await DeviceInfo.getCurrentDevice(8765);
      var originalName = device1.deviceName;

      // 更新设备名称
      const newName = '我的测试设备';
      await DeviceInfo.updateDeviceName(newName);

      // 验证名称已更新
      var savedName = await DeviceInfo.getSavedDeviceName();
      expect(savedName, equals(newName));
      expect(savedName, isNot(equals(originalName)));

      // 重新获取设备信息，应使用新名称
      var device2 = await DeviceInfo.getCurrentDevice(8765);
      expect(device2.deviceName, equals(newName));
      expect(device2.deviceId, equals(device1.deviceId)); // ID保持不变
    });

    test('重置设备信息应清除保存的数据', () async {
      // 生成设备信息
      var device1 = await DeviceInfo.getCurrentDevice(8765);
      var originalId = device1.deviceId;

      // 验证数据已保存
      expect(await DeviceInfo.getSavedDeviceId(), isNotNull);
      expect(await DeviceInfo.getSavedDeviceName(), isNotNull);

      // 重置设备信息
      await DeviceInfo.resetDeviceInfo();

      // 验证数据已清除
      expect(await DeviceInfo.getSavedDeviceId(), isNull);
      expect(await DeviceInfo.getSavedDeviceName(), isNull);

      // 重新获取应生成新ID
      var device2 = await DeviceInfo.getCurrentDevice(8765);
      expect(device2.deviceId, isNot(equals(originalId)));
    });

    test('设备ID应该是有效的UUID v4格式', () async {
      var device = await DeviceInfo.getCurrentDevice(8765);

      // UUID v4 格式: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
      final uuidRegex = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false,
      );

      expect(uuidRegex.hasMatch(device.deviceId), isTrue);
    });

    test('不同平台应生成包含平台信息的设备名称', () async {
      var device = await DeviceInfo.getCurrentDevice(8765);

      // 设备名称应包含平台信息
      expect(
        device.deviceName,
        anyOf([
          contains('Windows'),
          contains('Mac'),
          contains('Linux'),
          contains('Android'),
          contains('iOS'),
          contains('Unknown'),
        ]),
      );
    });

    test('设备信息应该包含端口号', () async {
      const testPort = 12345;
      var device = await DeviceInfo.getCurrentDevice(testPort);

      expect(device.port, equals(testPort));
    });

    test('新生成的设备应标记为已连接', () async {
      var device = await DeviceInfo.getCurrentDevice(8765);

      expect(device.isConnected, isTrue);
    });

    test('并发调用getCurrentDevice应返回相同ID', () async {
      // 模拟多个并发调用
      var futures = List.generate(
        10,
        (_) => DeviceInfo.getCurrentDevice(8765),
      );

      var devices = await Future.wait(futures);

      // 所有调用应返回相同的ID
      var firstId = devices.first.deviceId;
      for (var device in devices) {
        expect(device.deviceId, equals(firstId));
      }
    });
  });

  group('DeviceInfo JSON Serialization Tests', () {
    test('设备信息应正确序列化和反序列化', () async {
      var device1 = await DeviceInfo.getCurrentDevice(8765);

      // 序列化
      var json = device1.toJson();

      // 反序列化
      var device2 = DeviceInfo.fromJson(json);

      // 验证数据一致
      expect(device2.deviceId, equals(device1.deviceId));
      expect(device2.deviceName, equals(device1.deviceName));
      expect(device2.port, equals(device1.port));
      expect(device2.isConnected, equals(device1.isConnected));
    });
  });

  group('DeviceInfo copyWith Tests', () {
    test('copyWith应保持设备ID不变', () async {
      var device1 = await DeviceInfo.getCurrentDevice(8765);

      var device2 = device1.copyWith(
        deviceName: '新设备名',
        port: 9999,
      );

      expect(device2.deviceId, equals(device1.deviceId));
      expect(device2.deviceName, equals('新设备名'));
      expect(device2.port, equals(9999));
    });
  });
}
