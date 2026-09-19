import 'dart:async';

import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';

/// Runs asynchronous operations one at a time in submission order.
class AsyncSerialQueue {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final completer = Completer<T>();
    _tail = (() async {
      try {
        await previous;
      } catch (e) {
        // 前一任务的错误已通过 completer 回传给其调用方，这里仅为排队续接。
        WywLogger().d('${LogTag.app} 串行队列等待前一个任务失败（已忽略）', error: e);
      }
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    })();
    return completer.future;
  }
}
