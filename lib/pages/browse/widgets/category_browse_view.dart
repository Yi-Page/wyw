import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/widget/empty_state_widget.dart';
import 'package:wyw/bean/widget/error_widget.dart';
import 'package:wyw/bean/widget/loading_indicator.dart';
import 'package:wyw/pages/descriptor/descriptor_page.dart';
import 'package:wyw/pages/plugin/plugin_controller.dart';

/// 空字符串筛选选项（如「全部」value=""）在 DropdownButton 中的内部占位符：
/// DropdownButton 把空串当"未选择"导致不显示选中项，这里用不可见字符代替，选中后再映射回空串。
const String _emptyOptionSentinel = '\u0000';

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

class _CategoryBrowseViewState extends State<CategoryBrowseView> {
  final PluginController _plugins = inject<PluginController>();

  Map<String, dynamic>? _categoryData;
  bool _loading = true;
  String? _error;

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
    if (plugin == null || !plugin.isRegistered) {
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
      if (plugin != null && plugin.isRegistered) {
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
  Future<List<String>?> _showOptionsDialog(
    String category,
    List<dynamic> groups,
  ) async {
    // 初始化每个组的默认值
    final values = <String>[
      for (final g in groups)
        if (g is Map)
          if ((g['type']?.toString() ?? '') == 'input')
            '' // input 类型默认空字符串
          else if ((g['options'] as List?)?.isNotEmpty == true)
            // dropdown 类型默认第一个选项的值
            (g['options'] as List).first is Map
                ? ((g['options'] as List).first as Map)['value'].toString()
                : ''
          else
            ''
        else
          '',
    ];

    // 用于存储 TextField 的控制器
    final controllers = <TextEditingController>[
      for (int i = 0; i < groups.length; i++)
        if (groups[i] is Map &&
            (groups[i]['type']?.toString() ?? '') == 'input')
          TextEditingController(text: values[i])
        else
          TextEditingController(), // 占位，不会使用
    ];

    return showDialog<List<String>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: Text('筛选 · $category'),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.7,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < groups.length; i++)
                        if (groups[i] is Map) ...[
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              (groups[i] as Map)['label']?.toString() ?? '',
                              style: Theme.of(ctx).textTheme.labelMedium,
                            ),
                          ),
                          const SizedBox(height: 4),
                          if ((groups[i] as Map)['type']?.toString() == 'input')
                            // 输入框类型
                            TextField(
                              controller: controllers[i],
                              cursorColor:
                                  Theme.of(context).colorScheme.primary,
                              decoration: InputDecoration(
                                floatingLabelBehavior:
                                    FloatingLabelBehavior.never,
                                hintText: '输入搜索内容',
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 12,
                                ),
                                border: const OutlineInputBorder(
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(8)),
                                ),
                              ),
                              onChanged: (text) {
                                values[i] = text;
                              },
                            )
                          else
                            // 下拉选择类型
                            DropdownButton<String>(
                              // 空串值（如「全部」value=""）用占位符，避免被当成"未选择"而显示空白
                              value: values[i].isEmpty
                                  ? _emptyOptionSentinel
                                  : values[i],
                              isExpanded: true,
                              items: [
                                for (final o in ((groups[i] as Map)['options']
                                        as List?) ??
                                    const [])
                                  if (o is Map)
                                    DropdownMenuItem(
                                      value: o['value'].toString().isEmpty
                                          ? _emptyOptionSentinel
                                          : o['value'].toString(),
                                      child: Text(
                                        o['text']?.toString() ??
                                            o['value'].toString(),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                              ],
                              onChanged: (v) {
                                setState(() {
                                  values[i] = (v == null)
                                      ? values[i]
                                      : (v == _emptyOptionSentinel ? '' : v);
                                });
                              },
                            ),
                          const SizedBox(height: 12),
                        ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () {
                    // 收集所有值（input 从 controller 获取最新值）
                    final result = <String>[];
                    for (int i = 0; i < groups.length; i++) {
                      if (groups[i] is Map &&
                          (groups[i]['type']?.toString() ?? '') == 'input') {
                        result.add(controllers[i].text);
                      } else {
                        result.add(values[i]);
                      }
                    }
                    Navigator.pop(ctx, result);
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
