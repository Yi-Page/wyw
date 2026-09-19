import 'dart:async';
import 'dart:io';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:wyw/services/logging/background_logger.dart';
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';

/// Android 后台下载服务
///
/// 使用 Foreground Service 保持 app 进程存活，防止系统在后台时杀死下载进程。
/// 下载逻辑仍在主 Isolate 运行，此服务仅负责：
/// 1. 显示通知栏进度
/// 2. 保持进程存活
/// 3. 提供通知栏交互（暂停全部）
class BackgroundDownloadService {
  static final BackgroundDownloadService _instance =
      BackgroundDownloadService._internal();
  factory BackgroundDownloadService() => _instance;
  BackgroundDownloadService._internal();

  bool _isInitialized = false;
  bool _isRunning = false;

  void Function()? onPauseAll;
  void Function()? onNavigateToDownloadRequested;

  /// 返回 true 表示用户同意请求权限，false 表示用户拒绝
  Future<bool> Function()? onNotificationPermissionRequired;

  bool get isSupported => Platform.isAndroid;
  bool get isRunning => _isRunning;
  Future<void> init() async {
    if (!isSupported || _isInitialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'wyw_download_channel',
        channelName: '下载服务',
        channelDescription: '视频下载后台服务',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    FlutterForegroundTask.initCommunicationPort();

    _isInitialized = true;
    WywLogger().i('${LogTag.download} 后台下载服务已初始化');
  }

  Future<bool> needsNotificationPermission() async {
    if (!isSupported) return false;
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    return permission != NotificationPermission.granted;
  }

  Future<bool> requestNotificationPermission() async {
    if (!isSupported) return true;
    final result = await FlutterForegroundTask.requestNotificationPermission();
    return result == NotificationPermission.granted;
  }

  Future<bool> startService() async {
    if (!isSupported) return false;
    if (_isRunning) return true;

    if (!_isInitialized) {
      await init();
    }

    final needsPermission = await needsNotificationPermission();
    if (needsPermission) {
      if (onNotificationPermissionRequired != null) {
        final userAgreed = await onNotificationPermissionRequired!();
        if (userAgreed) {
          final granted = await requestNotificationPermission();
          if (!granted) {
            WywLogger().w('${LogTag.download} 通知权限授予失败（用户已同意弹窗）');
          }
        } else {
          WywLogger().i('${LogTag.download} 用户在权限弹窗中选择拒绝');
        }
      } else {
        // 没有设置回调，直接请求权限（兼容旧行为）
        final granted = await requestNotificationPermission();
        if (!granted) {
          WywLogger().w('${LogTag.download} 通知权限未授予');
        }
      }
    }

    try {
      final result = await FlutterForegroundTask.startService(
        notificationTitle: '正在下载',
        notificationText: '准备中...',
        notificationButtons: [
          const NotificationButton(id: 'pause_all', text: '暂停全部'),
        ],
        callback: _backgroundCallback,
      );

      _isRunning = result is ServiceRequestSuccess;

      if (_isRunning) {
        // 主动下发日志文件路径（任务 isolate 中 path_provider 不可用，
        // 由主 isolate 代为解析后经通信端口下发）。
        unawaited(_sendLogPathToTask());
        WywLogger().i('${LogTag.download} 后台下载服务已启动');
      } else {
        WywLogger().w('${LogTag.download} 后台服务启动返回非成功: $result');
      }
      return _isRunning;
    } catch (e) {
      WywLogger().e('${LogTag.download} 后台服务启动失败', error: e);
      return false;
    }
  }

  /// 把日志文件绝对路径下发到任务 isolate。
  ///
  /// 任务 isolate（[TaskHandler] 回调）中 path_provider 的 MethodChannel
  /// 不可用，无法自行解析日志路径，由主 isolate 代为解析后经通信端口下发；
  /// 任务侧未收到路径前日志先缓冲（见 `BackgroundFileLogger`）。
  Future<void> _sendLogPathToTask() async {
    try {
      final path = (await getLogsPath()).path;
      FlutterForegroundTask.sendDataToTask({
        'action': 'log_path',
        'path': path,
      });
    } catch (e) {
      WywLogger().w('${LogTag.download} 后台日志路径下发失败', error: e);
    }
  }

  Future<void> stopService() async {
    if (!isSupported || !_isRunning) return;

    try {
      await FlutterForegroundTask.stopService();
      _isRunning = false;
      WywLogger().i('${LogTag.download} 后台下载服务已停止');
    } catch (e) {
      WywLogger().e('${LogTag.download} 后台服务停止失败', error: e);
    }
  }

  Future<void> updateNotification({
    required String title,
    required String text,
  }) async {
    if (!isSupported || !_isRunning) return;

    try {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: text,
      );
    } catch (e) {
      WywLogger().d('${LogTag.download} 后台通知更新失败（已忽略，不影响下载）', error: e);
    }
  }

