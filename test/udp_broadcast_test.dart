import 'dart:io';
import 'dart:convert';
import 'dart:async';

/// UDP广播测试工具 - 用于诊断移动设备发现问题
void main() async {
  print('🔧 [UDPTest] UDP广播测试工具');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  // 测试1: 绑定UDP端口
  print('\n📋 测试1: 绑定UDP Socket到端口8766');
  RawDatagramSocket? socket;
  try {
    socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 8766);
    print('✅ Socket绑定成功: ${socket.address}:${socket.port}');

    // 启用广播
    socket.broadcastEnabled = true;
    print('✅ 广播功能已启用');
  } catch (e) {
    print('❌ Socket绑定失败: $e');
    return;
  }

  // 测试2: 获取本机IP地址
  print('\n📋 测试2: 获取本机IP地址');
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLinkLocal: false,
    );

    // print('发现 ${interfaces.length} 个网络接口:');
    String? localIp;

    for (var interface in interfaces) {
      // print('\n接口名称: ${interface.name}');
      for (var addr in interface.addresses) {
        // print('  地址: ${addr.address}');
        // print('  回环: ${addr.isLoopback}');
        // print('  链路本地: ${addr.isLinkLocal}');
        // print('  组播: ${addr.isMulticast}');

        if (!addr.isLoopback && !addr.isLinkLocal) {
          localIp = addr.address;
          // print('  ✅ 选择此地址');
        }
      }
    }

    if (localIp == null) {
      print('❌ 未找到可用的IP地址');
      socket.close();
      return;
    }

    print('\n✅ 使用IP地址: $localIp');

    // 测试3: 发送广播消息
    print('\n📋 测试3: 发送UDP广播消息');
    final message = {
      'type': 'device_announcement',
      'deviceId': 'test-device-id',
      'deviceName': 'TestDevice',
      'ipAddress': localIp,
      'port': 8765,
      'timestamp': DateTime.now().toIso8601String(),
    };

    final jsonString = jsonEncode(message);
    print('消息内容: $jsonString');

    final data = utf8.encode(jsonString);
    print('消息大小: ${data.length} bytes');

    final broadcastAddr = InternetAddress('255.255.255.255');
    final bytesSent = socket.send(data, broadcastAddr, 8766);

    print('✅ 广播发送成功: $bytesSent bytes 到 255.255.255.255:8766');

    // 测试4: 监听UDP消息
    print('\n📋 测试4: 监听UDP广播消息 (30秒)');
    print('等待其他设备的广播...');

    var messageCount = 0;
    var ownMessageCount = 0;

    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket!.receive();
        if (datagram != null) {
          try {
            final receivedData = utf8.decode(datagram.data);
            final receivedMsg =
                jsonDecode(receivedData) as Map<String, dynamic>;

            if (receivedMsg['deviceId'] == 'test-device-id') {
              ownMessageCount++;
              print('🔄 收到自己的广播消息 (#$ownMessageCount)');
            } else {
              messageCount++;
              print('\n✨ 收到其他设备消息 (#$messageCount):');
              print('   来源: ${datagram.address.address}:${datagram.port}');
              print('   设备: ${receivedMsg['deviceName']}');
              print('   IP: ${receivedMsg['ipAddress']}');
              print('   端口: ${receivedMsg['port']}');
            }
          } catch (e) {
            print('⚠️  收到非标准消息: ${datagram.address.address}');
          }
        }
      }
    });

    // 持续发送广播
    print('每3秒发送一次广播...');
    var broadcastCount = 0;
    final broadcastTimer = Timer.periodic(Duration(seconds: 3), (timer) {
      broadcastCount++;
      final bytesSent = socket!.send(data, broadcastAddr, 8766);
      print('📡 发送广播 #$broadcastCount: $bytesSent bytes');
    });

    // 30秒后停止
    await Future.delayed(Duration(seconds: 30));

    broadcastTimer.cancel();
    socket.close();

    print('\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📊 测试结果统计:');
    print('   发送广播次数: $broadcastCount');
    print('   收到自己的消息: $ownMessageCount');
    print('   收到其他设备消息: $messageCount');

    if (ownMessageCount > 0) {
      print('\n✅ 本地UDP回环正常');
    } else {
      print('\n⚠️  本地UDP回环异常');
    }

    if (messageCount > 0) {
      print('✅ 成功接收到其他设备的广播');
    } else {
      print('❌ 未接收到任何其他设备的广播');
      print('\n可能的原因:');
      print('  1. 移动设备未在同一WiFi网络');
      print('  2. 移动设备未启动同步功能');
      print('  3. 路由器开启了AP隔离');
      print('  4. 防火墙阻止了UDP 8766端口');
      print('  5. 移动设备使用了不同的广播端口');
    }

    print('\n🔍 建议:');
    print('  1. 在移动设备上运行相同的测试');
    print('  2. 确认两个设备的IP地址在同一网段');
    print('  3. 检查路由器设置是否有AP隔离');
    print('  4. 尝试关闭Windows防火墙测试');
  } catch (e, stack) {
    print('❌ 测试失败: $e');
    print('堆栈: $stack');
    socket.close();
  }
}
