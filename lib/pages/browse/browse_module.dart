import 'package:flutter_modular/flutter_modular.dart';
import 'browse_page.dart';

final browseModule = createModule(
  path: '/browse',
  register: (c) {
    c.route(
      '/',
      transition: TransitionType.none,
      child: (context, state) => const BrowsePage(),
    );
  },
);
