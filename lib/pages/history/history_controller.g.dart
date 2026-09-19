// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'history_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$HistoryController on _HistoryController, Store {
  late final _$historiesAtom =
      Atom(name: '_HistoryController.histories', context: context);

  @override
  ObservableList<HistoryEntry> get histories {
    _$historiesAtom.reportRead();
    return super.histories;
  }

  @override
  set histories(ObservableList<HistoryEntry> value) {
    _$historiesAtom.reportWrite(value, super.histories, () {
      super.histories = value;
    });
  }

  late final _$removeAsyncAction =
      AsyncAction('_HistoryController.remove', context: context);

  @override
  Future<void> remove(HistoryEntry entry) {
    return _$removeAsyncAction.run(() => super.remove(entry));
  }

  late final _$clearAllAsyncAction =
      AsyncAction('_HistoryController.clearAll', context: context);

  @override
  Future<void> clearAll() {
    return _$clearAllAsyncAction.run(() => super.clearAll());
  }

  late final _$_HistoryControllerActionController =
      ActionController(name: '_HistoryController', context: context);

  @override
  void init() {
    final _$actionInfo = _$_HistoryControllerActionController.startAction(
        name: '_HistoryController.init');
    try {
      return super.init();
    } finally {
      _$_HistoryControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  HistoryEntry? findBySource(HistoryType type, String sourceId) {
    final _$actionInfo = _$_HistoryControllerActionController.startAction(
        name: '_HistoryController.findBySource');
    try {
      return super.findBySource(type, sourceId);
    } finally {
      _$_HistoryControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
histories: ${histories}
    ''';
  }
}
