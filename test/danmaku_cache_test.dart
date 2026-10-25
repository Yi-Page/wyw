import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:wyw/modules/danmaku/danmaku_module.dart';
import 'package:wyw/services/danmaku/danmaku_cache_service.dart';
import 'package:wyw/utils/danmaku.dart';

DanmakuEntry _entry(String message, double time, {int type = 1}) {
  return DanmakuEntry(
    message: message,
    time: time,
    type: type,
    color: generateDanmakuColor(0xFF0000),
    source: '10086',
  );
}

void main() {
  late Directory tempDir;
  final service = DanmakuCacheService();

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wyw_danmaku_cache_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('写入后能读回，字段完整', () async {
    final danmakus = [
      _entry('第一条', 1.25),
      _entry('第二条', 30.5, type: 5),
    ];
    await service.write(
      directory: tempDir.path,
      episodeId: 17580001,
      libraryTitle: '某番剧',
      danmakus: danmakus,
    );

    expect(await service.hasCache(tempDir.path), isTrue);

    final cached = await service.read(tempDir.path);
    expect(cached, isNotNull);
    expect(cached!.episodeId, 17580001);
    expect(cached.libraryTitle, '某番剧');
    expect(cached.danmakus, hasLength(2));
    expect(cached.danmakus.first.message, '第一条');
    expect(cached.danmakus.first.time, 1.25);
    expect(cached.danmakus.last.type, 5);
    expect(cached.danmakus.last.time, 30.5);
  });

  test('目录不存在时读取返回 null，不抛异常', () async {
    expect(await service.read(path.join(tempDir.path, 'not_created')), isNull);
    expect(await service.hasCache(path.join(tempDir.path, 'not_created')),
        isFalse);
  });

  test('空目录参数一律按"没有缓存"处理', () async {
    expect(await service.read(''), isNull);
    expect(await service.hasCache(''), isFalse);
    await service.write(
      directory: '',
      episodeId: 1,
      libraryTitle: 'x',
      danmakus: [_entry('a', 1)],
    );
    expect(await service.hasCache(''), isFalse);
  });

  test('弹幕为空时不落文件', () async {
    await service.write(
      directory: tempDir.path,
      episodeId: 1,
      libraryTitle: 'x',
      danmakus: const [],
    );
    expect(await service.hasCache(tempDir.path), isFalse);
  });

  test('缓存文件损坏时返回 null 并顺手删除，避免每次播放都踩同一个坏文件', () async {
    final file = File(path.join(tempDir.path, DanmakuCacheService.fileName));
    await file.writeAsString('{ 这不是合法 JSON');

    expect(await service.read(tempDir.path), isNull);
    expect(await file.exists(), isFalse, reason: '损坏文件应被清掉');
  });

  test('只有空 comments 的文件同样视为无缓存', () async {
    final file = File(path.join(tempDir.path, DanmakuCacheService.fileName));
    await file.writeAsString('{"episodeId":1,"comments":[]}');

    expect(await service.read(tempDir.path), isNull);
  });

  test('delete 之后不再有缓存', () async {
    await service.write(
      directory: tempDir.path,
      episodeId: 1,
      libraryTitle: 'x',
      danmakus: [_entry('a', 1)],
    );
    expect(await service.hasCache(tempDir.path), isTrue);

    await service.delete(tempDir.path);
    expect(await service.hasCache(tempDir.path), isFalse);
  });
}
