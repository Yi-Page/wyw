import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/plugins/plugin_category.dart';

/// 分类模型与注册表测试（P2-M2）。
///
/// 核心行为：**未知 `// type:` 值保留为自定义分类**，而不是归并成「其他」。
/// 这是相对旧 `PluginType.parse`（未知值一律 → unknown）的行为变更。
void main() {
  group('PluginCategory 相等性', () {
    test('按 id 判定，跨注册表实例仍然相等', () {
      // 用自定义 id：内置分类是 const 单例，天然 identical，测不出「按 id 相等」。
      final a = PluginCategoryRegistry().resolve('podcast');
      final b = PluginCategoryRegistry().resolve('podcast');
      expect(identical(a, b), isFalse);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('内置分类是 const 单例', () {
      expect(identical(PluginCategoryRegistry().resolve('video'),
          PluginCategory.video), isTrue);
    });

    test('不同 id 不相等', () {
      expect(PluginCategory.video, isNot(PluginCategory.manga));
      expect(PluginCategory.video, isNot(PluginCategory.unknown));
    });
  });

  group('PluginCategory.builtinById', () {
    test('大小写不敏感命中内置分类', () {
      expect(PluginCategory.builtinById('video'), PluginCategory.video);
      expect(PluginCategory.builtinById(' MANGA '), PluginCategory.manga);
      expect(PluginCategory.builtinById('Novel'), PluginCategory.novel);
    });

    test('未内置 / 空值返回 null', () {
      expect(PluginCategory.builtinById('podcast'), isNull);
      expect(PluginCategory.builtinById(null), isNull);
      expect(PluginCategory.builtinById('  '), isNull);
    });
  });

  group('PluginCategory.isUnspecified', () {
    test('null / 空串 / unknown 都算未声明', () {
      expect(PluginCategory.isUnspecified(null), isTrue);
      expect(PluginCategory.isUnspecified(''), isTrue);
      expect(PluginCategory.isUnspecified('   '), isTrue);
      expect(PluginCategory.isUnspecified('unknown'), isTrue);
      expect(PluginCategory.isUnspecified(' UNKNOWN '), isTrue);
    });

    test('其他值都算已声明', () {
      expect(PluginCategory.isUnspecified('video'), isFalse);
      expect(PluginCategory.isUnspecified('podcast'), isFalse);
    });
  });

  group('PluginCategoryRegistry.resolve', () {
    test('命中内置分类，大小写不敏感', () {
      final registry = PluginCategoryRegistry();
      expect(registry.resolve('video'), PluginCategory.video);
      expect(registry.resolve(' Video '), PluginCategory.video);
      expect(registry.resolve('MANGA'), PluginCategory.manga);
    });

    test('空值归为「其他」', () {
      final registry = PluginCategoryRegistry();
      expect(registry.resolve(null), PluginCategory.unknown);
      expect(registry.resolve(''), PluginCategory.unknown);
      expect(registry.resolve('  '), PluginCategory.unknown);
    });

    test('未知 id 保留为隐式自定义分类，而不是归为「其他」', () {
      final registry = PluginCategoryRegistry();
      final category = registry.resolve('podcast');
      expect(category.id, 'podcast');
      expect(category.label, 'podcast');
      expect(category.isBuiltin, isFalse);
      expect(category, isNot(PluginCategory.unknown));
      // 隐式分类用与内置「其他」不同的图标，避免卡片上无法区分
      expect(category.icon, PluginCategory.customIcon);
      expect(category.icon, isNot(PluginCategory.unknown.icon));
    });

    test('隐式自定义分类 id 规范化为小写，大小写变体归为同一个', () {
      final registry = PluginCategoryRegistry();
      final upper = registry.resolve('Podcast');
      final lower = registry.resolve('podcast');
      expect(upper.id, 'podcast');
      expect(lower.id, 'podcast');
      expect(upper, lower);
      // label 取首次出现的拼写
      expect(upper.label, 'Podcast');
    });

    test('重复解析同一个未知 id 返回同一实例', () {
      final registry = PluginCategoryRegistry();
      final first = registry.resolve('podcast');
      final second = registry.resolve('podcast');
      expect(identical(first, second), isTrue);
    });
  });

  group('PluginCategoryRegistry 与用户自定义分类', () {
    test('用户分类覆盖 label 并占用其 id', () {
      final registry = PluginCategoryRegistry(custom: const [
        CustomCategory(id: 'anime', label: '番剧'),
      ]);
      final category = registry.resolve('anime');
      expect(category.id, 'anime');
      expect(category.label, '番剧');
      expect(category.isBuiltin, isFalse);
    });

    test('用户分类 id 大小写不敏感', () {
      final registry = PluginCategoryRegistry(custom: const [
        CustomCategory(id: 'Anime', label: '番剧'),
      ]);
      expect(registry.resolve('anime').label, '番剧');
      expect(registry.resolve('ANIME').label, '番剧');
    });

    test('内置分类不能被用户分类顶掉', () {
      final registry = PluginCategoryRegistry(custom: const [
        CustomCategory(id: 'video', label: '我要改名'),
      ]);
      expect(registry.resolve('video'), PluginCategory.video);
      expect(registry.resolve('video').label, '视频');
      // 被顶掉的条目也不该出现在自定义列表里
      expect(registry.custom, isEmpty);
    });

    test('自定义分类之间同 id 以先登记者为准', () {
      final registry = PluginCategoryRegistry(custom: const [
        CustomCategory(id: 'anime', label: '先'),
        CustomCategory(id: 'ANIME', label: '后'),
      ]);
      expect(registry.resolve('anime').label, '先');
    });

    test('byId 不产生副作用', () {
      final registry = PluginCategoryRegistry();
      expect(registry.byId('podcast'), isNull);
      expect(registry.custom, isEmpty);
    });

    test('label 不参与相等性：重命名分类不会让「按分类筛选」失配', () {
      // 这正是「改了分类展示名后筛选/选中态失效」那类 bug 的守卫：
      // 分类身份只由 id 决定，label 是纯展示数据。
      final before = PluginCategoryRegistry(
        custom: const [CustomCategory(id: 'anime', label: '番剧')],
      ).resolve('anime');
      final after = PluginCategoryRegistry(
        custom: const [CustomCategory(id: 'anime', label: '动画')],
      ).resolve('anime');

      expect(before, after); // 相等性只看 id
      expect(before.hashCode, after.hashCode);
      expect(after.label, '动画'); // 但 label 已更新
      expect(before.label, '番剧');
    });
  });

  group('PluginCategoryRegistry 列表', () {
    test('all = 内置在前（固定顺序）+ 自定义在后', () {
      final registry = PluginCategoryRegistry(custom: const [
        CustomCategory(id: 'anime', label: '番剧'),
      ]);
      registry.resolve('podcast'); // 隐式登记

      final all = registry.all;
      expect(all.take(4).toList(), PluginCategory.builtins);
      expect(all.length, 6);
      expect(all.where((c) => c.isBuiltin).length, 4);
    });

    test('custom 按展示名排序', () {
      final registry = PluginCategoryRegistry(custom: const [
        CustomCategory(id: 'zzz', label: '乙'),
        CustomCategory(id: 'aaa', label: '甲'),
      ]);
      expect(registry.custom.map((c) => c.label).toList(), ['乙', '甲']);
    });

    test('重建注册表会清掉上一轮登记的隐式分类', () {
      final first = PluginCategoryRegistry()..resolve('podcast');
      expect(first.custom, isNotEmpty);

      final second = PluginCategoryRegistry();
      expect(second.custom, isEmpty);
      expect(second.byId('podcast'), isNull);
    });
  });

  group('PluginCategory.custom', () {
    test('工厂方法使用统一的默认视觉属性', () {
      final category = PluginCategory.custom(id: 'anime', label: '番剧');
      expect(category.icon, PluginCategory.customIcon);
      expect(category.color, PluginCategory.customColor);
      expect(category.isBuiltin, isFalse);
    });
  });
}
