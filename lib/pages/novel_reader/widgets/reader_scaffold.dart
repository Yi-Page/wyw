part of 'novel_reader.dart';

/// 设置面板：阅读方式 / 字号 / 行距。
class _NovelReaderSettingsPanel extends StatefulWidget {
  const _NovelReaderSettingsPanel({required this.controller});

  final NovelReaderController controller;

  @override
  State<_NovelReaderSettingsPanel> createState() =>
      _NovelReaderSettingsPanelState();
}

class _NovelReaderSettingsPanelState extends State<_NovelReaderSettingsPanel> {
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('阅读设置', style: TextStyle(fontSize: 18)),
            ),
            ListTile(
              title: const Text('阅读方式'),
              trailing: SegmentedButton<NovelReaderMode>(
                segments: const [
                  ButtonSegment(
                    value: NovelReaderMode.scroll,
                    icon: Icon(Icons.swap_vert),
                    label: Text('滚动'),
                  ),
                  ButtonSegment(
                    value: NovelReaderMode.page,
                    icon: Icon(Icons.swipe),
                    label: Text('翻页'),
                  ),
                ],
                selected: {widget.controller.mode},
                onSelectionChanged: (s) {
                  widget.controller.setMode(s.first);
                  setState(() {});
                },
              ),
            ),
            ListTile(
              title: const Text('字号'),
              subtitle: Slider(
                value: widget.controller.fontSize.clamp(12, 32),
                min: 12,
                max: 32,
                divisions: 20,
                label: widget.controller.fontSize.toStringAsFixed(0),
                onChanged: (v) {
                  widget.controller.setFontSize(v);
                  setState(() {});
                },
              ),
            ),
            ListTile(
              title: const Text('行距'),
              subtitle: Slider(
                value: widget.controller.lineHeight.clamp(1.2, 2.4),
                min: 1.2,
                max: 2.4,
                divisions: 12,
                label: widget.controller.lineHeight.toStringAsFixed(1),
                onChanged: (v) {
                  widget.controller.setLineHeight(v);
                  setState(() {});
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
