import 'dart:async';
import 'package:flutter/material.dart';
import 'package:wyw/navigation.dart';
import 'package:wyw/utils/constants.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';

// A simple dialog helper class to show dialogs and toasts based on flutter native implementation (replace flutter_smart_dialog)
// flutter_smart_dialog use overlays and self-managed route stack to show dialogs.
// It's powerful but can't behave like the default showDialog, e.g. the lack of mask animation. the lack of snackbar.
// Use the implementation should be careful, because shared route stack with the whole app, it may cause some unexpected behaviors.
// Don't use it in double PopScope widget.
class WywDialog {
  /// The global observer that tracks contexts across the application
  static final WywDialogObserver observer = WywDialogObserver();

  WywDialog._internal();

  static Future<T?> show<T>({
    BuildContext? context,
    bool? clickMaskDismiss,
    VoidCallback? onDismiss,
    required WidgetBuilder builder,
  }) async {
    final ctx =
        context ?? rootNavigatorKey.currentContext ?? observer.currentContext;
    if (ctx != null && ctx.mounted) {
      try {
        final result = await showDialog<T>(
          context: ctx,
          useRootNavigator: true,
          barrierDismissible: clickMaskDismiss ?? true,
          builder: builder,
          routeSettings: const RouteSettings(name: 'WywDialog'),
        );
        onDismiss?.call();
        return result;
      } catch (e, s) {
        WywLogger().w('${LogTag.dialog} 显示对话框失败', error: e, stackTrace: s);
        return null;
      }
    } else {
      WywLogger().w('${LogTag.dialog} 无可用上下文，已跳过显示对话框');
      return null;
    }
  }

  static void showToast({
    required String message,
    BuildContext? context,
    bool showActionButton = false,
    String? actionLabel,
    Function()? onActionPressed,
    Duration duration = const Duration(seconds: 2),
  }) {
    final messenger = _resolveScaffoldMessenger(context);
    final toastContext = _resolveToastContext(context);
    if (messenger != null && toastContext != null && toastContext.mounted) {
      try {
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
                        onActionPressed?.call();
                        messenger.hideCurrentSnackBar();
                      },
                    )
                  : null,
            ),
          );
      } catch (e, s) {
        WywLogger().w('${LogTag.dialog} 显示 Toast 失败', error: e, stackTrace: s);
      }
    } else {
      WywLogger().w('${LogTag.dialog} 无可用上下文，已跳过显示 Toast');
    }
  }

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
    // Use provided context first, then root context, then fallback to current context
    final ctx = context ??
        rootNavigatorKey.currentContext ??
        observer.rootContext ??
        observer.currentContext;
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
      } catch (e, s) {
        WywLogger().w('${LogTag.dialog} 显示底部弹窗失败', error: e, stackTrace: s);
        return null;
      }
    } else {
      WywLogger().w('${LogTag.dialog} 无可用上下文，已跳过显示底部弹窗');
      return null;
    }
  }

  // 在存在返回值时弹出并附带返回值
  static void dismiss<T>({T? popWith}) {
    final dialogContext = observer.wywDialogContext;
    if (observer.hasWywDialog && dialogContext != null) {
      try {
        Navigator.of(dialogContext).pop(popWith);
      } catch (e, s) {
        WywLogger().w('${LogTag.dialog} 关闭对话框失败', error: e, stackTrace: s);
      }
    } else {
      WywLogger().w('${LogTag.dialog} 无可用上下文，已跳过关闭对话框');
    }
  }

  /// 弹出一个标准的「取消 / 确认」二元对话框，返回用户是否确认。
  ///
  /// 统一替代各处手写的 `show<bool>` + AlertDialog + 两个 TextButton 样板。
  /// 点击遮罩不会关闭（需要显式选择），关闭/取消一律返回 false。
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

  static BuildContext? _resolveToastContext(BuildContext? context) {
    if (context != null && context.mounted) {
      return context;
    }
    final messengerContext = rootScaffoldMessengerKey.currentContext;
    if (messengerContext != null && messengerContext.mounted) {
      return messengerContext;
    }
    return observer.scaffoldContext;
  }
}

/// Navigator observer to track contexts and dialog routes
class WywDialogObserver extends NavigatorObserver {
  /// List of active dialog routes
  final List<Route<dynamic>> _wywDialogRoutes = [];
  bool _snackBarClearScheduled = false;

  /// The most recent context from any MaterialPageRoute or PopupRoute
  BuildContext? _currentContext;

  /// The most recent context from any route containing a Scaffold
  BuildContext? _scaffoldContext;

  /// The root context of the app (for bottom sheets to cover the entire app)
  BuildContext? _rootContext;

  BuildContext? get currentContext => _currentContext;

  BuildContext? get scaffoldContext => _scaffoldContext ?? _currentContext;

  /// Get the root context for bottom sheets, fallback to scaffold context, then current context
  BuildContext? get rootContext =>
      _rootContext ?? _scaffoldContext ?? _currentContext;

  bool get hasWywDialog => _wywDialogRoutes.isNotEmpty;

  BuildContext? get wywDialogContext => _wywDialogRoutes.isNotEmpty
      ? _wywDialogRoutes.last.navigator?.context
      : null;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    if (_isWywDialogRoute(route)) {
      _wywDialogRoutes.add(route);
    }
    final navigatorContext = route.navigator?.context;
    if (navigatorContext != null) {
      _updateContexts(navigatorContext, route);
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _scheduleSnackBarClear();
    if (_isWywDialogRoute(route)) {
      _wywDialogRoutes.remove(route);
    }
    if (previousRoute != null) {
      final navigatorContext = previousRoute.navigator?.context;
      if (navigatorContext != null) {
        _updateContexts(navigatorContext, previousRoute);
      }
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _scheduleSnackBarClear();
    if (oldRoute != null && _isWywDialogRoute(oldRoute)) {
      _wywDialogRoutes.remove(oldRoute);
    }
    if (newRoute != null && _isWywDialogRoute(newRoute)) {
      _wywDialogRoutes.add(newRoute);
    }
    if (newRoute != null) {
      final navigatorContext = newRoute.navigator?.context;
      if (navigatorContext != null) {
        _updateContexts(navigatorContext, newRoute);
      }
    }
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    _scheduleSnackBarClear();

    if (_isWywDialogRoute(route)) {
      _wywDialogRoutes.remove(route);
    }

    if (previousRoute != null) {
      final navigatorContext = previousRoute.navigator?.context;
      if (navigatorContext != null) {
        _updateContexts(navigatorContext, previousRoute);
      }
    }
  }

  void _updateContexts(BuildContext context, Route<dynamic> route) {
    _currentContext = context;
    if (_hasScaffold(context)) {
      _scaffoldContext = context;
      // Always update root context with scaffold contexts to ensure we have the most recent one
      // This helps ensure bottom sheets appear at the app level
      _rootContext = context;
    }
  }

  bool _hasScaffold(BuildContext context) {
    return Scaffold.maybeOf(context) != null;
  }

  bool _isWywDialogRoute(Route<dynamic> route) {
    return route.settings.name == 'WywDialog' ||
        route.settings.name == 'WywBottomSheet';
  }

  void _scheduleSnackBarClear() {
    if (_snackBarClearScheduled) return;
    _snackBarClearScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snackBarClearScheduled = false;
      // Route observer callbacks run while Navigator is reconciling routes.
      // Clearing the root messenger after the frame avoids mutating UI state
      // in the middle of that reconciliation.
      rootScaffoldMessengerKey.currentState?.removeCurrentSnackBar();
    });
  }
}
