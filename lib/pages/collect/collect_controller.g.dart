// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collect_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$CollectController on _CollectController, Store {
  late final _$entriesAtom =
      Atom(name: '_CollectController.entries', context: context);

  @override
  ObservableList<CollectEntry> get entries {
    _$entriesAtom.reportRead();
    return super.entries;
  }

  @override
  set entries(ObservableList<CollectEntry> value) {
    _$entriesAtom.reportWrite(value, super.entries, () {
      super.entries = value;
    });
  }

  late final _$loadingAtom =
      Atom(name: '_CollectController.loading', context: context);

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

  late final _$queryAtom =
      Atom(name: '_CollectController.query', context: context);

  @override
  String get query {
    _$queryAtom.reportRead();
    return super.query;
  }

  @override
  set query(String value) {
    _$queryAtom.reportWrite(value, super.query, () {
      super.query = value;
    });
  }

  late final _$selectedTypeAtom =
      Atom(name: '_CollectController.selectedType', context: context);

  @override
  CollectType? get selectedType {
    _$selectedTypeAtom.reportRead();
    return super.selectedType;
  }

  @override
  set selectedType(CollectType? value) {
    _$selectedTypeAtom.reportWrite(value, super.selectedType, () {
      super.selectedType = value;
    });
  }

  late final _$sortAtom =
      Atom(name: '_CollectController.sort', context: context);

  @override
  CollectSort get sort {
    _$sortAtom.reportRead();
    return super.sort;
  }

  @override
  set sort(CollectSort value) {
    _$sortAtom.reportWrite(value, super.sort, () {
      super.sort = value;
    });
  }

  late final _$initAsyncAction =
      AsyncAction('_CollectController.init', context: context);

  @override
  Future<void> init() {
    return _$initAsyncAction.run(() => super.init());
  }

  late final _$refreshAsyncAction =
      AsyncAction('_CollectController.refresh', context: context);

  @override
  Future<void> refresh() {
    return _$refreshAsyncAction.run(() => super.refresh());
  }

  late final _$setCollectTypeAsyncAction =
      AsyncAction('_CollectController.setCollectType', context: context);

  @override
  Future<void> setCollectType(CollectEntry entry, CollectType type) {
    return _$setCollectTypeAsyncAction
        .run(() => super.setCollectType(entry, type));
  }

  late final _$removeAsyncAction =
      AsyncAction('_CollectController.remove', context: context);

  @override
  Future<void> remove(CollectEntry entry) {
    return _$removeAsyncAction.run(() => super.remove(entry));
  }

  late final _$setCollectTypeBatchAsyncAction =
      AsyncAction('_CollectController.setCollectTypeBatch', context: context);

  @override
  Future<void> setCollectTypeBatch(
      Iterable<CollectEntry> targets, CollectType type) {
    return _$setCollectTypeBatchAsyncAction
        .run(() => super.setCollectTypeBatch(targets, type));
  }

  late final _$removeBatchAsyncAction =
      AsyncAction('_CollectController.removeBatch', context: context);

  @override
  Future<void> removeBatch(Iterable<CollectEntry> targets) {
    return _$removeBatchAsyncAction.run(() => super.removeBatch(targets));
  }

  late final _$clearAllAsyncAction =
      AsyncAction('_CollectController.clearAll', context: context);

  @override
  Future<void> clearAll() {
    return _$clearAllAsyncAction.run(() => super.clearAll());
  }

  late final _$clearUncollectedAsyncAction =
      AsyncAction('_CollectController.clearUncollected', context: context);

  @override
  Future<void> clearUncollected() {
    return _$clearUncollectedAsyncAction.run(() => super.clearUncollected());
  }

  late final _$_CollectControllerActionController =
      ActionController(name: '_CollectController', context: context);

  @override
  void setQuery(String value) {
    final _$actionInfo = _$_CollectControllerActionController.startAction(
        name: '_CollectController.setQuery');
    try {
      return super.setQuery(value);
    } finally {
      _$_CollectControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void setType(CollectType? type) {
    final _$actionInfo = _$_CollectControllerActionController.startAction(
        name: '_CollectController.setType');
    try {
      return super.setType(type);
    } finally {
      _$_CollectControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void setSort(CollectSort value) {
    final _$actionInfo = _$_CollectControllerActionController.startAction(
        name: '_CollectController.setSort');
    try {
      return super.setSort(value);
    } finally {
      _$_CollectControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
entries: ${entries},
loading: ${loading},
query: ${query},
selectedType: ${selectedType},
sort: ${sort}
    ''';
  }
}
