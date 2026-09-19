// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'comic_reader_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$ComicReaderController on _ComicReaderController, Store {
  late final _$chapterAtom =
      Atom(name: '_ComicReaderController.chapter', context: context);

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

  late final _$pageAtom =
      Atom(name: '_ComicReaderController.page', context: context);

  @override
  int get page {
    _$pageAtom.reportRead();
    return super.page;
  }

  @override
  set page(int value) {
    _$pageAtom.reportWrite(value, super.page, () {
      super.page = value;
    });
  }

  late final _$modeAtom =
      Atom(name: '_ComicReaderController.mode', context: context);

  @override
  ComicReaderMode get mode {
    _$modeAtom.reportRead();
    return super.mode;
  }

  @override
  set mode(ComicReaderMode value) {
    _$modeAtom.reportWrite(value, super.mode, () {
      super.mode = value;
    });
  }

  late final _$imagesAtom =
      Atom(name: '_ComicReaderController.images', context: context);

  @override
  List<String>? get images {
    _$imagesAtom.reportRead();
    return super.images;
  }

  @override
  set images(List<String>? value) {
    _$imagesAtom.reportWrite(value, super.images, () {
      super.images = value;
    });
  }

  late final _$isLoadingAtom =
      Atom(name: '_ComicReaderController.isLoading', context: context);

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

  late final _$jumpToLastPageOnLoadAtom = Atom(
      name: '_ComicReaderController.jumpToLastPageOnLoad', context: context);

  @override
  bool get jumpToLastPageOnLoad {
    _$jumpToLastPageOnLoadAtom.reportRead();
    return super.jumpToLastPageOnLoad;
  }

  @override
  set jumpToLastPageOnLoad(bool value) {
    _$jumpToLastPageOnLoadAtom.reportWrite(value, super.jumpToLastPageOnLoad,
        () {
      super.jumpToLastPageOnLoad = value;
    });
  }

  late final _$portraitAtom =
      Atom(name: '_ComicReaderController.portrait', context: context);

  @override
  bool get portrait {
    _$portraitAtom.reportRead();
    return super.portrait;
  }

  @override
  set portrait(bool value) {
    _$portraitAtom.reportWrite(value, super.portrait, () {
      super.portrait = value;
    });
  }

  @override
  String toString() {
    return '''
chapter: ${chapter},
page: ${page},
mode: ${mode},
images: ${images},
isLoading: ${isLoading},
jumpToLastPageOnLoad: ${jumpToLastPageOnLoad},
portrait: ${portrait}
    ''';
  }
}
