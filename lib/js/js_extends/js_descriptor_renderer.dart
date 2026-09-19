import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/plugins/plugin.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:wyw/bean/card/network_img_layer.dart';
import '../../pages/plugin/plugin_controller.dart';
import 'js_descriptor.dart';

/// UI 描述符 → Widget 渲染器。
///
/// **设计**：纯无状态 class，构造时绑定 onAction 回调；`buildList()` 递归
/// switch on `UiType`，每个 case 构造对应 Flutter widget。
///
/// **容错**：
///   - 未知 `type` → `SizedBox.shrink()` + warn log（不抛错）
///   - 缺字段 → 默认值（padding/elevation/...）
///   - 嵌套深度 > [maxDepth] → 当前节点截断为 `SizedBox.shrink()`
///   - `Button.onTap` 缺失 → 渲染 disabled 按钮
class UiDescriptorRenderer {
  /// 嵌套深度上限（与 JS 端 `__ui_validate_` 对齐）
  static const int maxDepth = 32;

  /// `Wrap` 始终经 [_LazyWrap] 渲染：保持原 Wrap 的自适应流式布局
  /// （子项按内容尺寸自动换行、间距恒定，任意屏幕宽度观感一致），
  /// 但先渲染前 [_LazyWrap.initCount] 项 + 「加载更多」，避免一次性
  /// 构建/挂载数百个子节点（如上百话章节按钮）导致卡顿。

  /// 按钮点击回调（page 层注入：实际执行 `plugin.invoke`）
  final Future<void> Function(UiAction action) onAction;

  /// 导航回调（page 层注入：触发 Flutter 路由跳转）
  final Future<void> Function(UiNavigate nav, String sourcePluginName)?
      onNavigate;

  /// 调用方插件名（navigate 跳转时回传给 page 层，定位 target plugin）
  final String sourcePluginName;

  /// 警告日志回调（默认走 `WywLogger`）
  final void Function(String message) onLog;

  UiDescriptorRenderer({
    required this.onAction,
    this.onNavigate,
    this.sourcePluginName = '',
    void Function(String)? onLog,
  }) : onLog = onLog ?? _defaultLog;

  static void _defaultLog(String message) {
    WywLogger().w('${LogTag.js} $message');
  }

  /// 渲染入口。
  ///
  /// 接受 `List<Map<String, dynamic>>`（插件直接返回的 raw list），
  /// 内部逐项解析为 `UiDescriptor` 后渲染。
  ///
  /// 返回 `List<Widget>`，调用方包进 `SliverGrid` / `SliverList` 等。
  List<Widget> buildList(List<Map<String, dynamic>> rawList) {
    final widgets = <Widget>[];
    for (var i = 0; i < rawList.length; i++) {
      final raw = rawList[i];
      try {
        widgets.add(_buildOne(UiDescriptor.fromJson(raw), 0));
      } catch (e) {
        onLog('渲染卡片失败 index=$i: $e');
        widgets.add(const SizedBox.shrink());
      }
    }
    return widgets;
  }

  /// 渲染单个描述符（递归）
  Widget _buildOne(UiDescriptor node, int depth) {
    if (depth > maxDepth) {
      onLog('UI 嵌套超过最大深度 depth=$maxDepth type=${node.type.name}，已截断');
      return const SizedBox.shrink();
    }

    switch (node.type) {
      case UiType.card:
        return _buildCard(node, depth);
      case UiType.column:
        return _buildColumn(node, depth);
      case UiType.row:
        return _buildRow(node, depth);
      case UiType.stack:
        return _buildStack(node, depth);
      case UiType.image:
        return _buildImage(node);
      case UiType.text:
        return _buildText(node);
      case UiType.icon:
        return _buildIcon(node);
      case UiType.button:
        return _buildButton(node);
      case UiType.iconButton:
        return _buildIconButton(node);
      case UiType.tag:
        return _buildTag(node);
      case UiType.spacer:
        return _buildSpacer(node);
      case UiType.divider:
        return _buildDivider(node);
      case UiType.container:
        return _buildContainer(node, depth);
      case UiType.padding:
        return _buildPadding(node, depth);
      case UiType.sizedBox:
        return _buildSizedBox(node);
      case UiType.center:
        return _buildCenter(node, depth);
      case UiType.align:
        return _buildAlign(node, depth);
      case UiType.expanded:
        return _buildExpanded(node, depth);
      case UiType.wrap:
        return _buildWrap(node, depth);
      case UiType.aspectRatio:
        return _buildAspectRatio(node, depth);
      case UiType.listView:
        return _buildListView(node, depth);
      case UiType.singleChildScrollView:
        return _buildSingleChildScrollView(node, depth);
      case UiType.navigate:
        onLog('navigate 描述符泄漏到渲染树，已忽略');
        return const SizedBox.shrink();
      case UiType.action:
        onLog('action 描述符泄漏到渲染树，已忽略');
        return const SizedBox.shrink();
      case UiType.expansionTile:
        return _buildExpansionTile(node, depth);
      case UiType.pagination:
        return _buildPagination(node, depth);
      case UiType.unknown:
        onLog('未知 UI 类型 type=${node.raw['__type']}');
        return const SizedBox.shrink();
    }
  }

  // ===== 容器 =====

