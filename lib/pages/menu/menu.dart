import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter/services.dart';
import 'package:wyw/bean/widget/embedded_native_control_area.dart';
import 'package:wyw/navigation.dart';
import 'package:wyw/pages/menu/route_visibility.dart';
import 'package:wyw/pages/router.dart';
import 'package:wyw/services/platform/screen_orientation.dart';
import 'package:wyw/utils/double_back_exit.dart';

class ScaffoldMenu extends StatefulWidget {
  const ScaffoldMenu({super.key});

  @override
  State<ScaffoldMenu> createState() => _ScaffoldMenu();
}

class _ScaffoldMenu extends State<ScaffoldMenu> with RouteAware {
  final _outletKey = GlobalKey<RouterOutletState>();
  final _doubleBackExit = DoubleBackExit(toastMessage: '再按一次退出应用');

  /// The shell sits at the bottom of the root stack and stays mounted while
  /// other pages cover it, so it publishes that state for its subtree.
  bool _isCovered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void>) {
      rootRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    rootRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPushNext() => _setCovered(true);

  @override
  void didPopNext() {
    _setCovered(false);
    // 覆盖页（播放页 / 阅读器）退出后回到「应用方向」。它们自己也会在 dispose 时
    // 释放方向占用，这里是对账兜底：任何没走 release 的路径都不会把方向留在
    // 播放页/阅读器那一档上。
    unawaited(ScreenOrientationService.instance.applyBasePolicy());
  }

  void _setCovered(bool value) {
    if (!mounted || _isCovered == value) {
      return;
    }
    setState(() => _isCovered = value);
  }

  void _selectDestination(int index) {
    _doubleBackExit.reset();
    final currentIndex =
        menu.indexForPath(context.routeState(listen: false).uri.path);
    if (index == currentIndex) {
      return;
    }
    _outletKey.currentState?.navigate('/tab${menu.getPath(index)}/');
  }

  void _handleSystemBack(BuildContext context) {
    if (_outletKey.currentState?.maybePop() ?? false) {
      _doubleBackExit.reset();
      return;
    }

    final currentIndex =
        menu.indexForPath(context.routeState(listen: false).uri.path);
    if (currentIndex != 0) {
      _selectDestination(0);
      return;
    }

    if (!_doubleBackExit.handle(context)) return;
    _doubleBackExit.reset();
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = menu.indexForPath(context.routeState().uri.path);
    return RouteVisibility(
      isCovered: _isCovered,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            _handleSystemBack(context);
          }
        },
        child: OrientationBuilder(
          builder: (context, orientation) {
            return orientation == Orientation.portrait
                ? _bottomMenu(context, selectedIndex)
                : _sideMenu(context, selectedIndex);
          },
        ),
      ),
    );
  }

  Widget _outlet(BuildContext context, {BorderRadius? borderRadius}) {
    Widget child = NotificationListener<NavigationNotification>(
      // A non-poppable outlet must not override the shell's PopScope state.
      onNotification: (notification) => !notification.canHandlePop,
      child: RouterOutlet(key: _outletKey),
    );
    if (borderRadius != null) {
      child = ClipRRect(borderRadius: borderRadius, child: child);
    }
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: borderRadius,
      ),
      child: child,
    );
  }

  Widget _bottomMenu(BuildContext context, int selectedIndex) {
    return Scaffold(
      body: _outlet(context),
      bottomNavigationBar: NavigationBar(
        destinations: const <Widget>[
          NavigationDestination(
            selectedIcon: Icon(Icons.search),
            icon: Icon(Icons.search),
            label: '搜索',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.explore),
            icon: Icon(Icons.explore_outlined),
            label: '浏览',
          ),
          NavigationDestination(
            selectedIcon: Icon(Icons.settings),
            icon: Icon(Icons.settings),
            label: '我的',
          ),
        ],
        selectedIndex: selectedIndex,
        onDestinationSelected: _selectDestination,
      ),
    );
  }

  Widget _sideMenu(BuildContext context, int selectedIndex) {
    const borderRadius = BorderRadius.only(
      topLeft: Radius.circular(16),
      bottomLeft: Radius.circular(16),
    );
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      body: Row(
        children: [
          EmbeddedNativeControlArea(
            child: NavigationRail(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
              groupAlignment: 1,
              leading: SizedBox(
                width: 50,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ClipOval(
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        context.pushNamed('/history/');
                      },
                      child: Image.asset(
                        'assets/images/logo/logo.png',
                      ),
                    ),
                  ),
                ),
              ),
              labelType: NavigationRailLabelType.selected,
              destinations: const <NavigationRailDestination>[
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.search),
                  icon: Icon(Icons.search),
                  label: Text('搜索'),
                ),
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.explore),
                  icon: Icon(Icons.explore_outlined),
                  label: Text('浏览'),
                ),
                NavigationRailDestination(
                  selectedIcon: Icon(Icons.settings),
                  icon: Icon(Icons.settings_outlined),
                  label: Text('我的'),
                ),
              ],
              selectedIndex: selectedIndex,
              onDestinationSelected: _selectDestination,
            ),
          ),
          Expanded(child: _outlet(context, borderRadius: borderRadius)),
        ],
      ),
    );
  }
}
