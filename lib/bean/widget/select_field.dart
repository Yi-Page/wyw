import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:wyw/utils/constants.dart';

/// 下拉选择组件的统一实现。
///
/// 背景（见 docs/ui-routing-design-spec.md B5/B7）：改造前全库有 4 套并存的下拉实现——
/// 裸 `DropdownButton`（无外框、默认下划线、与相邻 TextField 风格割裂，还要靠
/// `'\u0000'` 哨兵值绕开「空串=未选择」）、手搓 `MenuAnchor` + `MenuItemButton`
/// （10 处重复样板：controller 开合、`requestFocusOnHover: false`、`Container(height:
/// 48, minWidth: 112/160)`、选中态只靠颜色）、`PopupMenuButton`、raw `showMenu`。
///
/// 本文件收敛其中的「选择」语义，提供两个最小原语：
///   - [SelectField]      —— 表单 / 弹窗 / 筛选栏用，外观与 TextField 同款（M3 outlined）；
///   - [SelectMenuButton] —— 列表行 / 设置行用，纯文本触发器（无外框）。
///
/// 设计要点：
///   1. **[SelectField] 用 `InputDecorator` 承载外观**——直接复用 M3 的边框、浮动
///      label、禁用色与聚焦色，与相邻 `TextField` 天然同款，这是修掉「风格割裂」的关键。
///   2. **弹层走「全屏透明 route + 手算定位」**，见 [showSelectPopup]：动画、宽度、
///      圆角、条目密度、配色全在自己手里，不受 `MenuStyle` / M3 默认值牵制。
///   3. **选中项在右侧打 ✓**（不只靠文字变色），禁用项置灰不可点。
///   4. **原生支持任意值语义**：`''` / `null` 都是合法选项值，不需要哨兵占位 hack。
///   5. 触发器把长文本交给调用方约束（见 [SelectMenuButton] 的说明），弹层宽度则由
///      [showSelectPopup] 的 min/max 参数统一决定。
///
/// 已知取舍：弹层位置在打开时算一次，**不跟随触发器滚动**（Kazumi 的实现同样如此）。
/// 详见 [showSelectPopup] 的说明。

// ============================ 数据模型 ============================

class SelectOption<T> {
  const SelectOption({
    required this.value,
    required this.label,
    this.enabled = true,
    this.icon,
  });

  /// 选项值。允许为空串（如「全部」用 `''`）——不需要哨兵值占位。
  final T value;

  /// 展示文案。
  final String label;

  /// 是否可选。为 false 时置灰且不可点击。
  final bool enabled;

  /// 选项图标。
  ///
  /// 会渲染在两处：**弹层条目**里（在文案左侧），以及**触发器**里（显示当前选中项的
  /// 图标，让不开弹层也能看出选的是哪一项）。值为空 / 未选中时触发器不显示图标。
  ///
  /// 用于选项需要图标区分的场景（如深色模式：跟随系统 / 浅色 / 深色）；
  /// 选中态由右侧的 ✓ 表达，图标保持中性色，不靠变色表态。
  final IconData? icon;
}

/// 在 [options] 中查找值为 [value] 的选项；找不到返回 null。
SelectOption<T>? selectOptionOf<T>(List<SelectOption<T>> options, T? value) {
  for (final option in options) {
    if (option.value == value) return option;
  }
  return null;
}

// ============================ 弹层尺寸与动效 ============================
//
// 口径移植自 Kazumi 的 CustomDropdownMenu（lib/bean/widget/custom_dropdown_menu.dart）：
// 条目 h16/v12 + 14px 字、圆角 8、gap 4。宽度上限比 Kazumi 的 200 放宽到 360，
// 因为插件的筛选项文案可能较长。

/// 弹层与触发器之间的间距。
const double _popupGap = 4;

/// 条目横向内边距（测量与渲染共用，避免两处漂移）。
const double _itemHorizontalPadding = 16;

/// 条目纵向内边距（测量与渲染共用）。
const double _itemVerticalPadding = 12;

/// 条目文案字号（测量与渲染共用）。
const double _itemFontSize = 14;

/// 条目里「选项图标」占的横向空间（图标 20 + 间距 8）。
const double _itemIconExtent = 28;

/// 条目里「勾选标记」占的横向空间（间距 8 + 图标 18）。
const double _itemCheckExtent = 26;

