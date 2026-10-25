import 'package:flutter/material.dart';

import 'package:wyw/bean/settings/settings_detail_scaffold.dart';
import 'package:wyw/pages/settings/danmaku/danmaku_shield_editor.dart';

class DanmakuShieldSettings extends StatelessWidget {
  const DanmakuShieldSettings({super.key});

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
        title: const Text('屏蔽规则'),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: const DanmakuShieldEditor(
              padding: EdgeInsets.all(16),
            ),
          ),
        ),
      );
}
