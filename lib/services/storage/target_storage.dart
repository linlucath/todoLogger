import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/target_models.dart';

class TargetStorage {
  static const String _targetsKey = 'targets';

  /// 加载所有目标
  Future<List<Target>> loadTargets() async {
    print('📂 [TargetStorage] 加载目标列表...');
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? targetsJson = prefs.getString(_targetsKey);

      if (targetsJson == null || targetsJson.isEmpty) {
        print('📂 [TargetStorage] 没有找到已保存的目标');
        return [];
      }

      final List<dynamic> targetsList = json.decode(targetsJson);
      final targets = targetsList
          .map((json) => Target.fromJson(json as Map<String, dynamic>))
          .toList();

      print('✅ [TargetStorage] 成功加载 ${targets.length} 个目标');
      return targets;
    } catch (e) {
      print('❌ [TargetStorage] 加载目标失败: $e');
      return [];
    }
  }

  /// 保存所有目标
  Future<void> saveTargets(List<Target> targets) async {
    print('💾 [TargetStorage] 保存 ${targets.length} 个目标...');
    try {
      final prefs = await SharedPreferences.getInstance();
      final targetsJson = json.encode(
        targets.map((target) => target.toJson()).toList(),
      );
      await prefs.setString(_targetsKey, targetsJson);
      print('✅ [TargetStorage] 目标保存成功');
    } catch (e) {
      print('❌ [TargetStorage] 保存目标失败: $e');
    }
  }

  /// 添加新目标
  Future<void> addTarget(Target target, List<Target> currentTargets) async {
    print('➕ [TargetStorage] 添加新目标: ${target.name}');
    currentTargets.add(target);
    await saveTargets(currentTargets);
  }

  /// 更新目标
  Future<void> updateTarget(
      Target updatedTarget, List<Target> currentTargets) async {
    print('✏️ [TargetStorage] 更新目标: ${updatedTarget.name}');
    final index = currentTargets.indexWhere((t) => t.id == updatedTarget.id);
    if (index != -1) {
      currentTargets[index] = updatedTarget;
      await saveTargets(currentTargets);
    } else {
      print('⚠️ [TargetStorage] 未找到要更新的目标: ${updatedTarget.id}');
    }
  }

  /// 删除目标
  Future<void> deleteTarget(
      String targetId, List<Target> currentTargets) async {
    print('🗑️ [TargetStorage] 删除目标: $targetId');
    currentTargets.removeWhere((t) => t.id == targetId);
    await saveTargets(currentTargets);
  }

  /// 切换目标启用状态
  Future<void> toggleTargetActive(
      String targetId, List<Target> currentTargets) async {
    final index = currentTargets.indexWhere((t) => t.id == targetId);
    if (index != -1) {
      final target = currentTargets[index];
      currentTargets[index] = target.copyWith(isActive: !target.isActive);
      print(
          '🔄 [TargetStorage] 切换目标状态: ${target.name} -> ${!target.isActive ? "启用" : "禁用"}');
      await saveTargets(currentTargets);
    }
  }

  /// 清空所有目标
  Future<void> clearAllTargets() async {
    print('🗑️ [TargetStorage] 清空所有目标');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_targetsKey);
    print('✅ [TargetStorage] 所有目标已清空');
  }
}
