import 'dart:convert';
// Note: 需要在 pubspec.yaml 中添加 crypto 包
// 如果没有 crypto 包，可以使用简单的字符串哈希作为替代
// import 'package:crypto/crypto.dart';

/// 同步数据完整性校验工具
/// 用于验证数据在传输过程中未被损坏
class SyncDataIntegrity {
  /// 计算数据的简单哈希值（不依赖crypto包）
  /// 生产环境建议使用 crypto 包的 sha256
  static String calculateHash(Map<String, dynamic> data) {
    try {
      final jsonString = jsonEncode(data);
      // 使用简单但有效的字符串哈希算法
      int hash = 0;
      for (int i = 0; i < jsonString.length; i++) {
        hash = ((hash << 5) - hash) + jsonString.codeUnitAt(i);
        hash = hash & hash; // Convert to 32bit integer
      }
      return hash.abs().toRadixString(16).padLeft(8, '0');
    } catch (e) {
      print('❌ [DataIntegrity] 计算哈希失败: $e');
      return '';
    }
  }

  /// 计算数据列表的哈希值
  static String calculateListHash(List<Map<String, dynamic>> dataList) {
    return calculateHash({'items': dataList});
  }

  /// 为数据添加完整性校验信息
  static Map<String, dynamic> addIntegrityCheck(Map<String, dynamic> data) {
    final hash = calculateHash(data);
    final timestamp = DateTime.now().toIso8601String();

    return {
      'data': data,
      'integrity': {
        'hash': hash,
        'timestamp': timestamp,
        'algorithm': 'simple-hash',
      },
    };
  }

  /// 验证数据完整性
  /// 返回 true 表示数据完整，false 表示数据已损坏
  static bool verifyIntegrity(Map<String, dynamic> envelope) {
    try {
      if (!envelope.containsKey('data') || !envelope.containsKey('integrity')) {
        print('⚠️  [DataIntegrity] 数据格式错误，缺少完整性信息');
        return false;
      }

      final data = envelope['data'];
      final integrity = envelope['integrity'] as Map<String, dynamic>;
      final expectedHash = integrity['hash'] as String?;
      final algorithm = integrity['algorithm'] as String?;

      if (expectedHash == null || algorithm == null) {
        print('⚠️  [DataIntegrity] 完整性信息不完整');
        return false;
      }

      // 计算实际哈希值
      final actualHash = calculateHash(data as Map<String, dynamic>);

      // 比较哈希值
      if (actualHash != expectedHash) {
        print('❌ [DataIntegrity] 数据完整性验证失败！');
        print('   期望哈希: $expectedHash');
        print('   实际哈希: $actualHash');
        return false;
      }

      print('✅ [DataIntegrity] 数据完整性验证通过');
      return true;
    } catch (e, stackTrace) {
      print('❌ [DataIntegrity] 验证过程异常: $e');
      print('Stack: $stackTrace');
      return false;
    }
  }

  /// 提取已验证的数据
  /// 验证通过后返回实际数据，验证失败返回 null
  static Map<String, dynamic>? extractVerifiedData(
      Map<String, dynamic> envelope) {
    if (!verifyIntegrity(envelope)) {
      return null;
    }
    return envelope['data'] as Map<String, dynamic>?;
  }

  /// 为批量数据添加完整性校验
  static Map<String, dynamic> addBatchIntegrityCheck(
      List<Map<String, dynamic>> dataList) {
    return addIntegrityCheck({'items': dataList});
  }

  /// 验证并提取批量数据
  static List<Map<String, dynamic>>? extractVerifiedBatch(
      Map<String, dynamic> envelope) {
    final verified = extractVerifiedData(envelope);
    if (verified == null) {
      return null;
    }
    return (verified['items'] as List?)?.cast<Map<String, dynamic>>();
  }

  /// 计算数据大小（字节）
  static int calculateDataSize(Map<String, dynamic> data) {
    try {
      final jsonString = jsonEncode(data);
      return utf8.encode(jsonString).length;
    } catch (e) {
      return 0;
    }
  }

  /// 生成数据摘要信息（用于日志）
  static Map<String, dynamic> generateDataSummary(Map<String, dynamic> data) {
    return {
      'hash': calculateHash(data).substring(0, 16), // 只取前16个字符
      'size': calculateDataSize(data),
      'timestamp': DateTime.now().toIso8601String(),
      'itemCount': _countItems(data),
    };
  }

  /// 计算数据项数量
  static int _countItems(Map<String, dynamic> data) {
    int count = 0;

    if (data.containsKey('items') && data['items'] is List) {
      count += (data['items'] as List).length;
    }

    if (data.containsKey('lists') && data['lists'] is List) {
      count += (data['lists'] as List).length;
    }

    return count;
  }

  /// 比较两个数据集的差异
  static Map<String, dynamic> compareData(
    Map<String, dynamic> data1,
    Map<String, dynamic> data2,
  ) {
    final hash1 = calculateHash(data1);
    final hash2 = calculateHash(data2);

    return {
      'identical': hash1 == hash2,
      'hash1': hash1.substring(0, 16),
      'hash2': hash2.substring(0, 16),
      'size1': calculateDataSize(data1),
      'size2': calculateDataSize(data2),
    };
  }
}
