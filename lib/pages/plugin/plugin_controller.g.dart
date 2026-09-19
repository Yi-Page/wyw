// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plugin_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$PluginController on _PluginController, Store {
  late final _$pluginsAtom =
      Atom(name: '_PluginController.plugins', context: context);

  @override
  ObservableList<Plugin> get plugins {
    _$pluginsAtom.reportRead();
    return super.plugins;
  }

  @override
  set plugins(ObservableList<Plugin> value) {
    _$pluginsAtom.reportWrite(value, super.plugins, () {
      super.plugins = value;
    });
  }

  late final _$initializedAtom =
      Atom(name: '_PluginController.initialized', context: context);

  @override
  bool get initialized {
    _$initializedAtom.reportRead();
    return super.initialized;
  }

  @override
  set initialized(bool value) {
    _$initializedAtom.reportWrite(value, super.initialized, () {
      super.initialized = value;
    });
  }

  late final _$loadingAtom =
      Atom(name: '_PluginController.loading', context: context);

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

  late final _$lastErrorAtom =
      Atom(name: '_PluginController.lastError', context: context);

  @override
  String? get lastError {
    _$lastErrorAtom.reportRead();
    return super.lastError;
  }

  @override
  set lastError(String? value) {
    _$lastErrorAtom.reportWrite(value, super.lastError, () {
      super.lastError = value;
    });
  }

  late final _$selectedPluginNameAtom =
      Atom(name: '_PluginController.selectedPluginName', context: context);

  @override
  String? get selectedPluginName {
    _$selectedPluginNameAtom.reportRead();
    return super.selectedPluginName;
  }

  @override
  set selectedPluginName(String? value) {
    _$selectedPluginNameAtom.reportWrite(value, super.selectedPluginName, () {
      super.selectedPluginName = value;
    });
  }

  late final _$initAsyncAction =
      AsyncAction('_PluginController.init', context: context);

  @override
  Future<void> init() {
    return _$initAsyncAction.run(() => super.init());
  }

  late final _$rescanAsyncAction =
      AsyncAction('_PluginController.rescan', context: context);

  @override
  Future<void> rescan() {
    return _$rescanAsyncAction.run(() => super.rescan());
  }

  late final _$addItemFromPathAsyncAction =
      AsyncAction('_PluginController.addItemFromPath', context: context);

  @override
  Future<bool> addItemFromPath({required String filePath}) {
    return _$addItemFromPathAsyncAction
        .run(() => super.addItemFromPath(filePath: filePath));
  }

  late final _$createAsyncAction =
      AsyncAction('_PluginController.create', context: context);

  @override
  Future<Plugin?> create(String name, String content) {
    return _$createAsyncAction.run(() => super.create(name, content));
  }

  late final _$updateItemAsyncAction =
      AsyncAction('_PluginController.updateItem', context: context);

  @override
  Future<bool> updateItem({required String name, required String content}) {
    return _$updateItemAsyncAction
        .run(() => super.updateItem(name: name, content: content));
  }

  late final _$removeItemAsyncAction =
      AsyncAction('_PluginController.removeItem', context: context);

  @override
  Future<bool> removeItem(String name) {
    return _$removeItemAsyncAction.run(() => super.removeItem(name));
  }

  late final _$openBrowseEntryAsyncAction =
      AsyncAction('_PluginController.openBrowseEntry', context: context);

  @override
  Future<bool> openBrowseEntry(
      {required String pluginName, required Map<String, dynamic> entryJson}) {
    return _$openBrowseEntryAsyncAction.run(() =>
        super.openBrowseEntry(pluginName: pluginName, entryJson: entryJson));
  }

  late final _$_PluginControllerActionController =
      ActionController(name: '_PluginController', context: context);

  @override
  void reorder(int oldIndex, int newIndex) {
    final _$actionInfo = _$_PluginControllerActionController.startAction(
        name: '_PluginController.reorder');
    try {
      return super.reorder(oldIndex, newIndex);
    } finally {
      _$_PluginControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void select(String? name) {
    final _$actionInfo = _$_PluginControllerActionController.startAction(
        name: '_PluginController.select');
    try {
      return super.select(name);
    } finally {
      _$_PluginControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
plugins: ${plugins},
initialized: ${initialized},
loading: ${loading},
lastError: ${lastError},
selectedPluginName: ${selectedPluginName}
    ''';
  }
}
