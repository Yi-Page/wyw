import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/bean/widget/empty_state_widget.dart';
import 'package:wyw/bean/widget/error_widget.dart';
import 'package:wyw/bean/widget/loading_indicator.dart';
import 'package:wyw/bean/widget/select_field.dart';
import 'package:wyw/pages/descriptor/descriptor_page.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';
import 'package:wyw/utils/constants.dart';

/// 分类浏览视图（无 Scaffold，可嵌入 tab 页或独立页面）。
///
/// 流程：
///   1. 调用插件 `getCategory()` 拿分类结构 `{title, parts: [{name, categories}]}`
///   2. 展示分组 + 分类标签（ActionChip）
///   3. 点击标签 → 若有筛选选项先弹选择框 → `pushNamed('/descriptor')`
///      用 `loadCategory(category, page, options)` 分页渲染漫画网格
class CategoryBrowseView extends StatefulWidget {
  const CategoryBrowseView({
    super.key,
    required this.pluginName,
    this.onTitleChanged,
  });

  final String pluginName;

  /// 分类页标题变化回调（如选中某分类时）。
  final ValueChanged<String>? onTitleChanged;

  @override
  State<CategoryBrowseView> createState() => _CategoryBrowseViewState();
}

class _CategoryBrowseViewState extends State<CategoryBrowseView>
    with AutomaticKeepAliveClientMixin {
  final PluginController _plugins = inject<PluginController>();

  Map<String, dynamic>? _categoryData;
  bool _loading = true;
  String? _error;

  /// 切走再切回时不重建不重拉：分类数据只在首次可见时加载一次。
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadCategoryData();
  }

  Future<void> _loadCategoryData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final plugin = _plugins.getPlugin(widget.pluginName);
    if (plugin == null || !plugin.isLoaded) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '插件未注册：${widget.pluginName}';
      });
      return;
    }
    try {
      final raw = await plugin.invoke('getCategory', const []);
      if (!mounted) return;
      setState(() {
        _categoryData = raw is Map ? Map<String, dynamic>.from(raw) : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _selectCategory(String category) async {
    // 插件为该分类提供筛选选项（如每週必看的期数/类型）时先弹选择框
    List<dynamic>? optionGroups;
    try {
      final plugin = _plugins.getPlugin(widget.pluginName);
      if (plugin != null && plugin.isLoaded) {
        final raw = await plugin.invoke('getCategoryOptions', [category]);
        if (raw is List && raw.isNotEmpty) {
          optionGroups = raw.cast<dynamic>();
        }
      }
    } catch (_) {
      // 静默可接受：插件无选项接口属预期分支，直接进入分类
    }
    var selectedOptions = <String>[];
    if (optionGroups != null) {
      final selected = await _showOptionsDialog(category, optionGroups);
      if (!mounted || selected == null) return; // 用户取消
      selectedOptions = selected;
    }
    if (!mounted) return;
    widget.onTitleChanged?.call(category);
    // 转到 DescriptorPage：loadCategory(category, page, options) 分页渲染
    context.pushNamed(
      '/descriptor/',
      arguments: DescriptorPageRouteArgs(
        pluginName: widget.pluginName,
        method: 'loadCategory',
        args: [category, 1, selectedOptions],
        title: category,
      ),
    );
  }

  /// 弹出筛选选择框（支持 input 和 dropdown 两种类型）。返回选中值列表，取消返回 null。
  ///
  /// 走项目统一弹层通道 [WywDialog]（root navigator + 全局上下文兜底），
  /// 与搜索页「最近搜索」弹层同款，不再直接调裸 `showDialog`。
  Future<List<String>?> _showOptionsDialog(
    String category,
    List<dynamic> groups,
  ) {
    return WywDialog.show<List<String>>(
      context: context,
      builder: (_) => _CategoryOptionsDialog(
        category: category,
        groups: groups,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 必需
    if (_loading) {
      return const Center(child: LoadingIndicator());
    }
    if (_error != null) {
      return Center(
        child: GeneralErrorWidget(
          errMsg: _error!,
          onRetry: _loadCategoryData,
        ),
      );
    }
    final data = _categoryData;
    if (data == null) {
      return const Center(
        child: GeneralEmptyState(
          icon: Icons.category_outlined,
          title: '该插件暂无分类',
        ),
      );
    }
    final parts = (data['parts'] as List?) ?? const [];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final part in parts)
          if (part is Map) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
              child: Text(
                part['name']?.toString() ?? '',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in (part['categories'] as List?) ?? const [])
                  ActionChip(
                    label: Text(c.toString()),
                    onPressed: () => _selectCategory(c.toString()),
                  ),
              ],
            ),
          ],
      ],
    );
  }
}

