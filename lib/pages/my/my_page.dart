import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:wyw/bean/appbar/app_bar_menu_button.dart';
import 'package:wyw/bean/appbar/sys_app_bar.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';
import 'package:wyw/pages/my/manual_play_dialog.dart';
import 'package:wyw/pages/my/my_space_view.dart';
import 'package:wyw/pages/video/video_route_args.dart';
import 'package:wyw/repositories/i_history_repository.dart';
import 'package:wyw/services/storage/history_type.dart';
import 'package:wyw/services/storage/video_play_model.dart';

class MyPage extends StatefulWidget {
  const MyPage({super.key});

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  void onBackPressed(BuildContext context) {
    if (WywDialog.observer.hasWywDialog) {
      WywDialog.dismiss();
      return;
    }
    context.navigate('/tab/search/');
  }

  /// 手动播放入口：弹窗收集地址/名称/资源类型后进入播放页。
  ///
  /// 地址同时作为 videoId（历史 key），播放页回吐的进度据此落盘，
  /// 下次从同一地址进入（或从历史页）可续播。
  Future<void> _openManualPlay(BuildContext context) async {
    final request = await showManualPlayDialog(context);
    if (request == null || !context.mounted) return;
    final title = request.displayTitle;
    context.pushNamed(
      '/video/',
      arguments: VideoPageRouteArgs(
        videoId: request.url,
        title: title,
        sources: [
          VideoPlaySource(
            name: '手动输入',
            episodes: [
              VideoPlayEpisode(
                name: title,
                path: PlayResourcePath(url: request.url, type: request.type),
              ),
            ],
          ),
        ],
        onProgressChanged: (progress) {
          inject<IHistoryRepository>().setProgress(
            type: HistoryType.video,
            sourceId: request.url,
            title: title,
            progress: progress.toMap(),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        title: Text('我的'),
        needTopOffset: false,
        actions: const [WywAppBarMenuButton(pagePath: '/tab/my/')],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: MySpaceView(
          onOpen: (destination) {
            switch (destination) {
              case MySpaceDestination.manualPlay:
                _openManualPlay(context);
              case MySpaceDestination.jsConsole:
                context.pushNamed('/js-dev/');
              case MySpaceDestination.history:
                context.pushNamed('/history/');
              case MySpaceDestination.downloads:
                context.pushNamed('/settings/download/');
              case MySpaceDestination.settings:
                context.pushNamed('/settings/');
            }
          },
        ),
      ),
    );
  }
}
