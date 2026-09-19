import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:wyw/bean/settings/settings_detail_scaffold.dart';
import 'package:wyw/bean/settings/settings_list.dart';
import 'package:wyw/bean/widget/loading_indicator.dart';
import 'package:wyw/services/storage/storage.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/services/logging/log_tags.dart';

class SetDisplayMode extends StatefulWidget {
  const SetDisplayMode({super.key});

  @override
  State<SetDisplayMode> createState() => _SetDisplayModeState();
}

class _SetDisplayModeState extends State<SetDisplayMode> {
  List<DisplayMode> modes = <DisplayMode>[];
  DisplayMode? active;
  DisplayMode? preferred;

  final ValueNotifier<int> page = ValueNotifier<int>(0);
  late final PageController controller = PageController()
    ..addListener(() {
      page.value = controller.page!.round();
    });

  @override
  void initState() {
    super.initState();
    init();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      fetchAll();
    });
  }

  Future<void> fetchAll() async {
    preferred = await FlutterDisplayMode.preferred;
    active = await FlutterDisplayMode.active;
    await GStorage.putSetting(SettingsKeys.displayMode, preferred.toString());
    setState(() {});
  }

  Future<void> init() async {
    try {
      modes = await FlutterDisplayMode.supported;
    } on PlatformException catch (e) {
      WywLogger().d('${LogTag.platform} 获取支持的屏幕刷新率失败（已忽略）', error: e);
    }
    var res = await getDisplayModeType(modes);

    preferred = modes.toList().firstWhere((el) => el == res);
    FlutterDisplayMode.setPreferredMode(preferred!);
  }

  Future<DisplayMode> getDisplayModeType(List<DisplayMode> modes) async {
    var value = GStorage.getSetting(SettingsKeys.displayMode);
    DisplayMode f = DisplayMode.auto;
    if (value != null) {
      f = modes.firstWhere((e) => e.toString() == value);
    }
    return f;
  }

  @override
  void dispose() {
    controller.dispose();
    page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('屏幕帧率设置'),
      body: (modes.isEmpty)
          ? const Center(child: LoadingIndicator())
          : SettingsList(
              sections: [
                SettingsRadioSection<DisplayMode>(
                  title: const Text('没有生效? 重启app试试'),
                  groupValue: preferred,
                  onChanged: (DisplayMode? newMode) async {
                    if (newMode == null) return;
                    await FlutterDisplayMode.setPreferredMode(newMode);
                    await Future<dynamic>.delayed(
                      const Duration(milliseconds: 100),
                    );
                    await fetchAll();
                  },
                  tiles: [
                    for (final e in modes)
                      SettingsTile<DisplayMode>.radioTile(
                        title: e == DisplayMode.auto
                            ? const Text('自动')
                            : Text('$e${e == active ? "  [系统]" : ""}'),
                        radioValue: e,
                      ),
                  ],
                ),
              ],
            ),
    );
  }
}