  Widget _buildCard(UiDescriptor node, int depth) {
    final raw = node.raw;
    final child = raw['child'];
    // 用 Builder 拿 BuildContext，使 `color: '@theme:xxx'` 可解析到 ColorScheme
    return Builder(
      builder: (context) => Card(
        elevation: _asDouble(raw['elevation'], fallback: 2),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
              _asDouble(raw['shapeRadius'], fallback: 12)),
        ),
        color: _resolveColor(raw['color'], context),
        child: Padding(
          padding: EdgeInsets.all(_asDouble(raw['padding'], fallback: 12)),
          child: child is Map<String, dynamic>
              ? _buildOne(UiDescriptor.fromJson(child), depth + 1)
              : const SizedBox.shrink(),
        ),
      ),
    );
  }

  Widget _buildColumn(UiDescriptor node, int depth) {
    final raw = node.raw;
    return Column(
      mainAxisAlignment: _parseMainAxis(raw['mainAxisAlignment']),
      crossAxisAlignment: _parseCrossAxis(raw['crossAxisAlignment']),
      mainAxisSize:
          raw['mainAxisSize'] == 'min' ? MainAxisSize.min : MainAxisSize.max,
      children: _takeChildren(raw['children'], depth),
    );
  }

  Widget _buildRow(UiDescriptor node, int depth) {
    final raw = node.raw;
    return Row(
      mainAxisAlignment: _parseMainAxis(raw['mainAxisAlignment']),
      crossAxisAlignment: _parseCrossAxis(raw['crossAxisAlignment']),
      mainAxisSize:
          raw['mainAxisSize'] == 'min' ? MainAxisSize.min : MainAxisSize.max,
      children: _takeChildren(raw['children'], depth),
    );
  }

  Widget _buildStack(UiDescriptor node, int depth) {
    final raw = node.raw;
    final children = _takeChildren(raw['children'], depth);
    return Stack(
      alignment: _parseStackAlignment(raw['alignment']),
      children: children,
    );
  }

  // ===== 叶子 =====

  Widget _buildImage(UiDescriptor node) {
    final raw = node.raw;
    final src = raw['src'] as String?;
    final w = _asDouble(raw['width'], fallback: 0);
    final h = _asDouble(raw['height'], fallback: 0);
    // 自定义请求头（如 JM 封面需要的 Referer/UA）
    final headers = (raw['headers'] as Map?)?.cast<String, String>();
    // 用 Builder 拿 context，给 Infinity 一个有限值（屏幕宽度 / 200）
    // 避免 NetworkImgLayer.placeholder 在 cacheSize 计算时 (Infinity*dpr).round() 崩溃
    return Builder(
      builder: (context) {
        final screenW = MediaQuery.sizeOf(context).width;
        final fw = (w == 0 || w == double.infinity) ? screenW : w;
        final fh = (h == 0 || h == double.infinity) ? 200.0 : h;
        return NetworkImgLayer(
          src: (src == null || src.isEmpty) ? null : src,
          width: fw,
          height: fh,
          type: raw['type'] as String?,
          httpHeaders: headers,
        );
      },
    );
  }

  Widget _buildText(UiDescriptor node) {
    final raw = node.raw;
    final content = (raw['content'] as String?) ?? '';
    final styleRaw = raw['style'];
    final maxLines = raw['maxLines'] as int?;
    final overflow = _parseTextOverflow(raw['overflow']);
    final color = _asColor(styleRaw is Map ? styleRaw['color'] : null);
    final fontSize =
        styleRaw is Map ? _asDouble(styleRaw['fontSize'], fallback: 0) : 0;
    final weight =
        styleRaw is Map ? _parseFontWeight(styleRaw['weight']) : null;

    return Text(
      content,
      maxLines: maxLines,
      overflow: overflow,
      style: TextStyle(
        color: color,
        fontSize: (fontSize == 0 ? null : fontSize) as double?,
        fontWeight: weight,
      ),
    );
  }

  Widget _buildIcon(UiDescriptor node) {
    final raw = node.raw;
    final name = (raw['name'] as String?) ?? 'help_outline';
    final size = _asDouble(raw['size'], fallback: 24);
    final color = _asColor(raw['color']);
    return _buildIconWidget(name, size: size, color: color);
  }

  /// 构造图标 Widget，支持两种 name 形态：
  ///   - Material Icon 名（如 'search'）→ 走 [_iconDataFor] 的映射表
  ///   - 十六进制码点（如 'e567' / '0xe567'）→ 直接用 'MaterialIcons' 字体渲染字形
  ///
  /// 说明：新版 Flutter 的 [IconData.codePoint] 被 `@mustBeConst` 约束，
  /// 不能在运行时用解析出的码点构造 [IconData]，因此码点分支改为用
  /// `Text` + MaterialIcons 字体绘制（与 `Icon` 内部实现等价）。
  Widget _buildIconWidget(String name, {double size = 24, Color? color}) {
    final codePoint = _parseIconCodePoint(name);
    if (codePoint != null) {
      return Text(
        String.fromCharCode(codePoint),
        style: TextStyle(
          fontFamily: 'MaterialIcons',
          fontSize: size,
          color: color,
        ),
      );
    }
    return Icon(_iconDataFor(name), size: size, color: color);
  }

  /// 解析 Material Icons 十六进制码点（支持 'e567' / '0xe567'）。
  ///
  /// 为避免把纯字母名称（如 'cafe'）误判成码点，仅当字符串全为十六进制
  /// 字符且至少包含一个数字时才解析。
  int? _parseIconCodePoint(String name) {
    final hex = RegExp(r'^0[xX]').hasMatch(name) ? name.substring(2) : name;
    if (RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex) &&
        RegExp(r'[0-9]').hasMatch(hex)) {
      return int.tryParse(hex, radix: 16);
    }
    return null;
  }

  Widget _buildPagination(UiDescriptor node, int depth) {
    final raw = node.raw;
    final page = (raw['page'] as num?)?.toInt() ?? 1;
    final maxPage = (raw['maxPage'] as num?)?.toInt() ?? 1;
    // 本页内容由 pageMethod + pageArgs 加载（首次渲染时执行），无需传 children
    return _PaginationView(
      page: page,
      maxPage: maxPage,
      depth: depth,
      render: _buildOne,
      sourcePluginName: sourcePluginName,
      onAction: onAction,
      onNavigate: onNavigate,
      pageMethod: raw['pageMethod'] as String?,
      pageArgs: (raw['pageArgs'] as List?)?.cast<dynamic>() ?? const [],
    );
  }

  Widget _buildButton(UiDescriptor node) {
    final raw = node.raw;
    final label = (raw['label'] as String?) ?? '';
    final onTapJson = raw['onTap'];
    final enabled = onTapJson is Map<String, dynamic>;

    // 按钮文本单行不换行，过长省略号；悬浮时用 Tooltip 显示完整文字。
    // 禁用态交给 M3 按钮自身渲染（onSurface/38%），不再手动覆盖灰色。
    final buttonText = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    Widget button;
    if (!enabled) {
      button = FilledButton.tonal(
        onPressed: null,
        child: buttonText,
      );
    } else if (onTapJson['__type'] == 'navigate') {
      // ★ navigate 类型优先
      button = FilledButton.tonal(
        onPressed: () {
          final nav = UiNavigate.fromJson(onTapJson);
          if (onNavigate != null) onNavigate!(nav, sourcePluginName);
        },
        child: buttonText,
      );
    } else {
      final action = UiAction.fromJson(onTapJson);
      button = FilledButton.tonal(
        onPressed: () => onAction(action),
        child: buttonText,
      );
    }

    // 鼠标悬浮展示完整文字（label 为空时不加，避免空提示）
    if (label.isEmpty) return button;
    return Tooltip(message: label, child: button);
  }

  /// IconButton：可点击的图标按钮。
  ///
  /// 字段：
  ///   - icon: 字符串（Material Icon 名如 'delete_outline'）或 UI.Icon 描述符
  ///   - onTap: UI.Action 或 UI.Navigate 描述符（必填，缺失则按钮 disabled）
  ///   - tooltip: 鼠标悬浮提示（可选）
  ///   - color: 图标颜色（可选，会覆盖 icon 自身的 color）
  ///   - size: 图标尺寸（可选，默认 24）
  Widget _buildIconButton(UiDescriptor node) {
    final raw = node.raw;

    // 解析 icon
    final iconJson = raw['icon'];
    Widget iconWidget;
    if (iconJson is Map<String, dynamic>) {
      // 完整的 UI.Icon 描述符
      iconWidget = _buildOne(UiDescriptor.fromJson(iconJson), 0);
    } else if (iconJson is String && iconJson.isNotEmpty) {
      // 字符串简写：Material Icon 名或十六进制码点（如 'e567'）
      final size = _asDouble(raw['size'], fallback: 24);
      final color = _asColor(raw['color']);
      iconWidget = _buildIconWidget(iconJson, size: size, color: color);
    } else {
      // 没传 icon → 用 help_outline 占位
      iconWidget = _buildIconWidget('help_outline',
          color: _asColor(raw['color']),
          size: _asDouble(raw['size'], fallback: 24));
    }

    // 解析 onTap（双语义：navigate 优先，其余走 action）
    final onTapJson = raw['onTap'];
    if (onTapJson is! Map<String, dynamic>) {
      return IconButton(
        icon: iconWidget,
        onPressed: null,
        tooltip: raw['tooltip'] as String?,
      );
    }

    if (onTapJson['__type'] == 'navigate') {
      return IconButton(
        icon: iconWidget,
        tooltip: raw['tooltip'] as String?,
        onPressed: () {
          final nav = UiNavigate.fromJson(onTapJson);
          if (onNavigate != null) onNavigate!(nav, sourcePluginName);
        },
      );
    }

    final action = UiAction.fromJson(onTapJson);
    return IconButton(
      icon: iconWidget,
      tooltip: raw['tooltip'] as String?,
      onPressed: () => onAction(action),
    );
  }

  Widget _buildTag(UiDescriptor node) {
    final raw = node.raw;
    final text = (raw['text'] as String?) ?? '';
    final bg = _asColor(raw['color']);
    return Chip(
      label: Text(text),
      backgroundColor: bg,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildSpacer(UiDescriptor node) {
    final raw = node.raw;
    final flex = _asInt(raw['flex'], fallback: 1);
    return Spacer(flex: flex);
  }

  Widget _buildDivider(UiDescriptor node) {
    final raw = node.raw;
    final thickness = _asDouble(raw['thickness'], fallback: 1);
    final color = _asColor(raw['color']);
    return Divider(
      thickness: thickness,
      color: color,
      indent: _asDouble(raw['indent'], fallback: 0),
      endIndent: _asDouble(raw['endIndent'], fallback: 0),
    );
  }

  // ===== 布局工具（新增） =====

  Widget _buildContainer(UiDescriptor node, int depth) {
    final raw = node.raw;
    final childJson = raw['child'];
    final decorationRaw = raw['decoration'];
    return Container(
      padding: _asEdgeInsets(raw['padding']),
      margin: _asEdgeInsets(raw['margin']),
      color: _asColor(raw['color']),
      width: _asWidth(raw['width']),
      height: _asHeight(raw['height']),
      alignment: _parseAlignment(raw['alignment']),
      decoration: decorationRaw is Map
          ? BoxDecoration(
              color: _asColor(decorationRaw['color']),
              borderRadius: _asBorderRadius(decorationRaw['borderRadius']),
              border: _asBorder(decorationRaw['border']),
            )
          : null,
      child: childJson is Map<String, dynamic>
          ? _buildOne(UiDescriptor.fromJson(childJson), depth + 1)
          : null,
    );
  }

  Widget _buildPadding(UiDescriptor node, int depth) {
    final raw = node.raw;
    return Padding(
      padding: _asEdgeInsets(raw['padding']) ?? const EdgeInsets.all(8),
      child: _buildOne(
          UiDescriptor.fromJson(raw['child'] as Map<String, dynamic>),
          depth + 1),
    );
  }

  Widget _buildSizedBox(UiDescriptor node) {
    final raw = node.raw;
    final w = _asDouble(raw['width'], fallback: 0);
    final h = _asDouble(raw['height'], fallback: 0);
    if (w > 0 && h > 0) return SizedBox(width: w, height: h);
    if (w > 0) return SizedBox(width: w);
    if (h > 0) return SizedBox(height: h);
    return const SizedBox.shrink();
  }

  Widget _buildCenter(UiDescriptor node, int depth) {
    final raw = node.raw;
    final wf = _asDouble(raw['widthFactor'], fallback: 1.0);
    return Center(
      widthFactor: wf == 0 ? null : wf,
      child: _buildOne(
          UiDescriptor.fromJson(raw['child'] as Map<String, dynamic>),
          depth + 1),
    );
  }

  Widget _buildAlign(UiDescriptor node, int depth) {
    final raw = node.raw;
    return Align(
      alignment: _parseAlignment(raw['alignment']) ?? Alignment.center,
      child: _buildOne(
          UiDescriptor.fromJson(raw['child'] as Map<String, dynamic>),
          depth + 1),
    );
  }

  Widget _buildExpanded(UiDescriptor node, int depth) {
    final raw = node.raw;
    final childJson = raw['child'];
    return Expanded(
      flex: _asInt(raw['flex'], fallback: 1),
      child: childJson is Map<String, dynamic>
          ? _buildOne(UiDescriptor.fromJson(childJson), depth + 1)
          : const SizedBox.shrink(),
    );
  }

  Widget _buildWrap(UiDescriptor node, int depth) {
    final raw = node.raw;
    final src = _normalizeChildren(raw['children']);
    final direction =
        raw['direction'] == 'vertical' ? Axis.vertical : Axis.horizontal;
    final spacing = _asDouble(raw['spacing'], fallback: 0);
    final runSpacing = _asDouble(raw['runSpacing'], fallback: 0);
    final alignment = _parseWrapAlignment(raw['alignment']);
    // 「分页 Wrap」——保持 Wrap 的自适应流式布局
    // （子项按内容尺寸自动换行、间距恒定，任意屏幕宽度观感一致），
    // 先渲染前 N 项 + 「加载更多」，避免一次性 mount 数百个子节点
    return _LazyWrap(
      children: src,
      depth: depth,
      render: _buildOne,
      direction: direction,
      spacing: spacing,
      runSpacing: runSpacing,
      alignment: alignment,
    );
  }

  Widget _buildAspectRatio(UiDescriptor node, int depth) {
    final raw = node.raw;
    return AspectRatio(
      aspectRatio: _asDouble(raw['aspectRatio'], fallback: 1.0),
      child: _buildOne(
          UiDescriptor.fromJson(raw['child'] as Map<String, dynamic>),
          depth + 1),
    );
  }

  Widget _buildListView(UiDescriptor node, int depth) {
    final raw = node.raw;
    return ListView(
      scrollDirection:
          raw['direction'] == 'horizontal' ? Axis.horizontal : Axis.vertical,
      padding: _asEdgeInsets(raw['padding']),
      children: _takeChildren(raw['children'], depth),
    );
  }

  Widget _buildSingleChildScrollView(UiDescriptor node, int depth) {
    final raw = node.raw;
    return SingleChildScrollView(
      scrollDirection:
          raw['direction'] == 'horizontal' ? Axis.horizontal : Axis.vertical,
      padding: _asEdgeInsets(raw['padding']),
      child: _buildOne(
          UiDescriptor.fromJson(raw['child'] as Map<String, dynamic>),
          depth + 1),
    );
  }

  // ===== 折叠面板 =====

  /// ExpansionTile：点击标题展开/收起 children。
  ///
  /// 字段：
  ///   - title: 子描述符（必填）→ 作为标题
  ///   - subtitle: 子描述符（可选）→ 作为副标题
  ///   - children: 子描述符列表（可选）→ 展开后的内容
  ///   - initiallyExpanded: bool（可选，默认 false）→ 是否初始展开
  ///   - shapeRadius: number（可选）→ 边框圆角（0 = 无圆角，矩形边框）
  Widget _buildExpansionTile(UiDescriptor node, int depth) {
    final raw = node.raw;

    // title（必填）— 必须能渲染，否则整个 tile 没意义
    final titleJson = raw['title'];
    final titleWidget = titleJson is Map<String, dynamic>
        ? _buildOne(UiDescriptor.fromJson(titleJson), depth + 1)
        : const SizedBox.shrink();

    // subtitle（可选）
    final subtitleJson = raw['subtitle'];
    final subtitleWidget = subtitleJson is Map<String, dynamic>
        ? _buildOne(UiDescriptor.fromJson(subtitleJson), depth + 1)
        : null;

    // children（可选）
    final childrenWidgets = _takeChildren(raw['children'], depth);

    final initiallyExpanded = raw['initiallyExpanded'] == true;

    // shapeRadius 控制边框（默认无圆角）
    final shapeRadius = raw['shapeRadius'];
    final shape = shapeRadius != null
        ? RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(_asDouble(shapeRadius, fallback: 0)),
          )
        : null;

    return ExpansionTile(
      title: titleWidget,
      subtitle: subtitleWidget,
      initiallyExpanded: initiallyExpanded,
      shape: shape,
      children: childrenWidgets,
    );
  }

  // ===== 工具方法 =====

  /// 取 children 列表（统一处理数组 / 单值 / null）
  ///
  /// [parentDepth] 是当前父节点的渲染深度，子节点 _buildOne 传 parentDepth+1
  List<Widget> _takeChildren(dynamic rawChildren, int parentDepth) {
    return _buildChildrenWidgets(_normalizeChildren(rawChildren), parentDepth);
  }

  /// 把 children 规范化为数组（统一处理数组 / 单值 / null）
  List<dynamic> _normalizeChildren(dynamic rawChildren) {
    if (rawChildren is List) return rawChildren;
    return rawChildren == null ? const [] : [rawChildren];
  }

  /// 逐个构建 children（[parentDepth] 是当前父节点深度，子节点 +1）
  List<Widget> _buildChildrenWidgets(List<dynamic> src, int parentDepth) {
    final list = <Widget>[];
    for (var i = 0; i < src.length; i++) {
      final c = src[i];
      if (c is Map<String, dynamic>) {
        list.add(_buildOne(UiDescriptor.fromJson(c), parentDepth + 1));
      }
    }
    return list;
  }

  // ---- 字段解析 ----

  double _asDouble(dynamic v, {required double fallback}) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  int _asInt(dynamic v, {required int fallback}) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? fallback;
    return fallback;
  }

  Color? _asColor(dynamic v) {
    if (v is! String || v.isEmpty) return null;
    var hex = v.trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) return null;
    final n = int.tryParse(hex, radix: 16);
    return n == null ? null : Color(n);
  }

  /// 解析颜色（含 hex + 主题色引用）。
  ///
  /// 支持两种写法：
  ///   - `'#RRGGBB'` 或 `'#AARRGGBB'` → 硬编码色（向后兼容）
  ///   - `'@theme:xxx'` → 解析为 `Theme.of(context).colorScheme.xxx`
  ///
  /// **使用要求**：调用此方法的 renderer 必须包裹在 `Builder(builder: (context) => ...)` 中，
  ///              以便拿到 `BuildContext`。
  Color? _resolveColor(dynamic v, BuildContext context) {
    if (v is String && v.startsWith('@theme:')) {
      return _themeColor(v.substring(7), context);
    }
    return _asColor(v);
  }

  /// Material 3 ColorScheme 命名色全集（30 个）。
  ///
  /// JS 端通过 `'@theme:surfaceContainerLow'` 等字符串引用。
  /// 全部走 `Theme.of(context).colorScheme.xxx`，跟随主题/深色模式自动切换。
  Color? _themeColor(String key, BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (key) {
      // Surface
      case 'surface':
        return scheme.surface;
      case 'surfaceDim':
        return scheme.surfaceDim;
      case 'surfaceBright':
        return scheme.surfaceBright;
      case 'surfaceContainerLowest':
        return scheme.surfaceContainerLowest;
      case 'surfaceContainerLow':
        return scheme.surfaceContainerLow;
      case 'surfaceContainer':
        return scheme.surfaceContainer;
      case 'surfaceContainerHigh':
        return scheme.surfaceContainerHigh;
      case 'surfaceContainerHighest':
        return scheme.surfaceContainerHighest;
      case 'surfaceTint':
        return scheme.surfaceTint;
      // On Surface
      case 'onSurface':
        return scheme.onSurface;
      case 'onSurfaceVariant':
        return scheme.onSurfaceVariant;
      // Primary
      case 'primary':
        return scheme.primary;
      case 'onPrimary':
        return scheme.onPrimary;
      case 'primaryContainer':
        return scheme.primaryContainer;
      case 'onPrimaryContainer':
        return scheme.onPrimaryContainer;
      // Secondary
      case 'secondary':
        return scheme.secondary;
      case 'onSecondary':
        return scheme.onSecondary;
      case 'secondaryContainer':
        return scheme.secondaryContainer;
      case 'onSecondaryContainer':
        return scheme.onSecondaryContainer;
      // Tertiary
      case 'tertiary':
        return scheme.tertiary;
      case 'onTertiary':
        return scheme.onTertiary;
      case 'tertiaryContainer':
        return scheme.tertiaryContainer;
      case 'onTertiaryContainer':
        return scheme.onTertiaryContainer;
      // Error
      case 'error':
        return scheme.error;
      case 'onError':
        return scheme.onError;
      case 'errorContainer':
        return scheme.errorContainer;
      case 'onErrorContainer':
        return scheme.onErrorContainer;
      // Outline
      case 'outline':
        return scheme.outline;
      case 'outlineVariant':
        return scheme.outlineVariant;
      // Other
      case 'shadow':
        return scheme.shadow;
      case 'scrim':
        return scheme.scrim;
      case 'inverseSurface':
        return scheme.inverseSurface;
      case 'onInverseSurface':
        return scheme.onInverseSurface;
      case 'inversePrimary':
        return scheme.inversePrimary;
      default:
        return null;
    }
  }

  MainAxisAlignment _parseMainAxis(dynamic v) {
    switch (v) {
      case 'start':
        return MainAxisAlignment.start;
      case 'end':
        return MainAxisAlignment.end;
      case 'center':
        return MainAxisAlignment.center;
      case 'spaceBetween':
        return MainAxisAlignment.spaceBetween;
      case 'spaceAround':
        return MainAxisAlignment.spaceAround;
      case 'spaceEvenly':
        return MainAxisAlignment.spaceEvenly;
      default:
        return MainAxisAlignment.start;
    }
  }

  CrossAxisAlignment _parseCrossAxis(dynamic v) {
    switch (v) {
      case 'start':
        return CrossAxisAlignment.start;
      case 'end':
        return CrossAxisAlignment.end;
      case 'center':
        return CrossAxisAlignment.center;
      case 'stretch':
        return CrossAxisAlignment.stretch;
      case 'baseline':
        return CrossAxisAlignment.baseline;
      default:
        return CrossAxisAlignment.center;
    }
  }

  Alignment _parseStackAlignment(dynamic v) {
    switch (v) {
      case 'topStart':
        return Alignment.topLeft;
      case 'topCenter':
        return Alignment.topCenter;
      case 'topEnd':
        return Alignment.topRight;
      case 'centerStart':
        return Alignment.centerLeft;
      case 'center':
        return Alignment.center;
      case 'centerEnd':
        return Alignment.centerRight;
      case 'bottomStart':
        return Alignment.bottomLeft;
      case 'bottomCenter':
        return Alignment.bottomCenter;
      case 'bottomEnd':
        return Alignment.bottomRight;
      default:
        return Alignment.topLeft;
    }
  }

  TextOverflow _parseTextOverflow(dynamic v) {
    switch (v) {
      case 'clip':
        return TextOverflow.clip;
      case 'fade':
        return TextOverflow.fade;
      case 'visible':
        return TextOverflow.visible;
      case 'ellipsis':
      default:
        return TextOverflow.ellipsis;
    }
  }

  FontWeight? _parseFontWeight(dynamic v) {
    switch (v) {
      case 'bold':
        return FontWeight.bold;
      case 'w100':
        return FontWeight.w100;
      case 'w200':
        return FontWeight.w200;
      case 'w300':
        return FontWeight.w300;
      case 'w400':
        return FontWeight.w400;
      case 'w500':
        return FontWeight.w500;
      case 'w600':
        return FontWeight.w600;
      case 'w700':
        return FontWeight.w700;
      case 'w800':
        return FontWeight.w800;
      case 'w900':
        return FontWeight.w900;
      default:
        return null;
    }
  }

  IconData _iconDataFor(String name) {
    switch (name) {
      // 导航和操作
      case 'search':
        return Icons.search;
      case 'arrow_upward':
        return Icons.arrow_upward;
      case 'arrow_downward':
        return Icons.arrow_downward;
      case 'arrow_back':
        return Icons.arrow_back;
      case 'arrow_forward':
        return Icons.arrow_forward;
      case 'arrow_back_ios':
        return Icons.arrow_back_ios;
      case 'arrow_forward_ios':
        return Icons.arrow_forward_ios;
      case 'arrow_drop_down':
        return Icons.arrow_drop_down;
      case 'arrow_drop_up':
        return Icons.arrow_drop_up;
      case 'close':
        return Icons.close;
      case 'check':
        return Icons.check;
      case 'clear':
        return Icons.clear;
      case 'done':
        return Icons.done;
      case 'done_all':
        return Icons.done_all;

      // 媒体控制
      case 'play_arrow':
        return Icons.play_arrow;
      case 'pause':
        return Icons.pause;
      case 'stop':
        return Icons.stop;
      case 'skip_next':
        return Icons.skip_next;
      case 'skip_previous':
        return Icons.skip_previous;
      case 'fast_forward':
        return Icons.fast_forward;
      case 'fast_rewind':
        return Icons.fast_rewind;
      case 'volume_up':
        return Icons.volume_up;
      case 'volume_down':
        return Icons.volume_down;
      case 'volume_off':
        return Icons.volume_off;
      case 'volume_mute':
        return Icons.volume_mute;
      case 'play_circle_outline':
        return Icons.play_circle_outline;
      case 'play_circle_filled':
        return Icons.play_circle_filled;
      case 'pause_circle_filled':
        return Icons.pause_circle_filled;
      case 'stop_circle':
        return Icons.stop_circle;

      // 收藏和评价
      case 'favorite':
        return Icons.favorite_border_outlined;
      case 'favorite_filled':
        return Icons.favorite;
      case 'star':
        return Icons.star;
      case 'star_border':
        return Icons.star_border;
      case 'star_half':
        return Icons.star_half;
      case 'thumb_up':
        return Icons.thumb_up_off_alt;
      case 'thumb_down':
        return Icons.thumb_down_off_alt;
      case 'thumb_up_filled':
        return Icons.thumb_up;
      case 'thumb_down_filled':
        return Icons.thumb_down;

      // 时间和历史
      case 'history':
        return Icons.history;
      case 'schedule':
        return Icons.schedule;
      case 'timer':
        return Icons.timer;
      case 'alarm':
        return Icons.alarm;
      case 'access_time':
        return Icons.access_time;

      // 列表和分类
      case 'list':
        return Icons.list;
      case 'menu':
        return Icons.menu;
      case 'grid_view':
        return Icons.grid_view;
      case 'view_list':
        return Icons.view_list;
      case 'view_module':
        return Icons.view_module;
      case 'view_compact':
        return Icons.view_compact;
      case 'sort':
        return Icons.sort;
      case 'filter_list':
        return Icons.filter_list;
      case 'category':
        return Icons.category;

      // 文件和文档
      case 'folder':
        return Icons.folder;
      case 'folder_open':
        return Icons.folder_open;
      case 'file':
        return Icons.insert_drive_file;
      case 'description':
        return Icons.description;
      case 'note':
        return Icons.note;
      case 'attachment':
        return Icons.attachment;

      // 分享和链接
      case 'share':
        return Icons.share;
      case 'open_in_new':
        return Icons.open_in_new;
      case 'open_in_browser':
        return Icons.open_in_browser;
      case 'link':
        return Icons.link;
      case 'copy':
        return Icons.copy;
      case 'cut':
        return Icons.cut;
      case 'paste':
        return Icons.paste;

      // 设置和工具
      case 'settings':
        return Icons.settings;
      case 'settings_applications':
        return Icons.settings_applications;
      case 'settings_backup_restore':
        return Icons.settings_backup_restore;
      case 'settings_cell':
        return Icons.settings_cell;
      case 'settings_ethernet':
        return Icons.settings_ethernet;
      case 'settings_input':
        return Icons.settings_input_component;
      case 'settings_phone':
        return Icons.settings_phone;
      case 'settings_power':
        return Icons.settings_power;
      case 'settings_voice':
        return Icons.settings_voice;
      case 'build':
        return Icons.build;
      case 'tune':
        return Icons.tune;

      // 信息提示
      case 'info':
        return Icons.info_outline;
      case 'info_filled':
        return Icons.info;
      case 'warning':
        return Icons.warning_outlined;
      case 'warning_filled':
        return Icons.warning;
      case 'error':
        return Icons.error_outline;
      case 'error_filled':
        return Icons.error;
      case 'help':
        return Icons.help_outline;
      case 'help_filled':
        return Icons.help;

      // 下载和上传
      case 'download':
        return Icons.download;
      case 'upload':
        return Icons.upload;
      case 'cloud_download':
        return Icons.cloud_download;
      case 'cloud_upload':
        return Icons.cloud_upload;
      case 'file_download':
        return Icons.file_download;
      case 'file_upload':
        return Icons.file_upload;
      case 'get_app':
        return Icons.get_app;

      // 更多和操作
      case 'more':
        return Icons.more_vert;
      case 'more_horiz':
        return Icons.more_horiz;
      case 'refresh':
        return Icons.refresh;
      case 'sync':
        return Icons.sync;
      case 'autorenew':
        return Icons.autorenew;
      case 'restart_alt':
        return Icons.restart_alt;

      // 导航
      case 'home':
        return Icons.home;
      case 'home_filled':
        return Icons.home_filled;
      case 'explore':
        return Icons.explore;
      case 'explore_off':
        return Icons.explore_off;
      case 'account_circle':
        return Icons.account_circle;
      case 'person':
        return Icons.person;
      case 'people':
        return Icons.people;
      case 'group':
        return Icons.group;

      // 添加和编辑
      case 'add':
        return Icons.add;
      case 'add_circle':
        return Icons.add_circle_outline;
      case 'add_circle_filled':
        return Icons.add_circle;
      case 'edit':
        return Icons.edit;
      case 'create':
        return Icons.create;
      case 'delete':
        return Icons.delete;
      case 'delete_outline':
        return Icons.delete_outline;
      case 'delete_forever':
        return Icons.delete_forever;
      case 'remove':
        return Icons.remove;
      case 'remove_circle':
        return Icons.remove_circle_outline;

      // 锁定和安全
      case 'lock':
        return Icons.lock;
      case 'lock_open':
        return Icons.lock_open;
      case 'lock_outline':
        return Icons.lock_outline;
      case 'security':
        return Icons.security;
      case 'verified':
        return Icons.verified;
      case 'verified_user':
        return Icons.verified_user;

      // 通信
      case 'chat':
        return Icons.chat;
      case 'chat_bubble':
        return Icons.chat_bubble_outline;
      case 'comment':
        return Icons.comment;
      case 'email':
        return Icons.email;
      case 'mail':
        return Icons.mail;
      case 'message':
        return Icons.message;
      case 'notifications':
        return Icons.notifications_none;
      case 'notifications_filled':
        return Icons.notifications;
      case 'notifications_active':
        return Icons.notifications_active;

      // 图片和媒体
      case 'photo':
        return Icons.photo;
      case 'photo_camera':
        return Icons.photo_camera;
      case 'image':
        return Icons.image;
      case 'video_library':
        return Icons.video_library;
      case 'videocam':
        return Icons.videocam;
      case 'videocam_off':
        return Icons.videocam_off;
      case 'music_note':
        return Icons.music_note;
      case 'album':
        return Icons.album;

      // 游戏和娱乐
      case 'gamepad':
        return Icons.gamepad;
      case 'sports_esports':
        return Icons.sports_esports;
      case 'casino':
        return Icons.casino;
      case 'dice':
        return Icons.casino;

      // 位置和地图
      case 'location_on':
        return Icons.location_on;
      case 'location_off':
        return Icons.location_off;
      case 'navigation':
        return Icons.navigation;
      case 'near_me':
        return Icons.near_me;
      case 'map':
        return Icons.map;
      case 'place':
        return Icons.place;

      // 购物和支付
      case 'shopping_cart':
        return Icons.shopping_cart;
      case 'shopping_bag':
        return Icons.shopping_bag;
      case 'shopping_basket':
        return Icons.shopping_basket;
      case 'payment':
        return Icons.payment;
      case 'credit_card':
        return Icons.credit_card;
      case 'receipt':
        return Icons.receipt;

      // 工具
      case 'brush':
        return Icons.brush;
      case 'palette':
        return Icons.palette;
      case 'color_lens':
        return Icons.color_lens;
      case 'gradient':
        return Icons.gradient;
      case 'opacity':
        return Icons.opacity;

      // 其他常用
      case 'done_outline':
        return Icons.done_outline;
      case 'check_circle':
        return Icons.check_circle_outline;
      case 'check_circle_filled':
        return Icons.check_circle;
      case 'cancel':
        return Icons.cancel;
      case 'block':
        return Icons.block;
      case 'close_fullscreen':
        return Icons.close_fullscreen;
      case 'open_with':
        return Icons.open_with;
      case 'fullscreen':
        return Icons.fullscreen;
      case 'fullscreen_exit':
        return Icons.fullscreen_exit;
      case 'zoom_in':
        return Icons.zoom_in;
      case 'zoom_out':
        return Icons.zoom_out;
      case 'rotate_left':
        return Icons.rotate_left;
      case 'rotate_right':
        return Icons.rotate_right;
      case 'crop':
        return Icons.crop;
      case 'crop_free':
        return Icons.crop_free;
      case 'filter':
        return Icons.filter;
      case 'label':
        return Icons.label;
      case 'label_outline':
        return Icons.label_outline;
      case 'bookmark':
        return Icons.bookmark_outline;
      case 'bookmark_filled':
        return Icons.bookmark;
      case 'flag':
        return Icons.flag;
      case 'flag_filled':
        return Icons.flag_outlined;
      case 'emoji':
        return Icons.emoji_emotions;
      case 'tag':
        return Icons.tag;
      case 'price_tag':
        return Icons.local_offer;

      // 未定义
      default:
        return Icons.help_outline;
    }
  }

  // ===== 辅助方法（新增） =====

  /// padding/margin 解析：number | [all] | [top,right,bottom,left]
  EdgeInsets? _asEdgeInsets(dynamic v) {
    if (v == null) return null;
    if (v is num) return EdgeInsets.all(v.toDouble());
    if (v is List) {
      if (v.length == 1) return EdgeInsets.all((v[0] as num).toDouble());
      if (v.length == 4) {
        return EdgeInsets.fromLTRB(
          (v[0] as num).toDouble(),
          (v[1] as num).toDouble(),
          (v[2] as num).toDouble(),
          (v[3] as num).toDouble(),
        );
      }
    }
    return null;
  }

  /// width 解析：number | 'fill'/'expand' (double.infinity)
  double? _asWidth(dynamic v) {
    if (v == 'fill' || v == 'expand') return double.infinity;
    if (v is num) return v.toDouble();
    return null;
  }

  /// height 解析：同 width
  double? _asHeight(dynamic v) {
    if (v == 'fill' || v == 'expand') return double.infinity;
    if (v is num) return v.toDouble();
    return null;
  }

  /// borderRadius 解析：number (all) | [tl,tr,br,bl]
  BorderRadius? _asBorderRadius(dynamic v) {
    if (v is num) return BorderRadius.circular(v.toDouble());
    if (v is List && v.length == 4) {
      return BorderRadius.only(
        topLeft: Radius.circular((v[0] as num).toDouble()),
        topRight: Radius.circular((v[1] as num).toDouble()),
        bottomRight: Radius.circular((v[2] as num).toDouble()),
        bottomLeft: Radius.circular((v[3] as num).toDouble()),
      );
    }
    return null;
  }

  /// border 解析：{ color: string, width: number }
  BoxBorder? _asBorder(dynamic v) {
    if (v is Map && v['width'] != null) {
      return Border.all(
        color: _asColor(v['color']) ?? Colors.black,
        width: _asDouble(v['width'], fallback: 1.0),
      );
    }
    return null;
  }

  /// alignment 解析（Container/Align）
  Alignment? _parseAlignment(dynamic v) {
    switch (v) {
      case 'topLeft':
        return Alignment.topLeft;
      case 'topCenter':
        return Alignment.topCenter;
      case 'topRight':
        return Alignment.topRight;
      case 'centerLeft':
        return Alignment.centerLeft;
      case 'center':
        return Alignment.center;
      case 'centerRight':
        return Alignment.centerRight;
      case 'bottomLeft':
        return Alignment.bottomLeft;
      case 'bottomCenter':
        return Alignment.bottomCenter;
      case 'bottomRight':
        return Alignment.bottomRight;
      default:
        return null;
    }
  }

  /// Wrap alignment 解析
  WrapAlignment _parseWrapAlignment(dynamic v) {
    switch (v) {
      case 'start':
        return WrapAlignment.start;
      case 'end':
        return WrapAlignment.end;
      case 'center':
        return WrapAlignment.center;
      case 'spaceBetween':
        return WrapAlignment.spaceBetween;
      case 'spaceAround':
        return WrapAlignment.spaceAround;
      case 'spaceEvenly':
        return WrapAlignment.spaceEvenly;
      default:
        return WrapAlignment.start;
    }
  }
}

