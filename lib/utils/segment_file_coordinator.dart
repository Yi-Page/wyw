import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';

/// 分片/密钥文件的跨组件落盘协调器（播放代理 ↔ 下载管理器共享同一下载目录）。
///
/// 背景：播放即下载时，[DownloadManager] 与本地播放代理可能并发下载同一个
/// 分片/密钥。旧实现两者都写同一个 `seg_00000.ts.tmp` 再 rename 到最终文件：
///  - 两个写入者会互相截断/覆写同一个 .tmp；
///  - Windows 上对正在被读取的目标文件执行 rename 会抛
///    `PathAccessException: 另一个程序正在使用此文件`（errno 32），
///    进而导致分片请求 502、播放器反复重试。
///
/// 本类保证：
///   1. [runExclusive]：同一最终路径同一时刻只有一个下载-发布流程，
///      第二个调用方直接复用第一个的结果（同源地址内容一致），
///      实现“同一分片只从源站拉取一次”的设计意图；
///   2. [uniqueTempPath]：每个写入者的临时文件带唯一后缀，互不覆写，
///      同时登记为“活跃写入”，供清理逻辑区分“正在写”与“残留”；
///   3. [publish]：rename 带指数退避重试；若最终文件已被其它写入者
///      完整发布（存在且非空），直接复用并丢弃自己的临时文件。
class SegmentWriteCoordinator {
  SegmentWriteCoordinator._();

  static final SegmentWriteCoordinator instance = SegmentWriteCoordinator._();

  final Map<String, Future<List<int>>> _inFlight = {};

  /// 当前仍处于「下载写入中」的唯一临时文件路径。
  /// DownloadManager 的临时文件清理（`*.tmp*` 扫描）用它跳过正在写入的
  /// 文件，避免把播放代理并发下载到一半的临时文件删掉，导致
  /// 「播放即下载」中已播放的分片落盘失败（502 后丢失）。
  final Set<String> _activeTempPaths = <String>{};
  final Random _random = Random();
  int _counter = 0;

  /// 归一化路径，消除播放代理与下载管理器在构造同一路径时
  /// 可能出现的分隔符差异（如 `\` 与 `/`），保证登记/查询一致。
  String _normPath(String path) => path.replaceAll('\\', '/');

  /// 生成唯一的临时文件路径（同进程内并发安全）。
  /// 生成的路径会登记为「活跃」，直到 [publish] 结束或调用方主动
  /// 调用 [releaseTempPath] 释放。
  String uniqueTempPath(String savePath) {
    _counter++;
    final token = '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
        '-${_counter.toRadixString(36)}'
        '-${_random.nextInt(0xFFFFFF).toRadixString(36)}';
    final tmpPath = '$savePath.tmp.$token';
    _activeTempPaths.add(_normPath(tmpPath));
    return tmpPath;
  }

  /// 放弃一个临时文件路径（删除该临时文件后调用）。
  void releaseTempPath(String tmpPath) {
    _activeTempPaths.remove(_normPath(tmpPath));
  }

  /// 该临时文件路径当前是否仍属于某个正在进行的写入。
  bool isActiveTempPath(String tmpPath) =>
      _activeTempPaths.contains(_normPath(tmpPath));

  /// 同一 [key]（最终文件路径）上的写入互斥：已有写入者在跑时，
  /// 直接等待它完成并复用其结果；否则执行 [task] 并登记为共享 future。
  Future<List<int>> runExclusive(
      String key, Future<List<int>> Function() task) {
    final existing = _inFlight[key];
    if (existing != null) return existing;
    final future = task();
    _inFlight[key] = future;
    // 任务完成后清理登记（仅当仍指向本次 future，避免误删后来者）；
    // 错误由原 future 的调用方负责，这里订阅一次避免未处理异常。
    unawaited(future.then<void>((_) {}, onError: (Object e, StackTrace s) {
      WywLogger().w('${LogTag.download} 分片互斥下载任务失败（不影响主流程）', error: e);
    }).whenComplete(() {
      if (identical(_inFlight[key], future)) {
        _inFlight.remove(key);
      }
    }));
    return future;
  }

  /// 把写完整的临时文件发布为最终文件：
  ///  - 最终文件已存在且非空 → 复用（删除自己的临时文件后直接返回）；
  ///  - 否则 rename，失败（目标被占用等）则指数退避重试；
  ///  - 重试耗尽且仍无完整目标 → 清理临时文件并抛错。
  /// 无论成功/复用/失败，都会把该临时文件从“活跃写入”登记中释放。
  Future<void> publish({
    required String tmpPath,
    required String savePath,
    int maxRetries = 8,
  }) async {
    final tmp = File(tmpPath);
    final target = File(savePath);
    try {
      if (!await tmp.exists()) return;

      for (int attempt = 0; attempt < maxRetries; attempt++) {
        if (await _isComplete(target)) {
          try {
            await tmp.delete();
          } catch (_) {
            // 静默可接受：复用已发布目标时清理自己的临时文件，失败无害
          }
          return;
        }
        if (attempt > 0) {
          await Future.delayed(
              Duration(milliseconds: 50 * (1 << (attempt - 1))));
        }
        try {
          await tmp.rename(savePath);
          return;
        } on FileSystemException catch (e, s) {
          WywLogger().w(
              '${LogTag.download} 分片发布 rename 重试 attempt=$attempt'
              ' tmp=$tmpPath save=$savePath errno=${e.osError?.errorCode}',
              error: e,
              stackTrace: s);
        }
      }

      // 重试后目标可能已被其它写入者完成 → 复用
      if (await _isComplete(target)) {
        try {
          await tmp.delete();
        } catch (_) {
          // 静默可接受：复用已发布目标时清理自己的临时文件，失败无害
        }
        return;
      }
      try {
        await tmp.delete();
      } catch (_) {
        // 静默可接受：发布失败前的临时文件清理，失败不影响随后抛出的错误
      }
      throw FileSystemException('Failed to publish segment file', savePath);
    } finally {
      // 无论发布成功/复用/失败，该临时文件都不再属于活跃写入。
      _activeTempPaths.remove(_normPath(tmpPath));
    }
  }

  Future<bool> _isComplete(File target) async {
    try {
      return await target.exists() && await target.length() > 0;
    } catch (_) {
      // 静默可接受：探测目标文件状态失败（可能正被并发读写占用），按未完成处理
      return false;
    }
  }
}