/// 弹层宽度下限（触发器比它窄时按此宽度）。
const double _popupMinWidth = 140;

/// 弹层宽度上限。
const double _popupMaxWidth = 360;

/// 弹层最大高度，超出后内部滚动。
const double _popupMaxHeight = 360;

/// 弹层最小高度：上下可用空间都极窄时也不至于被压成一条缝
/// （宁可略微出界，也不要不可用）。
const double _popupMinHeight = 96;

/// 展开 / 收起动画时长。
const Duration _popupOpenDuration = Duration(milliseconds: 200);
const Duration _popupCloseDuration = Duration(milliseconds: 150);

// ============================ 弹层 ============================

/// 条目文案样式（测量与渲染共用，避免两处漂移）。
TextStyle _itemTextStyle(BuildContext context) =>
    (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
        .copyWith(fontSize: _itemFontSize);

/// 量出「最宽的那一条选项」需要多宽，让弹层宽度跟随内容。
///
/// 不测量的话，弹层宽度只由触发器宽度（下限 [_popupMinWidth]）决定，而设置行尾
/// 那截当前值往往只有几十像素——于是宽度恒为下限，稍长一点的选项文案就在
/// 固定的 140 里被省略。实测：`跟随系统`（含选项图标与 ✓）需要 56px，而
/// 140 − 32(内边距) − 28(图标) − 26(✓) = 54px，正好差 2px 被切。
///
/// 勾选标记只算给**当前选中项**：选中项比未选中项多占 [_itemCheckExtent]，
/// 按实际选中的那一条量才是准确的内容宽度。
double _measureOptionsWidth<T>(
  BuildContext context,
  List<SelectOption<T>> options,
  T? value,
) {
  final TextStyle style = _itemTextStyle(context);
  final TextScaler scaler = MediaQuery.textScalerOf(context);
  final TextDirection direction = Directionality.of(context);
  double widest = 0;
  for (final option in options) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: option.label, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    double width = painter.width;
    painter.dispose();
    if (option.icon != null) width += _itemIconExtent;
    if (option.value == value) width += _itemCheckExtent;
    widest = math.max(widest, width);
  }
  return widest;
}

/// 弹出下拉弹层；选中返回该选项，取消返回 null。
///
/// 实现方式移植自 Kazumi `CustomDropdownMenu`：用一条**全屏透明 route** 承载弹层
/// （而不是 `MenuAnchor` 的 `OverlayPortal`），好处是弹层的动画、宽度、圆角、
/// 条目密度与配色完全自己掌控，代价是要自己负责定位与交互。移植时补上了原版没有的
/// 三件事，否则相对 `MenuAnchor` 是一次能力退步：
///   1. **越界避让**：原版直接 `Positioned(left: offset.dx, top: offset.dy + h + gap)`，
///      右侧或底部越界就出屏；这里按可用区（安全区再扣键盘 `viewInsets`）做翻转与夹取，
///      并在上下空间都不足时用 [_popupMinHeight] 兜底；
///   2. **Esc 关闭 + 自动聚焦**：`MenuAnchor` 自带键盘/焦点行为，原版没有；
///   3. **无障碍**：给 `barrierLabel`，遮罩不再是「看不见的拦截层」。
///
/// **位置不是快照**：传入触发器的 [anchorKey]，弹层每帧重新读它的位置
/// （build 读到的是上一帧布局结果，所以帧末再复核一次，变化了就重定位）。
/// 于是窗口尺寸变化、触发器滚动都会跟着走；把 `Rect` 缓存成快照的旧写法会让
/// 弹层留在打开时的位置、与触发器脱节。
///
/// 与 `MenuAnchor` 相比仍有的差距：没有菜单语义节点与方向键遍历。
/// 若需要，要改用框架的菜单体系或自行补语义。
///
/// 返回值用 [SelectOption] 而不是裸值：这样即使某个选项的 `value` 是 `null`，
/// 也能和「用户取消」区分开。
Future<SelectOption<T>?> showSelectPopup<T>({
  required BuildContext context,
  required GlobalKey anchorKey,
  required List<SelectOption<T>> options,
  T? value,
  double gap = _popupGap,
  double minWidth = _popupMinWidth,
  double maxWidth = _popupMaxWidth,
  double maxHeight = _popupMaxHeight,
}) {
  if (options.isEmpty) return Future<SelectOption<T>?>.value(null);

  return Navigator.of(context, rootNavigator: true).push<SelectOption<T>>(
    PageRouteBuilder<SelectOption<T>>(
      opaque: false,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      // 弹层自带 Material 阴影，所以遮罩必须完全透明；点击拦截由页面层的
      // 全屏 GestureDetector 负责（与 Kazumi 一致），barrierDismissible 只作兜底。
      barrierColor: Colors.transparent,
      transitionDuration: _popupOpenDuration,
      reverseTransitionDuration: _popupCloseDuration,
      pageBuilder: (routeContext, animation, secondaryAnimation) =>
          _SelectPopup<T>(
        anchorKey: anchorKey,
        animation: animation,
        options: options,
        value: value,
        gap: gap,
        minWidth: minWidth,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      ),
    ),
  );
}

