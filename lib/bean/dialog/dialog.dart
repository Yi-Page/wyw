import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:wyw/navigation.dart';
import 'package:wyw/utils/constants.dart';
import 'package:wyw/bean/styles/media_chrome_colors.dart';

/// 对一条路由的独占所有权（含首帧之前）。
///
/// 照抄 Kazumi 的 `KazumiDialogHandle`：调用方可在任意时机定向关闭某个
/// 对话框（而不是只能关"最上面那个"）。
class WywDialogHandle<T> {
  Route<T>? _route;
  bool _used = false;
  bool _dismissed = false;

  bool get isActive => !_dismissed && (_route?.isActive ?? false);

  void dismiss({T? popWith}) {
    if (_dismissed) return;
    _dismissed = true;
    final route = _route;
    if (route != null) WywDialog._dismissRoute(route, popWith);
  }

  void _attach(Route<T> route) {
    _used = true;
    _route = route;
  }

  void _finish() {
    _dismissed = true;
    _route = null;
  }
}

/// 对话框 / 底部弹窗的统一入口（照抄 Kazumi 新版 `KazumiDialog`）。
///
/// 相对 wyw 旧版 `dialog_helper.dart` 的提升：
///   - 句柄（[WywDialogHandle]）定向关闭单个对话框；
///   - 专用 route `_WywDialogRoute`：继承调用方主题、遮罩色来自 DialogTheme、
///     桌面焦点遍历 `closedLoop`、可配转场时长/构造；
///   - toast 带 `_toastRevision`：导航后只清旧页的 toast；
///   - `dismiss` 可带 context 定向关闭，也可无 context 关最后一个；
///   - 底部弹窗可复用同一套记账（见 [routeSettings] 注释）。
///
/// wyw 契约保留：observer 同时认 `WywDialog` 与 `WywBottomSheet` 两个路由名
/// （5 个 `PopScope(canPop:false)` 页面 + 47 处 `WywDialog.dismiss()` 依赖）。
class WywDialog {
  /// 全局路由观察器（注册在根 Navigator，见 main.dart）。
  static final WywDialogObserver observer = WywDialogObserver();

  // Allows modal sheets to use the same dismissal and route tracking.
  static const routeSettings = RouteSettings(name: 'WywDialog');
  static int _toastRevision = 0;

  WywDialog._internal();

  static Future<T?> show<T>({
    BuildContext? context,
    WywDialogHandle<T>? handle,
    bool clickMaskDismiss = true,
    FutureOr<void> Function()? onDismiss,
    Duration? transitionDuration,
    RouteTransitionsBuilder? transitionBuilder,
    required WidgetBuilder builder,
  }) async {
    final dialog = handle ?? WywDialogHandle<T>();
    if (dialog._used) {
      throw StateError('A dialog handle can only be used once.');
    }
    try {
      final ctx = context ??
          rootNavigatorKey.currentContext ??
          observer.navigator?.context;
      if (ctx == null || !ctx.mounted || dialog._dismissed) return null;
      final navigator = Navigator.of(ctx, rootNavigator: true);
      final route = _WywDialogRoute<T>(
        context: ctx,
        builder: builder,
        themes: InheritedTheme.capture(from: ctx, to: navigator.context),
        barrierColor: Theme.of(ctx).dialogTheme.barrierColor ??
            MediaChromeColors.barrier,
        barrierDismissible: clickMaskDismiss,
        traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
        settings: routeSettings,
        animationStyle: transitionDuration == null
            ? null
            : AnimationStyle(duration: transitionDuration),
        transitionBuilder: transitionBuilder,
      );
      dialog._attach(route);
      return await navigator.push<T>(route);
    } catch (e) {
      debugPrint('Wyw Dialog Error: Failed to show dialog: $e');
      return null;
    } finally {
      dialog._finish();
      await onDismiss?.call();
    }
  }

