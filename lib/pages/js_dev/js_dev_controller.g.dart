// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'js_dev_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$JsDevController on _JsDevController, Store {
  late final _$linesAtom =
      Atom(name: '_JsDevController.lines', context: context);

  @override
  ObservableList<JsLogLine> get lines {
    _$linesAtom.reportRead();
    return super.lines;
  }

  @override
  set lines(ObservableList<JsLogLine> value) {
    _$linesAtom.reportWrite(value, super.lines, () {
      super.lines = value;
    });
  }

  late final _$runningAtom =
      Atom(name: '_JsDevController.running', context: context);

  @override
  bool get running {
    _$runningAtom.reportRead();
    return super.running;
  }

  @override
  set running(bool value) {
    _$runningAtom.reportWrite(value, super.running, () {
      super.running = value;
    });
  }

  @override
  String toString() {
    return '''
lines: ${lines},
running: ${running}
    ''';
  }
}
