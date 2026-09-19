import 'package:flutter_modular/flutter_modular.dart';
import 'search_page.dart';

final searchModule = createModule(
  path: '/search',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (context, state) => const SearchPage(),
    );
  },
);