  static void showToast({
    required String message,
    BuildContext? context,
    bool showActionButton = false,
    String? actionLabel,
    VoidCallback? onActionPressed,
    Duration duration = const Duration(seconds: 2),
  }) {
    final messenger = _resolveScaffoldMessenger(context);
    if (messenger != null && messenger.mounted) {
      final toastContext =
          context != null && context.mounted ? context : messenger.context;
      try {
        _toastRevision++;
        messenger
          ..removeCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(message),
              behavior: SnackBarBehavior.floating,
              width: MediaQuery.sizeOf(toastContext).width >
                      LayoutBreakpoint.medium['width']!
                  ? 600
                  : null,
              duration: duration,
              persist: false,
              action: showActionButton
                  ? SnackBarAction(
                      label: actionLabel ?? 'Dismiss',
                      onPressed: () {
                        // Let SnackBarAction close the old toast before replacing it.
                        if (onActionPressed != null) {
                          scheduleMicrotask(onActionPressed);
                        }
                      },
                    )
                  : null,
            ),
          );
      } catch (e) {
        debugPrint('Wyw Dialog Error: Failed to show toast: $e');
      }
    } else {
      debugPrint(
          'Wyw Dialog Error: No ScaffoldMessenger available to show Toast');
    }
  }

  /// 关闭对话框/弹窗。
  ///
  /// 传 context 时定向关闭「路由名匹配的当前 modal」；不传则关闭 observer
  /// 记的最后一个（含底部弹窗）。
  static void dismiss<T>({BuildContext? context, T? popWith}) {
    if (context != null && !context.mounted) return;
    final route =
        context == null ? observer._lastDialogRoute : ModalRoute.of(context);
    if (route != null && observer._isWywDialogRoute(route)) {
      _dismissRoute(route, popWith);
    }
  }

  static void _dismissRoute<T>(Route<T> route, T? result) {
    if (!route.isActive) return;
    // Owners may be disposed while Navigator is reconciling its routes.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _dismissRoute(route, result);
      });
      return;
    }
    final navigator = route.navigator;
    if (navigator == null || !navigator.mounted) return;
    if (route.isCurrent) {
      navigator.pop<T>(result);
    } else {
      navigator.removeRoute<T>(route, result);
    }
  }

  static ScaffoldMessengerState? _resolveScaffoldMessenger(
    BuildContext? context,
  ) {
    if (context != null && context.mounted) {
      final scopedMessenger = ScaffoldMessenger.maybeOf(context);
      if (scopedMessenger != null) {
        return scopedMessenger;
      }
    }
    return rootScaffoldMessengerKey.currentState;
  }

  // ===== wyw 保留的方法（Kazumi 由 sheet 层自己实现）=====

  /// 从底部弹出模态弹窗。
  ///
  /// 必须给路由带上默认名 `WywBottomSheet`，否则会绕过 [WywDialogObserver]
  /// 的记账：`dismiss()`（47 处调用）与 5 个 `PopScope(canPop:false)` 页面
  /// 的返回键处理都会把它当"不存在"。这个入口（而非裸 showModalBottomSheet）
  /// 是 wyw 的返回键契约，不能丢。
  static Future<T?> showBottomSheet<T>({
    BuildContext? context,
    required WidgetBuilder builder,
    Color? backgroundColor,
    double? elevation,
    ShapeBorder? shape,
    Clip? clipBehavior,
    BoxConstraints? constraints,
    Color? barrierColor,
    bool isScrollControlled = false,
    bool useRootNavigator = true,
    bool isDismissible = true,
    bool enableDrag = true,
    bool showDragHandle = false,
    RouteSettings? routeSettings,
    AnimationController? transitionAnimationController,
    Offset? anchorPoint,
    bool useSafeArea = false,
  }) async {
    // Use provided context first, then root context, then fallback to the
    // observed navigator's context.
    final ctx = context ??
        rootNavigatorKey.currentContext ??
        observer.navigator?.context;
    if (ctx != null && ctx.mounted) {
      try {
        final result = await showModalBottomSheet<T>(
          context: ctx,
          builder: builder,
          backgroundColor: backgroundColor,
          elevation: elevation,
          shape: shape,
          clipBehavior: clipBehavior,
          constraints: constraints,
          barrierColor: barrierColor,
          isScrollControlled: isScrollControlled,
          useRootNavigator: useRootNavigator,
          isDismissible: isDismissible,
          enableDrag: enableDrag,
          showDragHandle: showDragHandle,
          routeSettings:
              routeSettings ?? const RouteSettings(name: 'WywBottomSheet'),
          transitionAnimationController: transitionAnimationController,
          anchorPoint: anchorPoint,
          useSafeArea: useSafeArea,
        );
        return result;
      } catch (e) {
        debugPrint('Wyw Dialog Error: Failed to show bottom sheet: $e');
        return null;
      }
    } else {
      debugPrint('Wyw Dialog Error: No available context, skip bottom sheet');
      return null;
    }
  }

  /// 标准的「取消 / 确认」二元对话框，返回用户是否确认。
  static Future<bool> showConfirm({
    BuildContext? context,
    required String title,
    required String message,
    String confirmText = '确定',
    String cancelText = '取消',
    TextStyle? confirmTextStyle,
    TextStyle? cancelTextStyle,
  }) async {
    final result = await show<bool>(
      context: context,
      clickMaskDismiss: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelText, style: cancelTextStyle),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmText, style: confirmTextStyle),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

