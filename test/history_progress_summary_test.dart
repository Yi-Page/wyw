import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/pages/history/history_progress_summary.dart';
import 'package:wyw/services/storage/history_entry.dart';
import 'package:wyw/services/storage/history_progress.dart';
import 'package:wyw/services/storage/history_type.dart';
import 'package:wyw/services/storage/video_play_model.dart';

/// 进度摘要（历史页「继续观看」与「已删除」弹窗共用）的回归。
///
/// 从 `history_page.dart` 抽出后，这条逻辑必须保持原样——否则两处展示会漂移。
void main() {
  HistoryEntry video({int positionMs = 754000, int durationMs = 1500000}) =>
      HistoryEntry(
        sourceId: 'v1',
        type: HistoryType.video,
        title: '视频',
        cover: '',
        lastWatchTime: DateTime(2026, 1, 1),
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
                    positionMs: i == 3 ? positionMs : 0,
                    durationMs: i == 3 ? durationMs : 0,
                  ),
              ],
            ),
          ],
          lastEpisodeIndex: 2,
        ).toMap(),
      );

  HistoryEntry comic({int chapterCount = 20, int lastChapterIndex = 4}) =>
      HistoryEntry(
        sourceId: 'c1',
        type: HistoryType.comic,
        title: '漫画',
        cover: '',
        lastWatchTime: DateTime(2026, 1, 1),
        progress: ComicProgress(
          chapterId: 'ch${lastChapterIndex + 1}',
          pageIndex: 3,
          chapters: [
            for (var i = 1; i <= chapterCount; i++)
              {'id': 'ch$i', 'title': '第 $i 话'},
          ],
          lastChapterIndex: lastChapterIndex,
        ).toMap(),
      );

  HistoryEntry novel({int chapterCount = 30, int chapter = 7}) => HistoryEntry(
        sourceId: 'n1',
        type: HistoryType.novel,
        title: '小说',
        cover: '',
        lastWatchTime: DateTime(2026, 1, 1),
        progress: ReadProgress(
          chapterId: 'n$chapter',
          chapter: chapter,
          chapters: [
            for (var i = 1; i <= chapterCount; i++) {'id': 'n$i', 'title': '第 $i 章'},
          ],
        ).toMap(),
      );

  group('historyProgressSummary', () {
    test('视频：集号 + 播放位置', () {
      expect(historyProgressSummary(video()), '第 3 集 · 12:34');
    });

    test('视频：无时长时只显示集号', () {
      expect(historyProgressSummary(video(durationMs: 0)), '第 3 集');
    });

    test('漫画：当前话 / 总话数', () {
      expect(historyProgressSummary(comic()), '第 5/20 话');
    });

    test('漫画：章节列表为空时返回 null', () {
      final entry = HistoryEntry(
        sourceId: 'c1',
        type: HistoryType.comic,
        title: '漫画',
        cover: '',
        lastWatchTime: DateTime(2026, 1, 1),
        progress: const ComicProgress(chapterId: 'x', pageIndex: 0).toMap(),
      );
      expect(historyProgressSummary(entry), isNull);
    });

    test('小说：当前章 / 总章数', () {
      expect(historyProgressSummary(novel()), '第 7/30 章');
    });

    test('custom 类型无进度语义 → null', () {
      final entry = HistoryEntry(
        sourceId: 'x',
        type: HistoryType.custom,
        title: '自定义',
        cover: '',
        lastWatchTime: DateTime(2026, 1, 1),
        progress: const {'foo': 'bar'},
      );
      expect(historyProgressSummary(entry), isNull);
    });
  });

  group('formatHistoryPosition', () {
    test('毫秒 → m:ss（秒补零）', () {
      expect(formatHistoryPosition(0), '0:00');
      expect(formatHistoryPosition(5000), '0:05');
      expect(formatHistoryPosition(65000), '1:05');
      expect(formatHistoryPosition(754000), '12:34');
    });
  });

  group('类型展示', () {
    test('中文名与图标', () {
      expect(historyTypeLabel(HistoryType.video), '视频');
      expect(historyTypeLabel(HistoryType.comic), '漫画');
      expect(historyTypeLabel(HistoryType.novel), '小说');
      expect(historyTypeLabel(HistoryType.custom), '其它');
      for (final type in HistoryType.values) {
        expect(historyTypeIcon(type), isNotNull);
      }
    });
  });
}
