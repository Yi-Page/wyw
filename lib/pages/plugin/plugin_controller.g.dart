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

  late final _$indexCorruptAtom =
      Atom(name: '_PluginController.indexCorrupt', context: context);

  @override
  bool get indexCorrupt {
    _$indexCorruptAtom.reportRead();
    return super.indexCorrupt;
  }

  @override
  set indexCorrupt(bool value) {
    _$indexCorruptAtom.reportWrite(value, super.indexCorrupt, () {
      super.indexCorrupt = value;
    });
  }

  late final _$categoriesAtom =
      Atom(name: '_PluginController.categories', context: context);

  @override
  PluginCategoryRegistry get categories {
    _$categoriesAtom.reportRead();
    return super.categories;
  }

  @override
  set categories(PluginCategoryRegistry value) {
    _$categoriesAtom.reportWrite(value, super.categories, () {
      super.categories = value;
    });
  }

  late final _$pluginNameDisplayAtom =
      Atom(name: '_PluginController.pluginNameDisplay', context: context);

  @override
  String get pluginNameDisplay {
    _$pluginNameDisplayAtom.reportRead();
    return super.pluginNameDisplay;
  }

  @override
  set pluginNameDisplay(String value) {
    _$pluginNameDisplayAtom.reportWrite(value, super.pluginNameDisplay, () {
      super.pluginNameDisplay = value;
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

  late final _$movePluginAsyncAction =
      AsyncAction('_PluginController.movePlugin', context: context);

  @override
  Future<void> movePlugin({required String name, String? beforeName}) {
    return _$movePluginAsyncAction
        .run(() => super.movePlugin(name: name, beforeName: beforeName));
  }

  late final _$addPluginAsyncAction =
      AsyncAction('_PluginController.addPlugin', context: context);

  @override
  Future<PluginCreateResult> addPlugin(Plugin plugin) {
    return _$addPluginAsyncAction.run(() => super.addPlugin(plugin));
  }

  late final _$createAsyncAction =
      AsyncAction('_PluginController.create', context: context);

  @override
  Future<PluginCreateResult> create(String name, String content,
      {bool adoptExistingFile = false}) {
    return _$createAsyncAction.run(() =>
        super.create(name, content, adoptExistingFile: adoptExistingFile));
  }

  late final _$updateItemAsyncAction =
      AsyncAction('_PluginController.updateItem', context: context);

  @override
  Future<PluginOpResult> updateItem(
      {required String name, required String content}) {
    return _$updateItemAsyncAction
        .run(() => super.updateItem(name: name, content: content));
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
  void updatePlugin(Plugin plugin) {
    final _$actionInfo = _$_PluginControllerActionController.startAction(
        name: '_PluginController.updatePlugin');
    try {
      return super.updatePlugin(plugin);
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
indexCorrupt: ${indexCorrupt},
categories: ${categories},
pluginNameDisplay: ${pluginNameDisplay}
    ''';
  }
}
