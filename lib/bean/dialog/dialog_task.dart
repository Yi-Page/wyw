import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:wyw/bean/dialog/dialog.dart'
    show WywDialog, WywDialogHandle;
import 'package:wyw/bean/widget/loading_indicator.dart';

/// 任务式对话框的宿主 mixin（照抄 Kazumi 的 `KazumiDialogOwner`）。
///
/// 让页面能 `dialogs.run((task) async { ... })`：统一的加载对话框、取消语义、
/// 错误提示，全部走 [WywDialog] 记账（返回键可正常关闭）。
mixin WywDialogOwner<T extends StatefulWidget> on State<T> {
  late final dialogs = WywDialogController(context: () => context)
    ..addListener(_refreshDialogState);

  void _refreshDialogState() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    dialogs.removeListener(_refreshDialogState);
    dialogs.dispose();
    super.dispose();
  }
}

class WywDialogController extends ChangeNotifier {
  WywDialogController({BuildContext Function()? context})
      : _context = context;

  final BuildContext Function()? _context;
  WywDialogTask? _current;
  bool _disposed = false;

  bool get isRunning => _current?._isActive ?? false;

  /// Await steps through the task to stop on cancellation. Replacing or disposing
  /// the owner skips [onCancelled]; user cancellation calls it after cleanup.
  Future<void> run(
    Future<void> Function(WywDialogTask task) action, {
    String? errorMessage,
    void Function(Object error, StackTrace stackTrace)? onError,
    VoidCallback? onCancelled,
  }) async {
    if (_disposed || !(_context?.call().mounted ?? true)) return;
    cancel();
    final task = _current = WywDialogTask._(this);
    notifyListeners();
    try {
      await action(task);
    } on _DialogTaskCancelled {
      if (!_disposed && identical(_current, task)) onCancelled?.call();
    } catch (error, stackTrace) {
      if (!task._isActive) return;
      if (onError != null) {
        onError(error, stackTrace);
      } else if (errorMessage != null) {
        WywDialog.showToast(message: errorMessage);
      } else {
        rethrow;
      }
    } finally {
      task._dialog?.dismiss();
      if (identical(_current, task)) {
        _current = null;
        if (!_disposed) notifyListeners();
      }
    }
  }

  void cancel() {
    _current?.cancel();
  }

  void _notifyCancellation() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    cancel();
    super.dispose();
  }
}

class WywDialogTask {
  WywDialogTask._(this._owner);

  final WywDialogController _owner;
  final _cancelled = Completer<void>();
  WywDialogHandle<dynamic>? _dialog;
  FutureOr<void> Function()? _onCancel;
  Future<void>? _cancelCleanup;

  bool get _isActive =>
      !_cancelled.isCompleted &&
      !_owner._disposed &&
      identical(_owner._current, this) &&
      (_owner._context?.call().mounted ?? true);

  void withContext(void Function(BuildContext context) action) {
    _checkActive();
    final context = _owner._context?.call();
    if (context == null) {
      throw StateError('This dialog task has no widget owner.');
    }
    action(context);
  }

  void _checkActive() {
    if (!_isActive) throw const _DialogTaskCancelled();
  }

  void cancel() {
    if (_cancelled.isCompleted) return;
    _cancelled.complete();
    _owner._notifyCancellation();
    _dialog?.dismiss();
    final onCancel = _onCancel;
    if (onCancel != null) {
      _cancelCleanup = Future<void>.sync(onCancel).catchError((Object error) {
        debugPrint('Wyw Dialog Error: Task cancellation failed: $error');
      });
    }
  }

  /// Stops waiting, not the operation itself; late errors are still consumed.
  Future<T> wait<T>(Future<T> future) async {
    final result = await Future.any<T>([
      future,
      _cancelled.future.then<T>((_) => throw const _DialogTaskCancelled()),
    ]);
    _checkActive();
    return result;
  }

  Future<T> loading<T>({
    required Future<T> Function() action,
    String? message,
    bool barrierDismissible = false,
    FutureOr<void> Function()? onCancel,
    WidgetBuilder? builder,
  }) async {
    _checkActive();
    final dialog = WywDialogHandle<void>();
    _dialog = dialog;
    _onCancel = onCancel;
    final closed = WywDialog.show<void>(
      context: _owner._context?.call(),
      handle: dialog,
      clickMaskDismiss: barrierDismissible,
      builder: builder ?? (_) => _LoadingDialog(message: message),
    );
    unawaited(closed.then((_) {
      if (identical(_dialog, dialog)) cancel();
    }));
    late T result;
    try {
      if (!dialog.isActive) cancel();
      _checkActive();
      result = await wait(action());
    } finally {
      // A system pop can precede completion of the dialog's Future.
      if (!dialog.isActive) cancel();
      _dialog = null;
      _onCancel = null;
      dialog.dismiss();
      await _cancelCleanup;
      _checkActive();
    }
    return result;
  }

  /// A dismissed choice cancels the workflow; an explicit false remains a result.
  Future<T> show<T extends Object>({
    required WidgetBuilder builder,
    bool clickMaskDismiss = true,
  }) async {
    _checkActive();
    final dialog = WywDialogHandle<T>();
    _dialog = dialog;
    try {
      final result = await wait(WywDialog.show<T>(
        context: _owner._context?.call(),
        handle: dialog,
        clickMaskDismiss: clickMaskDismiss,
        builder: builder,
      ));
      if (result == null) {
        cancel();
        throw const _DialogTaskCancelled();
      }
      return result;
    } finally {
      _dialog = null;
      dialog.dismiss();
    }
  }
}

class _DialogTaskCancelled implements Exception {
  const _DialogTaskCancelled();
}

class _LoadingDialog extends StatelessWidget {
  const _LoadingDialog({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) => Center(
        child: Card(
          elevation: 8,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LoadingIndicator(),
                const SizedBox(height: 16),
                Text(message ?? 'Loading...',
                    style: const TextStyle(fontSize: 16)),
              ],
            ),
          ),
        ),
      );
}
