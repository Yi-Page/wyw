import 'package:flutter/material.dart';

import 'package:wyw/bean/widget/content_section.dart';
import 'package:wyw/bean/widget/empty_state_widget.dart';
import 'package:wyw/modules/danmaku/danmaku_shield_rule.dart';
import 'package:wyw/repositories/danmaku_shield_repository.dart';

/// 屏蔽规则编辑器（设置页与播放器 sheet 共用）。
///
/// 结构与 Kazumi 的 `danmaku_shield_editor.dart` 一致；唯一差异是数据源：
/// Kazumi 走 `MyController`（弹弹play 账号体系，规则可云端同步），
/// wyw 没有账号，改为直接读写本地屏蔽词仓库。
class DanmakuShieldEditor extends StatefulWidget {
  const DanmakuShieldEditor({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(24, 0, 24, 24),
  });

  final EdgeInsetsGeometry padding;

  @override
  State<DanmakuShieldEditor> createState() => _DanmakuShieldEditorState();
}

class _DanmakuShieldEditorState extends State<DanmakuShieldEditor> {
  final DanmakuShieldRepository repository = DanmakuShieldRepository.instance;
  final TextEditingController textEditingController = TextEditingController();

  @override
  void dispose() {
    textEditingController.dispose();
    super.dispose();
  }

  Future<void> _addRule() async {
    final rule = textEditingController.text.trim();
    if (rule.isEmpty) return;
    if (validateDanmakuShieldRule(rule) != null) return;
    await repository.add(rule);
    if (mounted && textEditingController.text.trim() == rule) {
      textEditingController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: widget.padding,
      children: [
        ContentSection(
          title: '添加规则',
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: textEditingController,
              decoration: InputDecoration(
                hintText: '关键词或 /正则表达式/',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                suffixIcon: IconButton(
                  tooltip: '添加规则',
                  onPressed: _addRule,
                  icon: const Icon(Icons.add_rounded),
                ),
              ),
              onSubmitted: (_) => _addRule(),
            ),
            const SizedBox(height: 8),
            Text('包含关键词的弹幕会被隐藏。用 / / 包裹正则表达式。',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ]),
        ),
        const SizedBox(height: 24),
        StreamBuilder<void>(
          stream: repository.changes,
          builder: (context, _) {
            final rules = repository.rules();
            if (rules.isEmpty) {
              return const GeneralEmptyState(
                icon: Icons.filter_alt_off_rounded,
                title: '还没有屏蔽规则',
                compact: true,
              );
            }
            return ContentSection.group(
              title: '已添加 · ${rules.length}',
              children: [
                for (final rule in rules)
                  ListTile(
                    title: Text(rule),
                    subtitle: rule.startsWith('/') && rule.endsWith('/')
                        ? const Text('正则表达式')
                        : null,
                    trailing: IconButton(
                      tooltip: '删除规则',
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => repository.remove(rule),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
