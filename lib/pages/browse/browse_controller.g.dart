// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'browse_controller.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$BrowseController on _BrowseController, Store {
  late final _$categoryPluginsAtom =
      Atom(name: '_BrowseController.categoryPlugins', context: context);

  @override
  List<Plugin> get categoryPlugins {
    _$categoryPluginsAtom.reportRead();
    return super.categoryPlugins;
  }

  @override
  set categoryPlugins(List<Plugin> value) {
    _$categoryPluginsAtom.reportWrite(value, super.categoryPlugins, () {
      super.categoryPlugins = value;
    });
  }

  @override
  String toString() {
    return '''
categoryPlugins: ${categoryPlugins}
    ''';
  }
}