/// 超大 children 的「分页 Wrap」：保持原 `Wrap` 的自适应流式布局
/// （子项按内容尺寸自动换行、间距恒定，任意屏幕宽度下观感一致），
/// 但初始只渲染前 [initCount] 项，剩余项通过 Wrap 末尾的「加载更多」chip
/// 分批追加，避免一次性构建/挂载数百个子节点（如上百话章节按钮）导致卡顿。
/// 末尾另有「倒序显示/恢复正序」按钮：点击后整组子项反向渲染（如章节源
/// 「最新在前」→ 显示「最早在前」），再点一次恢复。
class _LazyWrap extends StatefulWidget {
  const _LazyWrap({
    required this.children,
    required this.depth,
    required this.render,
    this.direction = Axis.horizontal,
    this.spacing = 0,
    this.runSpacing = 0,
    this.alignment = WrapAlignment.start,
  });

  /// 原始子描述符列表
  final List<dynamic> children;

  /// 当前渲染深度（子节点在 [render] 中 +1）
  final int depth;

  /// 子描述符 → Widget 渲染函数（renderer 的 `_buildOne`）
  final Widget Function(UiDescriptor node, int depth) render;

  final Axis direction;
  final double spacing;
  final double runSpacing;
  final WrapAlignment alignment;

