// ignore_for_file: library_private_types_in_public_api

import 'dart:async';

import 'package:mobx/mobx.dart';
import 'package:wyw/repositories/plugin_history_repository.dart';
import 'package:wyw/services/storage/plugin_history_entry.dart';

part 'plugin_history_controller.g.dart';

/// 浏览历史页面控制器
///
/// **设计要点**：
///   - 仓库通过构造参数注入（不再用 `inject<>` 字段懒求值）
///   - 仓库持 `Stream<void> changes`，controller 订阅并在每次变化时拉取最新数据
///   - 列表展示在 `Observer` 内自动 rebuild
class PluginHistoryController = _PluginHistoryController
    with _$PluginHistoryController;

abstract class _PluginHistoryController with Store {
  _PluginHistoryController(this._repository);

  final PluginHistoryRepository _repository;

  StreamSubscription<void>? _changesSub;

  @observable
  ObservableList<PluginHistoryEntry> histories =
      ObservableList<PluginHistoryEntry>();

  @observable
  bool loading = false;

  @action
  Future<void> init() async {
    _changesSub ??= _repository.changes.listen((_) => refresh());
    await refresh();
  }

  /// 拉取最新数据
  @action
  Future<void> refresh() async {
    loading = true;
    final entries = await _repository.getAll();
    histories
      ..clear()
      ..addAll(entries);
    loading = false;
  }

  @action
  Future<void> remove(PluginHistoryEntry entry) async {
    await _repository.remove(
      pluginName: entry.pluginName,
      id: entry.id,
    );
    // 仓库写入后会通过 changes 流触发 refresh，无需手动同步列表
  }

  /// 撤销删除：条目原样放回（保留原 visitTime），
  /// 仓库 changes 流会触发 refresh 同步列表。
  Future<void> restore(PluginHistoryEntry entry) async {
    await _repository.restore(entry);
  }

  @action
  Future<void> clearAll() async {
    await _repository.clearAll();
  }

  void dispose() {
    _changesSub?.cancel();
    _changesSub = null;
  }
}
