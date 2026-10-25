import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Windows 无障碍桥噪音闸门。
///
/// 背景：Windows 上一旦有任意 UIA 客户端挂到窗口（读屏、某些辅助/调试工具，
/// 甚至是开发/测试环境），Flutter 引擎就会为整个应用生成语义树。引擎的无障碍桥
/// （`accessibility_bridge.cc`）对高频变化的树处理不过来，会在控制台持续刷
/// `Failed to update ui::AXTree, ... will not be in the tree and is not the new root`。
/// 这是引擎 bug，无害但刷屏；且**不是某个控件的问题**——只要界面在动（滚动、
/// 动画、定时器、进度），树就会变，所以整个应用都会报。
///
/// 处理：仅当**没有任何真·无障碍需求**（读屏导航、高对比、反色、粗体）时，
/// 把整棵语义树剥掉——界面照常交互、日志安静。一旦真需要无障碍（例如用户
/// 打开「讲述人」），立即恢复语义树。只作用于 Windows；其他平台恒不屏蔽。
class DesktopSemanticsGate extends StatefulWidget {
  const DesktopSemanticsGate({super.key, required this.child});

  final Widget child;

  @override
  State<DesktopSemanticsGate> createState() => _DesktopSemanticsGateState();
}

class _DesktopSemanticsGateState extends State<DesktopSemanticsGate>
    with WidgetsBindingObserver {
  bool _strip = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _strip = _shouldStrip();
  }

  @override
  void didChangeAccessibilityFeatures() {
    final strip = _shouldStrip();
    if (strip != _strip && mounted) {
      setState(() => _strip = strip);
    }
  }

  /// 真·无障碍需求存在时不剥，其余情况（Windows）剥掉。
  bool _shouldStrip() {
    if (defaultTargetPlatform != TargetPlatform.windows) return false;
    final features =
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures;
    return !(features.accessibleNavigation ||
        features.highContrast ||
        features.invertColors ||
        features.boldText);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(excluding: _strip, child: widget.child);
  }
}
