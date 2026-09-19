import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/core_module.dart';
import 'package:wyw/pages/index_module.dart';

final appModule = createModule(
  register: (c) {
    c
      ..module(coreModule)
      ..module(indexModule);
  },
);