class _SelectPopup<T> extends StatefulWidget {
  const _SelectPopup({
    required this.anchorKey,
    required this.animation,
    required this.options,
    required this.value,
    required this.gap,
    required this.minWidth,
    required this.maxWidth,
    required this.maxHeight,
  });

  /// 触发器（弹层要贴着它定位）。
  ///
  /// 存 Key 而不是存算好的 `Rect`：窗口尺寸变化会让 `MediaQuery` 变化并触发重建，
  /// 若沿用打开时的矩形，弹层就会留在旧位置、与触发器脱节。
  final GlobalKey anchorKey;

  final Animation<double> animation;
  final List<SelectOption<T>> options;
  final T? value;
  final double gap;
  final double minWidth;
  final double maxWidth;
  final double maxHeight;

  @override
  State<_SelectPopup<T>> createState() => _SelectPopupState<T>();
}

class _SelectPopupState<T> extends State<_SelectPopup<T>> {
  /// 上一次成功读到的触发器矩形。
  ///
  /// 每次重建重新读 [widget.anchorKey]；只在读不到（触发器已被移除等瞬时状态）
  /// 时回退到它，避免弹层突然跳到屏幕左上角。
  Rect? _lastAnchorRect;

  /// 本帧定位所依据的矩形，供帧末复核比对。
  Rect? _positionedRect;

  /// 是否已排入帧末复核，避免一帧内重复排队。
  bool _verifyScheduled = false;

