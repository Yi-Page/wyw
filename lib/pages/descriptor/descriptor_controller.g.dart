// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'descriptor_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$DescriptorController on _DescriptorController, Store {
  late final _$cardsAtom =
      Atom(name: '_DescriptorController.cards', context: context);

  @override
  List<Widget>? get cards {
    _$cardsAtom.reportRead();
    return super.cards;
  }

  @override
  set cards(List<Widget>? value) {
    _$cardsAtom.reportWrite(value, super.cards, () {
      super.cards = value;
    });
  }

  late final _$errorAtom =
      Atom(name: '_DescriptorController.error', context: context);

  @override
  String? get error {
    _$errorAtom.reportRead();
    return super.error;
  }

  @override
  set error(String? value) {
    _$errorAtom.reportWrite(value, super.error, () {
      super.error = value;
    });
  }

  late final _$loadingAtom =
      Atom(name: '_DescriptorController.loading', context: context);

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

  @override
  String toString() {
    return '''
cards: ${cards},
error: ${error},
loading: ${loading}
    ''';
  }
}
