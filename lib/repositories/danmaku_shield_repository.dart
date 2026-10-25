import 'dart:async';

import 'package:hive_ce/hive.dart';
import 'package:wyw/modules/danmaku/danmaku_shield_rule.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/storage/storage.dart';

/// 弹幕屏蔽词仓库。
///
/// 直接复用早已开好的 `GStorage.shieldList` 箱（`Box<String>`），键就是规则本身，
/// 因此增删都是 O(1) 且天然去重。
class DanmakuShieldRepository {
  DanmakuShieldRepository({required Box<String> box}) : _box = box;

  /// 全局实例。静态字段懒初始化，首次使用必然晚于 `GStorage.init()`。
  static final DanmakuShieldRepository instance =
      DanmakuShieldRepository(box: GStorage.shieldList);

  final Box<String> _box;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// 规则变更通知（设置页据此刷新列表）。
  Stream<void> get changes => _changes.stream;

  /// 当前全部规则（按写入顺序，过滤空串）。
  List<String> rules() => _box.values.where((rule) => rule.isNotEmpty).toList();

  Future<void> add(String rule) async {
    final trimmed = rule.trim();
    if (validateDanmakuShieldRule(trimmed) != null) return;
    try {
      await _box.put(trimmed, trimmed);
      _changes.add(null);
    } catch (error) {
      WywLogger().w('${LogTag.danmaku} 屏蔽词写入失败', error: error);
    }
  }

  Future<void> remove(String rule) async {
    try {
      await _box.delete(rule);
      _changes.add(null);
    } catch (error) {
      WywLogger().w('${LogTag.danmaku} 屏蔽词删除失败', error: error);
    }
  }

  void dispose() {
    _changes.close();
  }
}
