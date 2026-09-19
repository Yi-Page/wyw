import 'dart:math' as math;

import 'package:flutter/material.dart';

// Material 3 connected-button small tokens.

const double _connectedGroupMinHeight = 40;
const double _connectedGroupGap = 2;
const double _connectedInnerCorner = 8;
const double _connectedPressedInnerCorner = 4;
const double _connectedSegmentMinWidth = 72;
const double _connectedSegmentHPadding = 16;
const double _connectedLabelVPadding = 12;

/// A Material 3 connected-button group bound to a [TabController].
///
/// Segments take their label's intrinsic width (plus padding) and the group
/// scrolls horizontally when the labels do not fit, so a long list of tabs
/// stays readable instead of being squeezed into equal slices. When everything
/// does fit, the spare width is shared out so the group fills its row.
class ConnectedTabs extends StatelessWidget {
  const ConnectedTabs({
    super.key,
    required this.labels,
    this.controller,
    this.padding = EdgeInsets.zero,
  });

  final List<String> labels;

  final TabController? controller;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tabController = controller ?? DefaultTabController.of(context);
    assert(labels.isNotEmpty && labels.length == tabController.length);

    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelLarge;
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);

    final metrics = [
      for (final label in labels)
        TextPainter(
          text: TextSpan(text: label, style: labelStyle),
          maxLines: 1,
          textScaler: textScaler,
          textDirection: direction,
        )..layout(),
    ];
    // Grow with the scaled label so large text is not clipped vertically.
    final height = math.max(
      _connectedGroupMinHeight,
      metrics.map((m) => m.height).reduce(math.max) + _connectedLabelVPadding,
    );
    final baseWidths = [
      for (final m in metrics)
        math.max(
          _connectedSegmentMinWidth,
          m.width + _connectedSegmentHPadding * 2,
        ),
    ];
    final gaps = _connectedGroupGap * (labels.length - 1);

    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth;
          final needed = baseWidths.reduce((a, b) => a + b) + gaps;
          final fits = needed <= available;
          final extra = fits ? (available - needed) / labels.length : 0.0;
          final widths = [for (final w in baseWidths) w + extra];

          return SizedBox(
            height: height,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: fits ? const NeverScrollableScrollPhysics() : null,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < labels.length; index++) ...[
                    if (index != 0) const SizedBox(width: _connectedGroupGap),
                    SizedBox(
                      width: widths[index],
                      child: AnimatedBuilder(
                        animation: tabController.animation!,
                        builder: (context, _) {
                          final position = tabController.animation!.value;
                          return _ConnectedSegment(
                            label: labels[index],
                            height: height,
                            selection:
                                (1 - (position - index).abs()).clamp(0.0, 1.0),
                            isLeading: index == 0,
                            isTrailing: index == labels.length - 1,
                            onTap: () => tabController.animateTo(index),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ConnectedSegment extends StatefulWidget {
  const _ConnectedSegment({
    required this.label,
    required this.height,
    required this.selection,
    required this.isLeading,
    required this.isTrailing,
    required this.onTap,
  });

  final String label;
  final double height;
  final double selection;
  final bool isLeading;
  final bool isTrailing;
  final VoidCallback onTap;

  @override
  State<_ConnectedSegment> createState() => _ConnectedSegmentState();
}

class _ConnectedSegmentState extends State<_ConnectedSegment> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final selection = widget.selection;
    final outerCorner = widget.height / 2;
    final outerRadius = Radius.circular(outerCorner);

    return Semantics(
      button: true,
      inMutuallyExclusiveGroup: true,
      selected: selection > 0.5,
      // Selection already follows the tab animation; tween only the press.
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: _pressed ? 1 : 0),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        builder: (context, press, child) {
          var inner = _connectedInnerCorner +
              (outerCorner - _connectedInnerCorner) * selection;
          inner +=
              (_connectedPressedInnerCorner - inner) * press * (1 - selection);
          final animated = Radius.circular(inner);
          return Material(
            color: Color.lerp(
              colorScheme.surfaceContainer,
              colorScheme.secondaryContainer,
              selection,
            ),
            borderRadius: BorderRadiusDirectional.only(
              topStart: widget.isLeading ? outerRadius : animated,
              bottomStart: widget.isLeading ? outerRadius : animated,
              topEnd: widget.isTrailing ? outerRadius : animated,
              bottomEnd: widget.isTrailing ? outerRadius : animated,
            ),
            clipBehavior: Clip.antiAlias,
            child: child,
          );
        },
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (value) => setState(() => _pressed = value),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: _connectedSegmentHPadding),
              child: Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Color.lerp(
                    colorScheme.onSurfaceVariant,
                    colorScheme.onSecondaryContainer,
                    selection,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
