// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'novel_reader_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$NovelReaderController on _NovelReaderController, Store {
  late final _$chapterAtom =
      Atom(name: '_NovelReaderController.chapter', context: context);

  @override
  int get chapter {
    _$chapterAtom.reportRead();
    return super.chapter;
  }

  @override
  set chapter(int value) {
    _$chapterAtom.reportWrite(value, super.chapter, () {
      super.chapter = value;
    });
  }

  late final _$fontSizeAtom =
      Atom(name: '_NovelReaderController.fontSize', context: context);

  @override
  double get fontSize {
    _$fontSizeAtom.reportRead();
    return super.fontSize;
  }

  @override
  set fontSize(double value) {
    _$fontSizeAtom.reportWrite(value, super.fontSize, () {
      super.fontSize = value;
    });
  }

  late final _$lineHeightAtom =
      Atom(name: '_NovelReaderController.lineHeight', context: context);

  @override
  double get lineHeight {
    _$lineHeightAtom.reportRead();
    return super.lineHeight;
  }

  @override
  set lineHeight(double value) {
    _$lineHeightAtom.reportWrite(value, super.lineHeight, () {
      super.lineHeight = value;
    });
  }

  late final _$modeAtom =
      Atom(name: '_NovelReaderController.mode', context: context);

  @override
  NovelReaderMode get mode {
    _$modeAtom.reportRead();
    return super.mode;
  }

  @override
  set mode(NovelReaderMode value) {
    _$modeAtom.reportWrite(value, super.mode, () {
      super.mode = value;
    });
  }

  late final _$contentAtom =
      Atom(name: '_NovelReaderController.content', context: context);

  @override
  String? get content {
    _$contentAtom.reportRead();
    return super.content;
  }

  @override
  set content(String? value) {
    _$contentAtom.reportWrite(value, super.content, () {
      super.content = value;
    });
  }

  late final _$isLoadingAtom =
      Atom(name: '_NovelReaderController.isLoading', context: context);

  @override
  bool get isLoading {
    _$isLoadingAtom.reportRead();
    return super.isLoading;
  }

  @override
  set isLoading(bool value) {
    _$isLoadingAtom.reportWrite(value, super.isLoading, () {
      super.isLoading = value;
    });
  }

  late final _$jumpToLastOnLoadAtom =
      Atom(name: '_NovelReaderController.jumpToLastOnLoad', context: context);

  @override
  bool get jumpToLastOnLoad {
    _$jumpToLastOnLoadAtom.reportRead();
    return super.jumpToLastOnLoad;
  }

  @override
  set jumpToLastOnLoad(bool value) {
    _$jumpToLastOnLoadAtom.reportWrite(value, super.jumpToLastOnLoad, () {
      super.jumpToLastOnLoad = value;
    });
  }

  late final _$loadedUpToAtom =
      Atom(name: '_NovelReaderController.loadedUpTo', context: context);

  @override
  int get loadedUpTo {
    _$loadedUpToAtom.reportRead();
    return super.loadedUpTo;
  }

  @override
  set loadedUpTo(int value) {
    _$loadedUpToAtom.reportWrite(value, super.loadedUpTo, () {
      super.loadedUpTo = value;
    });
  }

  @override
  String toString() {
    return '''
chapter: ${chapter},
fontSize: ${fontSize},
lineHeight: ${lineHeight},
mode: ${mode},
content: ${content},
isLoading: ${isLoading},
jumpToLastOnLoad: ${jumpToLastOnLoad},
loadedUpTo: ${loadedUpTo}
    ''';
  }
}
