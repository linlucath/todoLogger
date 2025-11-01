import 'dart:convert';
import 'dart:io';

/// 同步数据压缩工具
/// 用于减少网络传输的数据量
class SyncCompression {
  // 压缩阈值：超过此大小的数据才进行压缩（避免小数据压缩反而变大）
  static const int compressionThreshold = 1024; // 1KB

  /// 压缩JSON数据
  /// 返回压缩后的数据和是否已压缩的标志
  static Map<String, dynamic> compressJson(Map<String, dynamic> data) {
    final jsonString = jsonEncode(data);
    final bytes = utf8.encode(jsonString);

    // 如果数据太小，不压缩
    if (bytes.length < compressionThreshold) {
      return {
        'compressed': false,
        'data': data,
        'originalSize': bytes.length,
        'compressedSize': bytes.length,
      };
    }

    try {
      // 使用GZIP压缩
      final compressed = gzip.encode(bytes);
      final compressionRatio = (1 - compressed.length / bytes.length) * 100;

      print('🗜️  [Compression] 压缩完成:');
      print('   原始大小: ${_formatBytes(bytes.length)}');
      print('   压缩大小: ${_formatBytes(compressed.length)}');
      print('   压缩率: ${compressionRatio.toStringAsFixed(1)}%');

      // 如果压缩后反而变大，不使用压缩
      if (compressed.length >= bytes.length) {
        print('⚠️  [Compression] 压缩后数据更大，使用原始数据');
        return {
          'compressed': false,
          'data': data,
          'originalSize': bytes.length,
          'compressedSize': bytes.length,
        };
      }

      // 将压缩数据转为Base64以便JSON传输
      final base64Data = base64Encode(compressed);

      return {
        'compressed': true,
        'data': base64Data,
        'originalSize': bytes.length,
        'compressedSize': compressed.length,
      };
    } catch (e) {
      print('❌ [Compression] 压缩失败: $e，使用原始数据');
      return {
        'compressed': false,
        'data': data,
        'originalSize': bytes.length,
        'compressedSize': bytes.length,
      };
    }
  }

  /// 解压JSON数据
  static Map<String, dynamic>? decompressJson(Map<String, dynamic> envelope) {
    try {
      final isCompressed = envelope['compressed'] as bool? ?? false;

      if (!isCompressed) {
        // 未压缩，直接返回
        return envelope['data'] as Map<String, dynamic>?;
      }

      // 压缩数据，需要解压
      final base64Data = envelope['data'] as String;
      final compressed = base64Decode(base64Data);
      final decompressed = gzip.decode(compressed);
      final jsonString = utf8.decode(decompressed);
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      final originalSize = envelope['originalSize'] as int? ?? 0;
      final compressedSize = envelope['compressedSize'] as int? ?? 0;
      final savedBytes = originalSize - compressedSize;

      print('🗜️  [Compression] 解压完成:');
      print('   压缩大小: ${_formatBytes(compressedSize)}');
      print('   原始大小: ${_formatBytes(originalSize)}');
      print('   节省: ${_formatBytes(savedBytes)}');

      return data;
    } catch (e, stackTrace) {
      print('❌ [Compression] 解压失败: $e');
      print('Stack: $stackTrace');
      return null;
    }
  }

  /// 格式化字节大小
  static String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  /// 估算数据大小（用于判断是否需要压缩）
  static int estimateJsonSize(Map<String, dynamic> data) {
    try {
      final jsonString = jsonEncode(data);
      return utf8.encode(jsonString).length;
    } catch (e) {
      return 0;
    }
  }

  /// 批量压缩数据项
  static Map<String, dynamic> compressBatch(List<Map<String, dynamic>> items) {
    final batchData = {'items': items};
    return compressJson(batchData);
  }

  /// 批量解压数据项
  static List<Map<String, dynamic>>? decompressBatch(
      Map<String, dynamic> envelope) {
    final decompressed = decompressJson(envelope);
    if (decompressed == null) {
      return null;
    }
    return (decompressed['items'] as List?)?.cast<Map<String, dynamic>>();
  }
}