  /// 初始渲染数量（首批通常已能铺满 1-2 屏，剩余通过「加载更多」追加）。
  static const int initCount = 100;

  /// 每次「加载更多」追加的数量（不宜过大，避免单帧 mount 过多）。
  static const int appendCount = 100;

  @override
  State<_LazyWrap> createState() => _LazyWrapState();
}

class _LazyWrapState extends State<_LazyWrap> {
  late int _count;

  /// 是否倒序渲染（由 Wrap 末尾的「倒序显示 / 恢复正序」按钮切换）。
  bool _reversed = false;

  @override
  void initState() {
    super.initState();
    _count = _LazyWrap.initCount;
  }

  @override
  Widget build(BuildContext context) {
    final src = widget.children;
    final total = src.length;
    final shown = _count < total ? _count : total;
    final items = <Widget>[];
    if (_reversed) {
      // 倒序渲染：从列表尾部向前取 shown 项（如章节源「最新在前」→ 显示
      // 「最早在前」），「加载更多」从尾部继续向头部推进、追加到末尾。
      final start = total - shown;
      for (var i = total - 1; i >= start; i--) {
        final c = src[i];
        if (c is Map<String, dynamic>) {
          items.add(widget.render(UiDescriptor.fromJson(c), widget.depth + 1));
        }
      }
    } else {
      for (var i = 0; i < shown; i++) {
        final c = src[i];
        if (c is Map<String, dynamic>) {
          items.add(widget.render(UiDescriptor.fromJson(c), widget.depth + 1));
        }
      }
    }
    // 末尾：倒序切换按钮
    if (total > _LazyWrap.initCount) {
      items.add(
        ActionChip(
          avatar: const Icon(Icons.swap_vert, size: 18),
          label: Text(_reversed ? '恢复正序' : '倒序显示'),
          onPressed: () => setState(() => _reversed = !_reversed),
        ),
      );
    }
    // 还有剩余：在末尾追加「加载更多」chip
    if (total > shown) {
      final remaining = total - shown;
      items.add(
        ActionChip(
          avatar: const Icon(Icons.expand_more, size: 18),
          label: Text('加载更多（剩余 $remaining）'),
          onPressed: () => setState(() {
            _count += _LazyWrap.appendCount;
          }),
        ),
      );
    }
    return Wrap(
      direction: widget.direction,
      spacing: widget.spacing,
      runSpacing: widget.runSpacing,
      alignment: widget.alignment,
      children: items,
    );
  }
}

