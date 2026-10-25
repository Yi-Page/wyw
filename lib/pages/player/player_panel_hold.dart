// 播放器控制栏的「临时钉住」原语：任何需要在交互期间阻止控制栏自动隐藏的
// 控件，都从 `player_item.dart` 的 lease 注册表取一个 `PlayerPanelHold`，
// 用完 release（父级另有兜底释放路径）。
//
// 本文件原有一个 `PlayerPanelHoldMenuAnchor`（把 MenuAnchor 的 onOpen/onClose
// 绑到 hold）——它只被 `player_item_panel.dart` 的底栏 MenuAnchor 簇与顶栏
// 「更多」菜单使用，这两处已随分屏面板收编退场，故该封装已删除；本文件只剩
// MouseRegion 封装（顶栏/底栏悬停保持可见仍用它）。
import 'package:flutter/material.dart';

/// A one-shot lease that keeps the player panel visible until released.
class PlayerPanelHold {
  PlayerPanelHold({required VoidCallback onRelease}) : _onRelease = onRelease;

  VoidCallback? _onRelease;

  bool get isReleased => _onRelease == null;

  void release() {
    final onRelease = _onRelease;
    if (onRelease == null) {
      return;
    }
    _onRelease = null;
    onRelease();
  }

  void releaseSilently() {
    _onRelease = null;
  }
}

/// Binds a hover widget lifecycle to a panel hold so callers do not manage
/// counters by hand.
class PlayerPanelHoldMouseRegion extends StatefulWidget {
  const PlayerPanelHoldMouseRegion({
    super.key,
    required this.acquirePlayerPanelHold,
    required this.child,
    this.cursor = MouseCursor.defer,
  });

  final PlayerPanelHold Function() acquirePlayerPanelHold;
  final Widget child;
  final MouseCursor cursor;

  @override
  State<PlayerPanelHoldMouseRegion> createState() =>
      _PlayerPanelHoldMouseRegionState();
}

class _PlayerPanelHoldMouseRegionState
    extends State<PlayerPanelHoldMouseRegion> {
  PlayerPanelHold? _hold;

  @override
  void dispose() {
    _releaseHold();
    super.dispose();
  }

  void _acquireHold() {
    if (_hold?.isReleased == false) {
      return;
    }
    _hold = widget.acquirePlayerPanelHold();
  }

  void _releaseHold() {
    _hold?.release();
    _hold = null;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => _acquireHold(),
      onExit: (_) => _releaseHold(),
      child: widget.child,
    );
  }
}
