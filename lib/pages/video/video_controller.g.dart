// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'video_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$VideoPageController on _VideoPageController, Store {
  late final _$loadingAtom =
      Atom(name: '_VideoPageController.loading', context: context);

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

  late final _$errorMessageAtom =
      Atom(name: '_VideoPageController.errorMessage', context: context);

  @override
  String? get errorMessage {
    _$errorMessageAtom.reportRead();
    return super.errorMessage;
  }

  @override
  set errorMessage(String? value) {
    _$errorMessageAtom.reportWrite(value, super.errorMessage, () {
      super.errorMessage = value;
    });
  }

  late final _$isFullscreenAtom =
      Atom(name: '_VideoPageController.isFullscreen', context: context);

  @override
  bool get isFullscreen {
    _$isFullscreenAtom.reportRead();
    return super.isFullscreen;
  }

  @override
  set isFullscreen(bool value) {
    _$isFullscreenAtom.reportWrite(value, super.isFullscreen, () {
      super.isFullscreen = value;
    });
  }

  late final _$isOrientationLockedAtom =
      Atom(name: '_VideoPageController.isOrientationLocked', context: context);

  @override
  bool get isOrientationLocked {
    _$isOrientationLockedAtom.reportRead();
    return super.isOrientationLocked;
  }

  @override
  set isOrientationLocked(bool value) {
    _$isOrientationLockedAtom.reportWrite(value, super.isOrientationLocked, () {
      super.isOrientationLocked = value;
    });
  }

  late final _$isCommentsAscendingAtom =
      Atom(name: '_VideoPageController.isCommentsAscending', context: context);

  @override
  bool get isCommentsAscending {
    _$isCommentsAscendingAtom.reportRead();
    return super.isCommentsAscending;
  }

  @override
  set isCommentsAscending(bool value) {
    _$isCommentsAscendingAtom.reportWrite(value, super.isCommentsAscending, () {
      super.isCommentsAscending = value;
    });
  }

  late final _$isPipAtom =
      Atom(name: '_VideoPageController.isPip', context: context);

  @override
  bool get isPip {
    _$isPipAtom.reportRead();
    return super.isPip;
  }

  @override
  set isPip(bool value) {
    _$isPipAtom.reportWrite(value, super.isPip, () {
      super.isPip = value;
    });
  }

  late final _$isOfflineModeAtom =
      Atom(name: '_VideoPageController.isOfflineMode', context: context);

  @override
  bool get isOfflineMode {
    _$isOfflineModeAtom.reportRead();
    return super.isOfflineMode;
  }

  @override
  set isOfflineMode(bool value) {
    _$isOfflineModeAtom.reportWrite(value, super.isOfflineMode, () {
      super.isOfflineMode = value;
    });
  }

  @override
  String toString() {
    return '''
loading: ${loading},
errorMessage: ${errorMessage},
isFullscreen: ${isFullscreen},
isOrientationLocked: ${isOrientationLocked},
isCommentsAscending: ${isCommentsAscending},
isPip: ${isPip},
isOfflineMode: ${isOfflineMode}
    ''';
  }
}