/// 分页容器视图：自管理本页 children + 分页控制。
///
/// 切页时通过 [onLoadPage] 重新拉取该页的原始描述符，渲染后**替换自身 children**，
/// 不依赖宿主页面重建整页。
class _PaginationView extends StatefulWidget {
  const _PaginationView({
    required this.page,
    required this.maxPage,
    required this.depth,
    required this.render,
    required this.sourcePluginName,
    required this.onAction,
    this.onNavigate,
    this.pageMethod,
    this.pageArgs = const [],
  });

  final int page;
  final int maxPage;
  final int depth;
  final Widget Function(UiDescriptor node, int depth) render;

  /// 卡片内按钮回调（详情跳转等），加载分页卡片时透传给 invokeWidgets。
  final String sourcePluginName;
  final Future<void> Function(UiAction action) onAction;
  final Future<void> Function(UiNavigate nav, String sourcePluginName)?
      onNavigate;

  /// UI.Pagination 声明：获取单页内容的方法名与参数模板（页码位于 args[1]）。
  final String? pageMethod;
  final List<dynamic> pageArgs;

  @override
  State<_PaginationView> createState() => _PaginationViewState();
}

class _PaginationViewState extends State<_PaginationView> {
  late int _page;
  List<Widget> _children = [];
  bool _loading = true;