  /// 帧末复核触发器位置：build 阶段读到的全局位置是**上一帧布局**的结果，
  /// 窗口尺寸变化时它还是旧值，直到本帧布局完成才更新。所以布局后重量一次，
  /// 若已变化就重定位一帧。
  ///
  /// 这条链在触发器持续移动时会一直延续（每帧位置都在变 → 每帧重定位），
  /// 于是**滚动跟随**也顺带成立；停止移动后比对相等，链路自然结束。
  void _scheduleRepositionCheck() {
    if (_verifyScheduled) return;
    _verifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verifyScheduled = false;
      if (!mounted) return;
      final Rect? afterLayout = _anchorRectOf(widget.anchorKey);
      if (afterLayout != null && afterLayout != _positionedRect) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    final Rect? measured = _anchorRectOf(widget.anchorKey);
    if (measured != null) _lastAnchorRect = measured;
    final Rect? anchorRect = measured ?? _lastAnchorRect;
    // 触发器已经不存在（例如宿主页面被销毁）：不再画一个没有落点的弹层。
    if (anchorRect == null) return const SizedBox.shrink();
    _positionedRect = anchorRect;
    _scheduleRepositionCheck();

    final Animation<double> animation = widget.animation;
    final List<SelectOption<T>> options = widget.options;
    final T? value = widget.value;
    final double gap = widget.gap;
    final double minWidth = widget.minWidth;
    final double maxWidth = widget.maxWidth;
    final double maxHeight = widget.maxHeight;

    // 可用区：屏幕安全区再扣掉键盘占位（`MenuAnchor` 的 `_MenuLayout` 也是这么算的）。
    final Rect usable = media.viewInsets.deflateRect(
      media.padding.deflateRect(Offset.zero & media.size),
    );

    // ---- 宽度：以「触发器宽度」与「最宽条目所需宽度」的较大者为基准，
    //      再夹在 [minWidth, maxWidth] 与可用区之内 ----
    final double contentWidth =
        _measureOptionsWidth<T>(context, options, value) +
            _itemHorizontalPadding * 2;
    final double width = math.min(
      math.max(math.max(anchorRect.width, contentWidth), minWidth),
      math.max(math.min(maxWidth, usable.width), minWidth),
    );

    // ---- 水平：优先与触发器左对齐；右侧放不下则翻成右对齐；再不行夹进可用区 ----
    double left = anchorRect.left;
    if (left + width > usable.right) {
      left = anchorRect.right - width;
    }
    final double leftLimit = math.max(usable.left, usable.right - width);
    if (left < usable.left) {
      left = usable.left;
    } else if (left > leftLimit) {
      left = leftLimit;
    }

    // ---- 垂直：优先向下；下方明显不够且上方更宽裕时向上 ----
    //
    // 注意 [maxH] 只是**上限**，弹层实际高度由条目数决定（通常远小于上限）。
    // 所以向上弹出时不能按 `top = anchor.top - gap - maxH` 定位——那会让短弹层
    // 悬在触发器上方老远处。正确做法是给「底边」定位：弹层底边贴触发器上沿，
    // 让它按自身高度向上长。
    final double spaceBelow = usable.bottom - anchorRect.bottom - gap;
    final double spaceAbove = anchorRect.top - gap - usable.top;
    final bool openAbove =
        spaceBelow < math.min(maxHeight, 160) && spaceAbove > spaceBelow;
    final double available = openAbove ? spaceAbove : spaceBelow;
    final double maxH =
        math.max(_popupMinHeight, math.min(available, maxHeight));

    final Widget positioned = openAbove
        ? Positioned(
            left: left,
            bottom: usable.bottom - (anchorRect.top - gap),
            width: width,
            child: _buildMenu(
                context, theme, openAbove, maxH, animation, options, value),
          )
        : Positioned(
            left: left,
            top: anchorRect.bottom + gap,
            width: width,
            child: _buildMenu(
                context, theme, openAbove, maxH, animation, options, value),
          );

    return _PopupShortcuts(
      child: GestureDetector(
        // 全屏承接点击：点到弹层以外任何地方都关闭（与 Kazumi 一致）。
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: Stack(children: [positioned]),
      ),
    );
  }

