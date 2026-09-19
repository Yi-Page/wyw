import 'dart:async';

import 'package:flutter/services.dart';

/// 音量键翻页监听（Android）。
///
/// 复刻自 venera 的实现：通过原生 EventChannel 接收音量键事件。
/// 注意：需要 Android 原生侧实现 `wyw/reader_volume` 频道（原生代码在
/// `android/app/src/main/...` 的 MainActivity 中注册），否则监听会静默失败。
class VolumeListener {
  static const channel = EventChannel('wyw/reader_volume');

  void Function()? onUp;

  void Function()? onDown;

  VolumeListener({this.onUp, this.onDown});

  StreamSubscription? stream;

  void listen() {
    try {
      stream = channel.receiveBroadcastStream().listen(onEvent);
    } catch (_) {
      // 静默可接受：原生音量频道未实现属预期分支
    }
  }

  void onEvent(dynamic event) {
    if (event == 1) {
      onUp!();
    } else if (event == 2) {
      onDown!();
    }
  }

  void cancel() {
    stream?.cancel();
    stream = null;
  }
}
