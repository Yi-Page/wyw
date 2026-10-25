import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/pages/history/history_deleted_dialog.dart';
import 'package:wyw/services/storage/history_entry.dart';
import 'package:wyw/services/storage/history_progress.dart';
import 'package:wyw/services/storage/history_type.dart';
import 'package:wyw/services/storage/video_play_model.dart';
import 'package:wyw/utils/deleted_ledger.dart';

/// 历史页「本次已删除」弹窗的行内容（外壳行为见 `deleted_entries_shell_test.dart`）。
void main() {
  HistoryEntry videoEntry() => HistoryEntry(
        sourceId: 'v1',
        type: HistoryType.video,
        title: '视频 A',
        cover: '',
        lastWatchTime: DateTime.now().subtract(const Duration(hours: 2)),
        progress: VideoPlaybackProgress(
          videoId: 'v1',
          sources: [
            VideoPlaySource(
              name: '线路 1',
              episodes: [
                for (var i = 1; i <= 3; i++)
                  VideoPlayEpisode(
                    name: '第 $i 集',
                    path: const PlayResourcePath(
                      url: 'http://example.com/v.mp4',
                      type: PlayPathType.direct,
                    ),
                    positionMs: i == 3 ? 754000 : 0,
                    durationMs: i == 3 ? 1500000 : 0,
                  ),
              ],
            ),
          ],
          lastEpisodeIndex: 2,
        ).toMap(),
      );

  HistoryEntry comicEntry() => HistoryEntry(
        sourceId: 'c1',
        type: HistoryType.comic,
        title: '漫画 B',
        cover: '',
        lastWatchTime: DateTime.now().subtract(const Duration(hours: 5)),
        progress: ComicProgress(
          chapterId: 'ch5',
          pageIndex: 3,
          chapters: [
            for (var i = 1; i <= 20; i++) {'id': 'ch$i', 'title': '第 $i 话'},
          ],
          lastChapterIndex: 4,
        ).toMap(),
      );

  DeletedRecord<HistoryEntry> record(HistoryEntry e) =>
      (item: e, deletedAt: DateTime.now().subtract(const Duration(minutes: 1)));

  Future<void> pump(
    WidgetTester tester, {
    required List<DeletedRecord<HistoryEntry>> entries,
    required Future<void> Function(HistoryEntry) onRestore,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showHistoryDeletedDialog(
                  context,
                  entries: entries,
                  onRestore: onRestore,
                  onRestoreAll: (_) async {},
                  onClear: () {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('行内容：标题 / 类型 / 进度摘要 / 上次观看 / 删除时间', (tester) async {
    await pump(
      tester,
      entries: [record(videoEntry()), record(comicEntry())],
      onRestore: (_) async {},
    );

    expect(find.text('视频 A'), findsOneWidget);
    expect(find.text('漫画 B'), findsOneWidget);
    expect(find.text('视频'), findsOneWidget);
    expect(find.text('漫画'), findsOneWidget);
    // 进度摘要（与历史页「继续观看」同源）
    expect(find.textContaining('第 3 集 · 12:34'), findsOneWidget);
    expect(find.textContaining('第 5/20 话'), findsOneWidget);
    expect(find.textContaining('上次观看'), findsWidgets);
    expect(find.textContaining('删除'), findsWidgets);
    expect(find.text('恢复'), findsNWidgets(2));
    // 历史页专属副标题
    expect(find.textContaining('恢复后回到原来的位置与进度'), findsOneWidget);
  });

  testWidgets('单条恢复回调收到该条目', (tester) async {
    final restored = <String>[];
    await pump(
      tester,
      entries: [record(videoEntry()), record(comicEntry())],
      onRestore: (e) async => restored.add(e.sourceId),
    );

    await tester.tap(find.text('恢复').first);
    await tester.pumpAndSettle();

    expect(restored, ['v1']);
    expect(find.text('视频 A'), findsNothing);
    expect(find.text('漫画 B'), findsOneWidget);
  });
}
