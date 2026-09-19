import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/pages/download/download_page_module.dart';
import 'package:wyw/pages/comic_reader/comic_reader_settings_page.dart';
import 'package:wyw/pages/logs/logs_page.dart';
import 'package:wyw/pages/plugin/plugin_module.dart';
import 'package:wyw/pages/settings/displaymode_settings.dart';
import 'package:wyw/pages/settings/download_settings.dart';
import 'package:wyw/pages/settings/interface_settings.dart';
import 'package:wyw/pages/settings/keyboard_settings.dart';
import 'package:wyw/pages/settings/decoder_settings.dart';
import 'package:wyw/pages/settings/player_settings.dart';
import 'package:wyw/pages/settings/renderer_settings.dart';
import 'package:wyw/pages/settings/settings_page.dart';
import 'package:wyw/pages/settings/super_resolution_settings.dart';
import 'package:wyw/pages/settings/theme_settings_page.dart';

final settingsModule = createModule(
  path: '/settings',
  register: (c) {
    c
      ..route('/', child: (context, state) => const SettingsPage())
      ..route('/theme', child: (context, state) => const ThemeSettingsPage())
      ..route(
        '/theme/display',
        child: (context, state) => const SetDisplayMode(),
      )
      ..route(
        '/keyboard',
        child: (context, state) => const KeyboardSettingsPage(),
      )
      ..route('/player', child: (context, state) => const PlayerSettingsPage())
      ..route(
        '/player/decoder',
        child: (context, state) => const DecoderSettings(),
      )
      ..route(
        '/player/renderer',
        child: (context, state) => const RendererSettings(),
      )
      ..route(
        '/interface',
        child: (context, state) => const InterfaceSettingsPage(),
      )
      ..route(
        '/player/super',
        child: (context, state) => const SuperResolutionSettings(),
      )
      ..route('/logs', child: (context, state) => const LogsPage())
      ..route('/comic-reader',
          child: (context, state) => const ComicReaderSettingsPage())
      ..module(downloadPageModule)
      ..route(
        '/download-settings',
        child: (context, state) => const DownloadSettingsPage(),
      )
      ..module(pluginModule);
  },
);