  Plugin? _plugin;

  @override
  void initState() {
    super.initState();
    _page = widget.page;
    _plugin = inject<PluginController>().getPlugin(widget.sourcePluginName);
    // 首次渲染直接执行 pageMethod 加载本页内容（不再依赖 children）
    if (widget.pageMethod != null) {
      _loadPage(_page);
    }
  }

  /// 加载指定页：直接经插件 invokeWidgets 渲染为 Widget 列表。
  Future<List<Widget>> onLoadPage(String method, List<dynamic> args) async {
    final plugin = _plugin;
    if (plugin != null) {
      return plugin.invokeWidgets(
        method,
        args: args,
        onAction: widget.onAction,
        onNavigate: widget.onNavigate,
        sourcePluginName: widget.sourcePluginName,
      );
    }
    return const [];
  }

  Future<void> _loadPage(int p) async {
    if (_plugin == null || widget.pageMethod == null) return;
    if (p < 1 || p > widget.maxPage) return;
    setState(() => _loading = true);
    try {
      // 分页参数构造：按约定 args[1] 为页码
      final pageParams = List<dynamic>.of(widget.pageArgs);
      if (pageParams.length >= 2) {
        pageParams[1] = p;
      } else {
        pageParams.add(p);
      }
      final widgets = await onLoadPage(widget.pageMethod!, pageParams);
      if (!mounted) return;
      setState(() {
        _page = p;
        _children = widgets;
        _loading = false;
      });
    } catch (e) {
      WywLogger().d(
        '${LogTag.js} 加载分页内容失败 page=$_page method=${widget.pageMethod}（已忽略）',
        error: e,
      );
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _goTo(int p) => _loadPage(p);

  /// 弹出「跳转到指定页」对话框：输入目标页码后跳转。
  ///
  /// 页码只允许数字，回车或点「跳转」确认；越界值自动夹取到
  /// `[1, widget.maxPage]`（与 [_loadPage] 的边界校验保持一致）。
  Future<void> _openJumpDialog() async {
    final controller = TextEditingController(text: '$_page');
    try {
      final target = await WywDialog.show(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('跳转到指定页'),
          content: SizedBox(
            width: 260,
            child: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              decoration: InputDecoration(
                labelText: '页码（1 - ${widget.maxPage}）',
                hintText: '输入目标页码',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (value) {
                final p = int.tryParse(value);
                if (p != null && p >= 1 && p <= widget.maxPage) {
                  WywDialog.dismiss(popWith: p);
                }
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => WywDialog.dismiss(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final p = int.tryParse(controller.text);
                if (p != null) WywDialog.dismiss(popWith: p);
              },
              child: const Text('跳转'),
            ),
          ],
        ),
      );
      if (target == null || !mounted) return;
      final p = target.clamp(1, widget.maxPage).toInt();
      if (p != _page) await _goTo(p);
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ..._children,
        if (_plugin != null && widget.pageMethod != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: '上一页',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _page > 1 ? () => _goTo(_page - 1) : null,
                ),
                // 页码指示器：点击弹出输入框，可跳转到指定页
                Tooltip(
                  message: '点击跳转到指定页',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _openJumpDialog,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: Text(
                        '$_page / ${widget.maxPage}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '下一页',
                  icon: const Icon(Icons.chevron_right),
                  onPressed:
                      _page < widget.maxPage ? () => _goTo(_page + 1) : null,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