  Widget _buildMenu(
    BuildContext context,
    ThemeData theme,
    bool openAbove,
    double maxHeight,
    Animation<double> animation,
    List<SelectOption<T>> options,
    T? value,
  ) {
    return Material(
      elevation: 6,
      borderRadius: StyleString.controlBorderRadius,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: theme.colorScheme.shadow,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final double t = Curves.easeOutCubic.transform(animation.value);
          return ClipRect(
            // 向上弹出时从底部往上长，向下弹出时从顶部往下长。
            child: Align(
              alignment:
                  openAbove ? Alignment.bottomCenter : Alignment.topCenter,
              heightFactor: t,
              child: Opacity(opacity: t, child: child),
            ),
          );
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            shrinkWrap: true,
            itemCount: options.length,
            itemBuilder: (context, index) =>
                _buildItem(context, theme.colorScheme, options[index]),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    ColorScheme colorScheme,
    SelectOption<T> option,
  ) {
    final bool selected = option.value == widget.value;
    final Color? disabledColor =
        option.enabled ? null : colorScheme.onSurface.withValues(alpha: 0.38);

    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _itemHorizontalPadding,
        vertical: _itemVerticalPadding,
      ),
      child: Row(
        children: [
          if (option.icon != null) ...[
            Icon(
              option.icon,
              size: 20,
              color: disabledColor ?? colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              option.label,
              style: _itemTextStyle(context).copyWith(
                color: disabledColor ??
                    (selected ? colorScheme.primary : colorScheme.onSurface),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 勾选标记在**右侧**（M3 DropdownMenu 惯例）：不再占左侧槽位，
          // 未选中项也就不必为它留白，文案左缘直接与「选项图标 / 内边距」对齐。
          if (selected) ...[
            const SizedBox(width: 8),
            Icon(Icons.check, size: 18, color: colorScheme.primary),
          ],
        ],
      ),
    );

    if (!option.enabled) {
      // 置灰项吞掉点击：否则会穿透到全屏关闭手势，点一下就关掉整个弹层
      // （`MenuAnchor` 的禁用项不会关闭菜单，行为保持一致）。
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: content,
      );
    }

    return InkWell(
      onTap: () => Navigator.of(context).pop(option),
      child: content,
    );
  }
}

/// 给弹层补上 Esc 关闭：`Shortcuts` + `Actions` + 自动聚焦（框架
/// `DismissMenuAction` 同款套路）。`MenuAnchor` 自带这个行为，自建弹层必须自己加。
class _PopupShortcuts extends StatelessWidget {
  const _PopupShortcuts({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (DismissIntent intent) {
              Navigator.of(context).pop();
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}

/// 让宿主（如 `SelectTile`）能从整行任意位置请求打开弹层。
///
/// 自建弹层没有 `MenuController`，用它替代「宿主持有 controller 再 open/close」
/// 的用法：触发器挂载时把自己的打开动作挂上来。
class SelectPopupController {
  VoidCallback? _openRequest;

  /// 由触发器在挂载 / 控制器变更时调用。
  void attach(VoidCallback open) => _openRequest = open;

  /// 由触发器在卸载 / 控制器变更时调用；只解绑自己那次挂载。
  void detach(VoidCallback open) {
    if (identical(_openRequest, open)) _openRequest = null;
  }

  /// 请求打开弹层；没有触发器连接时为空操作。
  void open() => _openRequest?.call();
}

// ============================ 触发器 ============================

/// 触发器共用：把 [GlobalKey] 包到的 widget 在全局坐标下的矩形算出来。
Rect? _anchorRectOf(GlobalKey key) {
  final RenderObject? object = key.currentContext?.findRenderObject();
  if (object is! RenderBox || !object.hasSize) return null;
  return object.localToGlobal(Offset.zero) & object.size;
}

/// 外框式下拉选择器：外观与 `TextField`（M3 outlined）一致。
///
/// 适用于表单、弹窗、筛选栏——凡是「旁边可能挨着一个 TextField」的地方。
/// 传入 [label] 时 label 浮动在边框上；不传时字段内始终显示当前选项文案，
/// 由调用方自行在字段上方渲染小节标签（与同排 TextField 保持同一排版口径）。
class SelectField<T> extends StatefulWidget {
  const SelectField({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    this.placeholder = '请选择',
    this.prefixIcon,
    this.enabled = true,
    this.dense = true,
  });

  /// 当前选中值；为 null 或不在 [options] 中时显示 [placeholder]。
  final T? value;

  final List<SelectOption<T>> options;

  final ValueChanged<T> onChanged;

  /// 浮动标签；为 null 时字段不显示 label（由调用方在外部渲染标签）。
  final String? label;

  /// 无选中项时的占位文案。
  final String placeholder;

  final Widget? prefixIcon;

  final bool enabled;

  /// 紧凑高度（沿用项目基准内容内边距）。
  final bool dense;

  @override
  State<SelectField<T>> createState() => _SelectFieldState<T>();
}

class _SelectFieldState<T> extends State<SelectField<T>> {
  final GlobalKey _anchorKey = GlobalKey(debugLabel: 'SelectField');
  bool _open = false;

  Future<void> _openPopup() async {
    // 防重入：弹层打开期间忽略重复请求
    if (_open) return;
    // 触发器还没完成布局就没有落点，先不开。
    if (_anchorRectOf(_anchorKey) == null) return;

    _open = true;
    try {
      final SelectOption<T>? picked = await showSelectPopup<T>(
        context: context,
        anchorKey: _anchorKey,
        options: widget.options,
        value: widget.value,
      );
      if (picked == null || !mounted) return;
      widget.onChanged(picked.value);
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final selected = selectOptionOf<T>(widget.options, widget.value);
    final disabledColor = colorScheme.onSurface.withValues(alpha: 0.38);
    final foreground = !widget.enabled
        ? disabledColor
        : (selected == null
            ? colorScheme.onSurfaceVariant
            : colorScheme.onSurface);

    return InkWell(
      key: _anchorKey,
      mouseCursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      borderRadius: StyleString.controlBorderRadius,
      onTap: widget.enabled ? _openPopup : null,
      child: InputDecorator(
        // 恒为 false：让传了 label 时 label 保持浮动，未选中项由下方
        // placeholder 文本承担提示职责（不依赖 hintText 的空态语义）。
        isEmpty: false,
        decoration: InputDecoration(
          labelText: widget.label,
          floatingLabelBehavior: widget.label == null
              ? FloatingLabelBehavior.never
              : FloatingLabelBehavior.auto,
          prefixIcon: widget.prefixIcon,
          enabled: widget.enabled,
          isDense: widget.dense,
          contentPadding: StyleString.fieldContentPadding,
          border: const OutlineInputBorder(
            borderRadius: StyleString.controlBorderRadius,
          ),
          suffixIcon: Icon(
            Icons.arrow_drop_down,
            color:
                widget.enabled ? colorScheme.onSurfaceVariant : disabledColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 当前选中项的图标：不开弹层也能看出选的是哪一项。
            if (selected?.icon != null) ...[
              Icon(
                selected!.icon,
                size: 18,
                color: widget.enabled
                    ? colorScheme.onSurfaceVariant
                    : disabledColor,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              selected?.label ?? widget.placeholder,
              style: textTheme.bodyMedium?.copyWith(color: foreground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// 无框式下拉触发器：纯文本 + 尾部 ▾，供列表行 / 设置行的尾部槽位使用。
///
/// 需要「整行可点即展开弹层」时，宿主传入 [controller]（见 `SelectTile`），
/// 并把行点击接到 `controller.open()`。
///
/// **宽度约束**：内部文案不做 `Flexible` 包裹（避免在无界宽度的 Row 里崩溃，
/// 见 `SelectMenuButton` 的 build），所以放进比文案更窄的固定宽度槽位时会
/// RenderFlex 溢出。调用方若要限制宽度，请给足空间或用 `ConstrainedBox` 并在
/// 上一级做省略。
class SelectMenuButton<T> extends StatefulWidget {
  const SelectMenuButton({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.controller,
    this.placeholder = '请选择',
    this.showArrow = true,
    this.textStyle,
    this.enabled = true,
  });

  final T? value;

  final List<SelectOption<T>> options;

  final ValueChanged<T> onChanged;

  /// 外部持有的打开请求通道（宿主希望从别处触发时传入）。
  final SelectPopupController? controller;

  final String placeholder;

  /// 是否显示尾部 ▾。
  final bool showArrow;

  final TextStyle? textStyle;

  final bool enabled;

  @override
  State<SelectMenuButton<T>> createState() => _SelectMenuButtonState<T>();
}

class _SelectMenuButtonState<T> extends State<SelectMenuButton<T>> {
  final GlobalKey _anchorKey = GlobalKey(debugLabel: 'SelectMenuButton');
  bool _open = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.attach(_openPopup);
  }

  @override
  void didUpdateWidget(SelectMenuButton<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach(_openPopup);
      widget.controller?.attach(_openPopup);
    }
  }

  @override
  void dispose() {
    widget.controller?.detach(_openPopup);
    super.dispose();
  }

  Future<void> _openPopup() async {
    // 防重入：整行点击与值区域点击可能同时到达
    if (_open) return;
    // 触发器还没完成布局就没有落点，先不开。
    if (_anchorRectOf(_anchorKey) == null) return;

    _open = true;
    try {
      final SelectOption<T>? picked = await showSelectPopup<T>(
        context: context,
        anchorKey: _anchorKey,
        options: widget.options,
        value: widget.value,
      );
      if (picked == null || !mounted) return;
      widget.onChanged(picked.value);
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final selected = selectOptionOf<T>(widget.options, widget.value);
    final disabledColor = colorScheme.onSurface.withValues(alpha: 0.38);
    final foreground = !widget.enabled
        ? disabledColor
        : (selected == null ? colorScheme.onSurfaceVariant : null);

    return InkWell(
      key: _anchorKey,
      mouseCursor:
          widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      borderRadius: StyleString.controlBorderRadius,
      onTap: widget.enabled ? _openPopup : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 当前选中项的图标：不开弹层也能看出选的是哪一项。
          if (selected?.icon != null) ...[
            Icon(
              selected!.icon,
              size: 18,
              color:
                  widget.enabled ? colorScheme.onSurfaceVariant : disabledColor,
            ),
            const SizedBox(width: 6),
          ],
          Text(
            selected?.label ?? widget.placeholder,
            style: (widget.textStyle ?? textTheme.bodyMedium)
                ?.copyWith(color: foreground),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (widget.showArrow) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down,
              size: 20,
              color:
                  widget.enabled ? colorScheme.onSurfaceVariant : disabledColor,
            ),
          ],
        ],
      ),
    );
  }
}
