// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plugin_history_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$PluginHistoryController on _PluginHistoryController, Store {
  late final _$historiesAtom =
      Atom(name: '_PluginHistoryController.histories', context: context);

  @override
  ObservableList<PluginHistoryEntry> get histories {
    _$historiesAtom.reportRead();
    return super.histories;
  }

  @override
  set histories(ObservableList<PluginHistoryEntry> value) {
    _$historiesAtom.reportWrite(value, super.histories, () {
      super.histories = value;
    });
  }

  late final _$loadingAtom =
      Atom(name: '_PluginHistoryController.loading', context: context);

  @override
  bool get loading {
    _$loadingAtom.reportRead();
    return super.loading;
  }

  @override
  set loading(bool value) {
    _$loadingAtom.reportWrite(value, super.loading, () {
      super.loading = value;
    });
  }

  late final _$initAsyncAction =
      AsyncAction('_PluginHistoryController.init', context: context);

  @override
  Future<void> init() {
    return _$initAsyncAction.run(() => super.init());
  }

  late final _$refreshAsyncAction =
      AsyncAction('_PluginHistoryController.refresh', context: context);

  @override
  Future<void> refresh() {
    return _$refreshAsyncAction.run(() => super.refresh());
  }

  late final _$removeAsyncAction =
      AsyncAction('_PluginHistoryController.remove', context: context);

  @override
  Future<void> remove(PluginHistoryEntry entry) {
    return _$removeAsyncAction.run(() => super.remove(entry));
  }

  late final _$clearAllAsyncAction =
      AsyncAction('_PluginHistoryController.clearAll', context: context);

  @override
  Future<void> clearAll() {
    return _$clearAllAsyncAction.run(() => super.clearAll());
  }

  @override
  String toString() {
    return '''
histories: ${histories},
loading: ${loading}
    ''';
  }
}
