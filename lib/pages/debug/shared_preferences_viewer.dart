import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// SharedPreferences 查看器页面
/// 以表格形式展示所有存储的键值对
class SharedPreferencesViewer extends StatefulWidget {
  const SharedPreferencesViewer({super.key});

  @override
  State<SharedPreferencesViewer> createState() =>
      _SharedPreferencesViewerState();
}

class _SharedPreferencesViewerState extends State<SharedPreferencesViewer> {
  Map<String, dynamic> _preferences = {};
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedKey;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 加载所有 SharedPreferences
  Future<void> _loadPreferences() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      final Map<String, dynamic> data = {};
      for (final key in keys) {
        final value = prefs.get(key);
        data[key] = value;
      }

      setState(() {
        _preferences = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
      }
    }
  }

  /// 删除指定的键
  Future<void> _deleteKey(String key) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除键 "$key" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      await _loadPreferences();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除: $key')),
        );
      }
    }
  }

  /// 清空所有 SharedPreferences
  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ 警告'),
        content: const Text('确定要清空所有 SharedPreferences 吗？此操作不可恢复！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('清空'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await _loadPreferences();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已清空所有数据')),
        );
      }
    }
  }

  /// 导出为 JSON
  Future<void> _exportToJson() async {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(_preferences);

    await Clipboard.setData(ClipboardData(text: jsonStr));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制到剪贴板')),
      );
    }
  }

  /// 查看详细内容
  void _viewDetails(String key, dynamic value) {
    setState(() => _selectedKey = key);

    String displayValue;
    try {
      // 尝试格式化 JSON
      if (value is String && (value.startsWith('{') || value.startsWith('['))) {
        final decoded = jsonDecode(value);
        displayValue = const JsonEncoder.withIndent('  ').convert(decoded);
      } else {
        displayValue = value.toString();
      }
    } catch (e) {
      displayValue = value.toString();
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Color(0xFF6C63FF)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                key,
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: Container(
          constraints: const BoxConstraints(
            maxHeight: 400,
            maxWidth: 600,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 类型信息
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Text(
                        '类型: ',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(_getTypeString(value)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // 值
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: SelectableText(
                    displayValue,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: displayValue));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已复制值')),
              );
            },
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  String _getTypeString(dynamic value) {
    if (value == null) return 'null';
    if (value is String) return 'String';
    if (value is int) return 'int';
    if (value is double) return 'double';
    if (value is bool) return 'bool';
    if (value is List) return 'List<String>';
    return value.runtimeType.toString();
  }

  /// 获取过滤后的数据
  List<MapEntry<String, dynamic>> get _filteredEntries {
    if (_searchQuery.isEmpty) {
      return _preferences.entries.toList();
    }

    return _preferences.entries.where((entry) {
      final key = entry.key.toLowerCase();
      final value = entry.value.toString().toLowerCase();
      final query = _searchQuery.toLowerCase();
      return key.contains(query) || value.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SharedPreferences 查看器'),
        backgroundColor: const Color(0xFF6C63FF),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPreferences,
            tooltip: '刷新',
          ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportToJson,
            tooltip: '导出 JSON',
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            onPressed: _clearAll,
            tooltip: '清空所有',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 搜索栏
                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey[100],
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: '搜索键或值...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                          onChanged: (value) {
                            setState(() => _searchQuery = value);
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      // 统计信息
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6C63FF),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '共 ${_preferences.length} 项',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 表格
                Expanded(
                  child: _preferences.isEmpty
                      ? const Center(
                          child: Text(
                            '没有数据',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SingleChildScrollView(
                            child: _buildDataTable(),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildDataTable() {
    final entries = _filteredEntries;

    return DataTable(
      headingRowColor: MaterialStateProperty.all(
        const Color(0xFF6C63FF).withOpacity(0.1),
      ),
      columns: const [
        DataColumn(
          label: Text(
            '键 (Key)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        DataColumn(
          label: Text(
            '类型',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        DataColumn(
          label: Text(
            '值 (Value)',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        DataColumn(
          label: Text(
            '操作',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
      rows: entries.map((entry) {
        final key = entry.key;
        final value = entry.value;
        final valuePreview = _getValuePreview(value);

        return DataRow(
          selected: _selectedKey == key,
          cells: [
            // 键
            DataCell(
              Container(
                constraints: const BoxConstraints(maxWidth: 200),
                child: SelectableText(
                  key,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              onTap: () {
                Clipboard.setData(ClipboardData(text: key));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('已复制键: $key')),
                );
              },
            ),
            // 类型
            DataCell(
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _getTypeColor(value),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _getTypeString(value),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            // 值预览
            DataCell(
              Container(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Text(
                  valuePreview,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
              onTap: () => _viewDetails(key, value),
            ),
            // 操作按钮
            DataCell(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.visibility, size: 20),
                    onPressed: () => _viewDetails(key, value),
                    tooltip: '查看详情',
                    color: const Color(0xFF6C63FF),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: value.toString()),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已复制值')),
                      );
                    },
                    tooltip: '复制值',
                    color: Colors.blue,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 20),
                    onPressed: () => _deleteKey(key),
                    tooltip: '删除',
                    color: Colors.red,
                  ),
                ],
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  String _getValuePreview(dynamic value) {
    if (value == null) return 'null';
    if (value is String) {
      if (value.length > 100) {
        return '${value.substring(0, 100)}...';
      }
      return value;
    }
    return value.toString();
  }

  Color _getTypeColor(dynamic value) {
    if (value is String) return Colors.green;
    if (value is int) return Colors.blue;
    if (value is double) return Colors.purple;
    if (value is bool) return Colors.orange;
    if (value is List) return Colors.teal;
    return Colors.grey;
  }
}
