import 'package:flutter/material.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/services/storage/video_play_model.dart';

/// 手动播放弹窗的确认结果。
class ManualPlayRequest {
  const ManualPlayRequest({
    required this.url,
    required this.type,
    this.name = '',
  });

  /// 播放页网址 / 媒体直链 / 本地文件路径。
  final String url;

  /// 资源类型（播放页 / 直链 / 本地文件）。
  final PlayPathType type;

  /// 可选视频名称；为空时调用方回退用 url 作标题。
  final String name;

  /// 播放页标题：优先用户输入的名称，否则用地址本身。
  String get displayTitle => name.trim().isNotEmpty ? name.trim() : url;
}

/// 资源类型选项：(类型, 标题, 说明)。
/// resolve 需要插件固定逻辑，手动入口不提供。
const List<(PlayPathType, String, String)> _typeOptions = [
  (PlayPathType.page, '播放页', '打开网页并自动嗅探视频直链'),
  (PlayPathType.direct, '直链', 'm3u8 / mp4 等媒体地址直接播放'),
  (PlayPathType.local, '本地文件', '播放设备内的本地视频文件'),
];

/// 弹出手动播放弹窗；确认返回 [ManualPlayRequest]，取消返回 null。
Future<ManualPlayRequest?> showManualPlayDialog(BuildContext context) {
  return WywDialog.show<ManualPlayRequest>(
    context: context,
    builder: (_) => const _ManualPlayDialog(),
  );
}

class _ManualPlayDialog extends StatefulWidget {
  const _ManualPlayDialog();

  @override
  State<_ManualPlayDialog> createState() => _ManualPlayDialogState();
}

class _ManualPlayDialogState extends State<_ManualPlayDialog> {
  final _urlController = TextEditingController();
  final _nameController = TextEditingController();
  PlayPathType _type = PlayPathType.page;

  String get _url => _urlController.text.trim();

  /// 网页/直链必须是完整 http(s) 地址（WebView 嗅探与播放器都依赖）；
  /// 本地路径只要求非空。
  String? get _urlError {
    if (_url.isEmpty || _type == PlayPathType.local) return null;
    final isHttp = _url.startsWith('http://') || _url.startsWith('https://');
    if (!isHttp) return '网址需以 http(s):// 开头';
    return null;
  }

  bool get _canPlay => _url.isNotEmpty && _urlError == null;

  @override
  void dispose() {
    _urlController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final typeHint = _typeOptions.firstWhere((o) => o.$1 == _type).$3;
    return AlertDialog(
      title: const Text('手动播放'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: '播放页网址 / 直链 / 本地路径',
                hintText: _type == PlayPathType.local
                    ? '例如 /sdcard/Movies/video.mp4'
                    : 'https://example.com/watch?id=1',
                prefixIcon: const Icon(Icons.link_rounded),
                errorText: _urlError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '视频名称（可选）',
                prefixIcon: Icon(Icons.movie_outlined),
              ),
            ),
            const SizedBox(height: 16),
            Text('资源类型', style: textTheme.labelMedium),
            const SizedBox(height: 8),
            SegmentedButton<PlayPathType>(
              showSelectedIcon: false,
              segments: [
                for (final (type, label, _) in _typeOptions)
                  ButtonSegment(value: type, label: Text(label)),
              ],
              selected: {_type},
              onSelectionChanged: (selection) =>
                  setState(() => _type = selection.first),
            ),
            const SizedBox(height: 8),
            Text(
              typeHint,
              style: textTheme.bodySmall
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            '取消',
            style: TextStyle(color: colorScheme.outline),
          ),
        ),
        TextButton(
          onPressed: _canPlay ? _play : null,
          child: const Text('播放'),
        ),
      ],
    );
  }

  void _play() {
    if (!_canPlay) return;
    Navigator.of(context).pop(ManualPlayRequest(
      url: _url,
      type: _type,
      name: _nameController.text.trim(),
    ));
  }
}