  Future<void> updateProgress({
    required int activeCount,
    required int totalCount,
    required double overallProgress,
    required String speedText,
  }) async {
    if (!isSupported || !_isRunning) return;

    String title;
    String text;

    if (activeCount == 0) {
      title = '下载已暂停';
      text = '共 $totalCount 个任务';
    } else {
      final percent = (overallProgress * 100).toInt();
      title = '正在下载 ($activeCount/$totalCount)';
      text = '$percent% · $speedText';
    }

    await updateNotification(title: title, text: text);
  }

  void handleNotificationAction(String buttonId) {
    if (buttonId == 'pause_all') {
      onPauseAll?.call();
    }
  }

  void handleNavigateToDownload() {
    onNavigateToDownloadRequested?.call();
  }

  /// 注册主 isolate 的任务数据回调。
  ///
  /// 内部先拦截任务侧发来的 `request_log_path`（任务 isolate 启动时可能早于
  /// 主侧的主动推送，这里按请求补发日志路径），其余数据转发给业务回调。
  void addTaskDataCallback(void Function(Object) callback) {
    FlutterForegroundTask.addTaskDataCallback((Object data) {
      if (data is Map && data['action'] == 'request_log_path') {
        unawaited(_sendLogPathToTask());
        return;
      }
      callback(data);
    });
  }

  void removeTaskDataCallback(void Function(Object) callback) {
    FlutterForegroundTask.removeTaskDataCallback(callback);
  }
}

/// 后台任务回调（在独立 Isolate 中运行）
///
/// 注意：此回调主要用于保持服务存活和处理通知交互。
/// 实际下载逻辑在主 Isolate 中运行。
@pragma('vm:entry-point')
void _backgroundCallback() {
  FlutterForegroundTask.setTaskHandler(_DownloadTaskHandler());
}

/// 后台 isolate 中的任务处理器。
///
/// 这里不能直接用 WywLogger：其文件落盘依赖 path_provider 的 MethodChannel，
/// 而本类回调运行在后台 isolate，平台通道不可用。改用 `BackgroundFileLogger`
/// （纯 dart:io），日志文件路径由主 isolate 通过通信端口下发
/// （见 `BackgroundDownloadService._sendLogPathToTask`）。
class _DownloadTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // 请求主 isolate 下发日志文件路径：防止主侧的主动推送早于本 isolate
    // 通信端口就绪而丢失；收到前日志先在 BackgroundFileLogger 缓冲。
    FlutterForegroundTask.sendDataToMain({'action': 'request_log_path'});
    BackgroundFileLogger.i(LogTag.download, '后台任务处理器启动 starter=$starter');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // eventAction 配置为 nothing，不会触发
  }

  @override
  void onNotificationButtonPressed(String id) {
    BackgroundFileLogger.i(LogTag.download, '通知按钮点击 id=$id');
    FlutterForegroundTask.sendDataToMain(
        {'action': 'button_pressed', 'id': id});
  }

  @override
  void onNotificationPressed() {
    BackgroundFileLogger.i(LogTag.download, '通知栏点击，唤起应用');
    FlutterForegroundTask.sendDataToMain({'action': 'navigate_to_download'});
    FlutterForegroundTask.launchApp();
  }

  @override
  void onNotificationDismissed() {
    // 前台服务通知通常不可划掉
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    BackgroundFileLogger.i(LogTag.download, '后台任务处理器销毁 isTimeout=$isTimeout');
  }

  @override
  void onReceiveData(Object data) {
    if (data is Map && data['action'] == 'log_path' && data['path'] is String) {
      BackgroundFileLogger.setPath(data['path'] as String);
      BackgroundFileLogger.i(LogTag.download, '已接收日志文件路径，后台日志开始落盘');
      return;
    }
    BackgroundFileLogger.i(LogTag.download, '收到主 isolate 数据: $data');
  }
}