/// 分类筛选弹窗（`getCategoryOptions()` 返回的分组表单）。
///
/// 改造前这里是「label + TextField / 裸 DropdownButton」的临时拼装：
///   - 输入框是圆角 8 的 outlined、下拉却是 M3 默认下划线的无边框控件，
///     行高、内边距、边框三者完全不同，同一列里风格割裂；
///   - 下拉还要靠 `'\u0000'` 哨兵值绕开 `DropdownButton` 的「空串 = 未选择」语义
///     （否则「全部」这类 `value: ''` 的选项显示为空白）。
///
/// 现在两种类型共用同一套排版与小节标签，下拉改用 `SelectField`
/// （与输入框同款 outlined 外观，且原生支持 `''` 作为合法选项值）。
///
/// 拆成独立 `StatefulWidget`（而非原来的 `StatefulBuilder` + 闭包变量）的原因：
/// `TextEditingController` 现在有真正的属主，随弹窗销毁一并 dispose，
/// 不再每次弹窗都泄漏一批控制器。
class _CategoryOptionsDialog extends StatefulWidget {
  const _CategoryOptionsDialog({
    required this.category,
    required this.groups,
  });

  final String category;
  final List<dynamic> groups;

  @override
  State<_CategoryOptionsDialog> createState() => _CategoryOptionsDialogState();
}

class _CategoryOptionsDialogState extends State<_CategoryOptionsDialog> {
  /// 每个分组的文本控制器（仅 `input` 类型使用）与当前选中值（`dropdown` 类型）。
  final List<TextEditingController> _controllers = [];
  final List<String> _values = [];

  static Map _mapOf(dynamic group) =>
      group is Map ? group : const <String, dynamic>{};

  static bool _isInput(Map group) => group['type']?.toString() == 'input';

  Map _mapAt(int index) => _mapOf(widget.groups[index]);

  @override
  void initState() {
    super.initState();
    for (final group in widget.groups) {
      final map = _mapOf(group);
      final options = (map['options'] as List?) ?? const [];
      // dropdown 默认选中第一项；input 与无选项分组默认空串。
      // 注意：`''` 是合法选项值（如「全部」），这里不需要任何占位哨兵。
      final initial =
          !_isInput(map) && options.isNotEmpty && options.first is Map
              ? (options.first as Map)['value'].toString()
              : '';
      _values.add(initial);
      _controllers.add(TextEditingController(text: initial));
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  List<SelectOption<String>> _optionsAt(int index) {
    final options = (_mapAt(index)['options'] as List?) ?? const [];
    return [
      for (final option in options)
        if (option is Map)
          SelectOption<String>(
            value: option['value'].toString(),
            label: option['text']?.toString() ?? option['value'].toString(),
          ),
    ];
  }

  /// 收集最终值：input 以输入框实时文本为准，其余取下拉选中值。
  List<String> _collect() => [
        for (var i = 0; i < widget.groups.length; i++)
          _isInput(_mapAt(i)) ? _controllers[i].text : _values[i],
      ];

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    // 分组顺序渲染：小节标签 → 控件；组间统一 16 间距。
    final fields = <Widget>[];
    for (var i = 0; i < widget.groups.length; i++) {
      if (widget.groups[i] is! Map) continue;
      if (fields.isNotEmpty) fields.add(const SizedBox(height: 16));
      fields.add(
        Text(
          _mapAt(i)['label']?.toString() ?? '',
          style: textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      );
      fields.add(const SizedBox(height: 6));
      fields.add(
        _isInput(_mapAt(i))
            ? TextField(
                controller: _controllers[i],
                cursorColor: colorScheme.primary,
                decoration: const InputDecoration(
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  hintText: '输入搜索内容',
                  isDense: true,
                  contentPadding: StyleString.fieldContentPadding,
                  border: OutlineInputBorder(
                    borderRadius: StyleString.controlBorderRadius,
                  ),
                ),
              )
            : SelectField<String>(
                value: _values[i],
                options: _optionsAt(i),
                onChanged: (value) => setState(() => _values[i] = value),
              ),
      );
    }

    return AlertDialog(
      title: Text('筛选 · ${widget.category}'),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        // 稳定下限宽度：筛选项数量随分类变化时，AlertDialog 会按内容收缩成不同宽度，
        // 弹窗忽宽忽窄很扎眼，这里给一个下限把它钉住。
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 240),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: fields,
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _collect()),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