class _WywDialogRoute<T> extends DialogRoute<T> {
  _WywDialogRoute({
    required super.context,
    required super.builder,
    super.themes,
    super.barrierColor,
    super.barrierDismissible,
    super.traversalEdgeBehavior,
    super.settings,
    super.animationStyle,
    this.transitionBuilder,
  });

  final RouteTransitionsBuilder? transitionBuilder;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      transitionBuilder?.call(context, animation, secondaryAnimation, child) ??
      super.buildTransitions(context, animation, secondaryAnimation, child);
}

/// 全局对话框/弹窗记账（注册在根 Navigator）。
class WywDialogObserver extends NavigatorObserver {
  final List<Route<dynamic>> _wywDialogRoutes = [];
  bool _snackBarClearScheduled = false;

  bool get hasWywDialog => _wywDialogRoutes.isNotEmpty;

  Route<dynamic>? get _lastDialogRoute =>
      _wywDialogRoutes.isEmpty ? null : _wywDialogRoutes.last;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (_isWywDialogRoute(route)) {
      _wywDialogRoutes.add(route);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    if (route is PageRoute) _scheduleSnackBarClear();
    if (_isWywDialogRoute(route)) {
      _wywDialogRoutes.remove(route);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    if (oldRoute is PageRoute) _scheduleSnackBarClear();
    if (_isWywDialogRoute(oldRoute)) {
      _wywDialogRoutes.remove(oldRoute);
    }
    if (newRoute != null && _isWywDialogRoute(newRoute)) {
      _wywDialogRoutes.add(newRoute);
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (route is PageRoute) _scheduleSnackBarClear();

    if (_isWywDialogRoute(route)) {
      _wywDialogRoutes.remove(route);
    }
  }

  /// wyw 契约：对话框与底部弹窗都记账（Kazumi 只认 `KazumiDialog`）。
  bool _isWywDialogRoute(Route<dynamic>? route) =>
      route?.settings.name == 'WywDialog' ||
      route?.settings.name == 'WywBottomSheet';

  void _scheduleSnackBarClear() {
    if (_snackBarClearScheduled) return;
    _snackBarClearScheduled = true;
    final revision = WywDialog._toastRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snackBarClearScheduled = false;
      // Only clear the old page's toast, never one posted after navigation.
      if (revision == WywDialog._toastRevision) {
        rootScaffoldMessengerKey.currentState?.removeCurrentSnackBar();
      }
    });
  }
}
