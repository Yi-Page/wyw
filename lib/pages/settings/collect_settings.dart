import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/bean/settings/settings_detail_scaffold.dart';
import 'package:wyw/bean/settings/settings_list.dart';
import 'package:wyw/bean/widget/select_field.dart';
import 'package:wyw/repositories/collect_repository.dart';
import 'package:wyw/services/storage/collect_type.dart';
import 'package:wyw/services/storage/storage.dart';

/// 收藏设置页。
///
/// 两项：
///   - **进入时的默认页签**（全部 / 未收藏 / 5 个收藏状态）
///   - **未收藏条目的保留上限**（自定义最大条数 / 无上限）
///
/// 已收藏的条目永不参与自动清理。
class CollectSettingsPage extends StatefulWidget {
  const CollectSettingsPage({super.key});

  @override
  State<CollectSettingsPage> createState() => _CollectSettingsPageState();
}

class _CollectSettingsPageState extends State<CollectSettingsPage> {
  CollectRepository get _repository => inject<CollectRepository>();

  /// 页签选项：顺序与收藏页的 tab 一致（全部、未收藏、在看、想看、看过、搁置、抛弃）。
  static final List<SelectOption<int>> _tabOptions = [
    const SelectOption(value: -1, label: '全部'),
    for (final type in const <CollectType>[
      CollectType.none,
      CollectType.watching,
      CollectType.planToWatch,
      CollectType.watched,
      CollectType.onHold,
      CollectType.abandoned,
    ])
      SelectOption(value: type.value, label: type.label),
  ];

  late int _limit;
  late int _defaultTab;

  @override
  void initState() {
    super.initState();
    _limit = GStorage.getSetting(SettingsKeys.uncollectedLimit);
    _defaultTab = GStorage.getSetting(SettingsKeys.collectDefaultTab);
  }

  String get _limitLabel => _limit <= 0 ? '无上限' : '$_limit 条';

  void _updateDefaultTab(int value) {
    GStorage.putSetting(SettingsKeys.collectDefaultTab, value);
    setState(() => _defaultTab = value);
  }

  Future<void> _editLimit() async {
    final controller = TextEditingController(
      text: _limit <= 0 ? '' : '$_limit',
    );
    final value = await WywDialog.show<int>(
      builder: (dialogContext) => AlertDialog(
        title: const Text('未收藏记录上限'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('超出上限时，按最近访问时间最旧优先自动清理。'),
            const SizedBox(height: 4),
            const Text('已收藏的条目永不自动清理。'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: '最大条数',
                hintText: '留空或 0 表示无上限',
              ),
              onSubmitted: (v) => WywDialog.dismiss(
                popWith: int.tryParse(v.trim()) ?? 0,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: WywDialog.dismiss,
            child: Text(
              '取消',
              style: TextStyle(
                color: Theme.of(dialogContext).colorScheme.outline,
              ),
            ),
          ),
          TextButton(
            onPressed: () => WywDialog.dismiss(
              popWith: int.tryParse(controller.text.trim()) ?? 0,
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (value == null || !mounted) return;
    final normalized = value < 0 ? 0 : value;
    await GStorage.putSetting(SettingsKeys.uncollectedLimit, normalized);
    final removed = await _repository.enforceUncollectedLimit();
    if (!mounted) return;
    setState(() => _limit = normalized);
    WywDialog.showToast(
      message: removed > 0
          ? '已保存：${normalized <= 0 ? '无上限' : '$normalized 条'}，清理了 $removed 条未收藏记录'
          : '已保存：${normalized <= 0 ? '无上限' : '$normalized 条'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('收藏设置'),
      body: SettingsList(
        sections: [
          SettingsSection(
            title: const Text('页面'),
            tiles: [
              SelectTile<int>(
                leading: Icons.tab_rounded,
                title: const Text('进入时的默认页签'),
                description: const Text('打开收藏页时默认停在哪个分类'),
                value: _defaultTab,
                placeholder: '全部',
                options: _tabOptions,
                onChanged: _updateDefaultTab,
              ),
            ],
          ),
          SettingsSection(
            title: const Text('浏览记录'),
            tiles: [
              SettingsTile(
                leading: Icons.cleaning_services_rounded,
                title: const Text('未收藏记录上限'),
                description: const Text(
                    '超出上限时按最近访问时间最旧优先自动清理；已收藏的条目永不自动清理'),
                value: Text(_limitLabel),
                onPressed: (_) => _editLimit(),
              ),
            ],
            bottomInfo: const Text(
                '「未收藏」是浏览记录的默认状态：插件收录一条作品足迹时即为未收藏。'),
          ),
        ],
      ),
    );
  }
}
