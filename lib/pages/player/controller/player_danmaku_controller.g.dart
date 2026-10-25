// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_danmaku_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$PlayerDanmakuController on _PlayerDanmakuController, Store {
  late final _$danmakuOnAtom =
      Atom(name: '_PlayerDanmakuController.danmakuOn', context: context);

  @override
  bool get danmakuOn {
    _$danmakuOnAtom.reportRead();
    return super.danmakuOn;
  }

  @override
  set danmakuOn(bool value) {
    _$danmakuOnAtom.reportWrite(value, super.danmakuOn, () {
      super.danmakuOn = value;
    });
  }

  late final _$danmakuLoadingAtom =
      Atom(name: '_PlayerDanmakuController.danmakuLoading', context: context);

  @override
  bool get danmakuLoading {
    _$danmakuLoadingAtom.reportRead();
    return super.danmakuLoading;
  }

  @override
  set danmakuLoading(bool value) {
    _$danmakuLoadingAtom.reportWrite(value, super.danmakuLoading, () {
      super.danmakuLoading = value;
    });
  }

  late final _$danmakuEpisodeIdAtom =
      Atom(name: '_PlayerDanmakuController.danmakuEpisodeId', context: context);

  @override
  int get danmakuEpisodeId {
    _$danmakuEpisodeIdAtom.reportRead();
    return super.danmakuEpisodeId;
  }

  @override
  set danmakuEpisodeId(int value) {
    _$danmakuEpisodeIdAtom.reportWrite(value, super.danmakuEpisodeId, () {
      super.danmakuEpisodeId = value;
    });
  }

  late final _$danmakuLibraryTitleAtom = Atom(
      name: '_PlayerDanmakuController.danmakuLibraryTitle', context: context);

  @override
  String get danmakuLibraryTitle {
    _$danmakuLibraryTitleAtom.reportRead();
    return super.danmakuLibraryTitle;
  }

  @override
  set danmakuLibraryTitle(String value) {
    _$danmakuLibraryTitleAtom.reportWrite(value, super.danmakuLibraryTitle, () {
      super.danmakuLibraryTitle = value;
    });
  }

  late final _$_PlayerDanmakuControllerActionController =
      ActionController(name: '_PlayerDanmakuController', context: context);

  @override
  void setDanmakuEnabled(bool value) {
    final _$actionInfo = _$_PlayerDanmakuControllerActionController.startAction(
        name: '_PlayerDanmakuController.setDanmakuEnabled');
    try {
      return super.setDanmakuEnabled(value);
    } finally {
      _$_PlayerDanmakuControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void setDanmakuLoading(bool value) {
    final _$actionInfo = _$_PlayerDanmakuControllerActionController.startAction(
        name: '_PlayerDanmakuController.setDanmakuLoading');
    try {
      return super.setDanmakuLoading(value);
    } finally {
      _$_PlayerDanmakuControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void beginDanmakuLoad() {
    final _$actionInfo = _$_PlayerDanmakuControllerActionController.startAction(
        name: '_PlayerDanmakuController.beginDanmakuLoad');
    try {
      return super.beginDanmakuLoad();
    } finally {
      _$_PlayerDanmakuControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void applyDanmakuLoad(List<DanmakuEntry> danmakus,
      {required int episodeId,
      required String libraryTitle,
      required bool enableDanmaku}) {
    final _$actionInfo = _$_PlayerDanmakuControllerActionController.startAction(
        name: '_PlayerDanmakuController.applyDanmakuLoad');
    try {
      return super.applyDanmakuLoad(danmakus,
          episodeId: episodeId,
          libraryTitle: libraryTitle,
          enableDanmaku: enableDanmaku);
    } finally {
      _$_PlayerDanmakuControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  void applyUnavailableDanmakuLoad(
      {required int episodeId, required String libraryTitle}) {
    final _$actionInfo = _$_PlayerDanmakuControllerActionController.startAction(
        name: '_PlayerDanmakuController.applyUnavailableDanmakuLoad');
    try {
      return super.applyUnavailableDanmakuLoad(
          episodeId: episodeId, libraryTitle: libraryTitle);
    } finally {
      _$_PlayerDanmakuControllerActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
danmakuOn: ${danmakuOn},
danmakuLoading: ${danmakuLoading},
danmakuEpisodeId: ${danmakuEpisodeId},
danmakuLibraryTitle: ${danmakuLibraryTitle}
    ''';
  }
}
