// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'search_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$SearchPageController on _SearchPageController, Store {
  late final _$keywordAtom =
      Atom(name: '_SearchPageController.keyword', context: context);

  @override
  String get keyword {
    _$keywordAtom.reportRead();
    return super.keyword;
  }

  @override
  set keyword(String value) {
    _$keywordAtom.reportWrite(value, super.keyword, () {
      super.keyword = value;
    });
  }

  late final _$activeTabKeyAtom =
      Atom(name: '_SearchPageController.activeTabKey', context: context);

  @override
  String? get activeTabKey {
    _$activeTabKeyAtom.reportRead();
    return super.activeTabKey;
  }

  @override
  set activeTabKey(String? value) {
    _$activeTabKeyAtom.reportWrite(value, super.activeTabKey, () {
      super.activeTabKey = value;
    });
  }

  late final _$recentKeywordsAtom =
      Atom(name: '_SearchPageController.recentKeywords', context: context);

  @override
  List<String> get recentKeywords {
    _$recentKeywordsAtom.reportRead();
    return super.recentKeywords;
  }

  @override
  set recentKeywords(List<String> value) {
    _$recentKeywordsAtom.reportWrite(value, super.recentKeywords, () {
      super.recentKeywords = value;
    });
  }

  late final _$tabStatesAtom =
      Atom(name: '_SearchPageController.tabStates', context: context);

  @override
  ObservableMap<String, SearchState> get tabStates {
    _$tabStatesAtom.reportRead();
    return super.tabStates;
  }

  @override
  set tabStates(ObservableMap<String, SearchState> value) {
    _$tabStatesAtom.reportWrite(value, super.tabStates, () {
      super.tabStates = value;
    });
  }

  late final _$initAsyncAction =
      AsyncAction('_SearchPageController.init', context: context);

  @override
  Future<void> init() {
    return _$initAsyncAction.run(() => super.init());
  }

  late final _$submitSearchAsyncAction =
      AsyncAction('_SearchPageController.submitSearch', context: context);

  @override
  Future<void> submitSearch(String keyword, {List<String>? pluginNames}) {
    return _$submitSearchAsyncAction
        .run(() => super.submitSearch(keyword, pluginNames: pluginNames));
  }

  late final _$searchAllAsyncAction =
      AsyncAction('_SearchPageController.searchAll', context: context);

  @override
  Future<void> searchAll(String keyword, List<String> pluginNames) {
    return _$searchAllAsyncAction
        .run(() => super.searchAll(keyword, pluginNames));
  }

  late final _$searchAsyncAction =
      AsyncAction('_SearchPageController.search', context: context);

  @override
  Future<void> search(String pluginName, String keyword) {
    return _$searchAsyncAction.run(() => super.search(pluginName, keyword));
  }

  late final _$loadMoreAsyncAction =
      AsyncAction('_SearchPageController.loadMore', context: context);

  @override
  Future<void> loadMore(String pluginName) {
    return _$loadMoreAsyncAction.run(() => super.loadMore(pluginName));
  }

  late final _$_SearchPageControllerActionController =
      ActionController(name: '_SearchPageController', context: context);

  @override
  void setKeyword(String k) {
    final _$actionInfo = _$_SearchPageControllerActionController.startAction(
        name: '_SearchPageController.setKeyword');
    try {
      return super.setKeyword(k);
    } finally {
      _$_SearchPageControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void removeRecentKeyword(String k) {
    final _$actionInfo = _$_SearchPageControllerActionController.startAction(
        name: '_SearchPageController.removeRecentKeyword');
    try {
      return super.removeRecentKeyword(k);
    } finally {
      _$_SearchPageControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void clearRecentKeywords() {
    final _$actionInfo = _$_SearchPageControllerActionController.startAction(
        name: '_SearchPageController.clearRecentKeywords');
    try {
      return super.clearRecentKeywords();
    } finally {
      _$_SearchPageControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
keyword: ${keyword},
activeTabKey: ${activeTabKey},
recentKeywords: ${recentKeywords},
tabStates: ${tabStates}
    ''';
  }
}
