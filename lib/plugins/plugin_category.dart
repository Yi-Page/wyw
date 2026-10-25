import 'package:flutter/material.dart';

/// 分类可选的**图标调色板**。
///
/// 落盘的是字符串 key 而不是 [IconData]：release 构建的 `--tree-shake-icons` 会
/// 剔除未被**编译期常量**引用的字形，运行时 `IconData(codePoint)` 会被判定为
/// 不可 tree-shake 而**直接构建失败**。所以候选全是常量，用户的选择只记一个 key。
/// 未知 key / 空串回落到 [fallback]，调色板可随时增删而不读崩旧数据。
abstract final class CategoryIcons {
  /// 未选择 / 未知 key 时的默认图标（刻意区别于「其他」分类的 `Icons.extension`）。
  static const IconData fallback = Icons.label_outline;

  /// 调色板：key（落盘值）-> 图标。顺序即选择器里的排列顺序。
  static const Map<String, IconData> palette = {
    'movie': Icons.movie_outlined,
    'tv': Icons.live_tv_outlined,
    'theater': Icons.theaters_outlined,
    'book': Icons.menu_book_outlined,
    'article': Icons.article_outlined,
    'comic': Icons.auto_stories_outlined,
    'music': Icons.music_note_outlined,
    'album': Icons.library_music_outlined,
    'podcast': Icons.podcasts_outlined,
    'game': Icons.sports_esports_outlined,
    'console': Icons.videogame_asset_outlined,
    'sport': Icons.sports_basketball_outlined,
    'fitness': Icons.fitness_center_outlined,
    'photo': Icons.photo_library_outlined,
    'camera': Icons.camera_alt_outlined,
    'art': Icons.palette_outlined,
    'brush': Icons.brush_outlined,
    'science': Icons.science_outlined,
    'school': Icons.school_outlined,
    'history': Icons.history_edu_outlined,
    'food': Icons.restaurant_outlined,
    'travel': Icons.flight_outlined,
    'world': Icons.public_outlined,
    'pet': Icons.pets_outlined,
    'spark': Icons.bolt_outlined,
    'star': Icons.star_border,
    'heart': Icons.favorite_border,
    'medal': Icons.emoji_events_outlined,
    'explore': Icons.explore_outlined,
  };

  /// key -> 图标；空串 / 未知 key 回落 [fallback]。
  static IconData resolve(String? key) {
    final clean = key?.trim() ?? '';
    if (clean.isEmpty) return fallback;
    return palette[clean] ?? fallback;
  }

  /// 该 key 是否是调色板里的合法条目（选择器用它标记「未选择」）。
  static bool contains(String? key) =>
      palette.containsKey(key?.trim() ?? '');
}

/// 用户自定义分类的**持久化定义**。
///
/// 落盘在 `categories.json`（见 `plugin_category_index.dart`），与 `index.json` 对称：
/// 整个文件是一个数组，一条记录一个分类。
///
/// 注意与 [PluginCategory] 的分工：
///   - [CustomCategory] = 用户数据（id + label + iconKey），**落盘**；
///   - [PluginCategory] = 解析后的视图模型（含 `IconData` / 配色 / 是否内置），**不落盘**。
class CustomCategory {
  const CustomCategory({
    required this.id,
    required this.label,
    this.iconKey = '',
  });

  /// 分类 id（如 `anime`）。插件的 `categoryId` 即指向它。
  final String id;

  /// 展示名（如 `番剧`）
  final String label;

  /// 图标 key（[CategoryIcons.palette] 的键）；空串 / 未知 → 默认图标。
  ///
  /// **不存 [IconData]**，原因见 [CategoryIcons] 的说明。
  final String iconKey;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'icon': iconKey,
      };

  /// 反序列化；无法得到有效 id / label 时返回 null（由调用方跳过该条目）。
  ///
  /// 兼容裸字符串形态（`"番剧"`）与缺 `id` 的旧对象形态 —— `id` 缺省时由调用方
  /// 补，这里只负责读字段。
  static CustomCategory? fromJson(Object? raw, {String? fallbackId}) {
    if (raw is String) {
      final label = raw.trim();
      final id = fallbackId?.trim() ?? '';
      if (id.isEmpty || label.isEmpty) return null;
      return CustomCategory(id: id, label: label);
    }
    if (raw is! Map) return null;

    final id = raw['id']?.toString().trim() ?? fallbackId?.trim() ?? '';
    final label = raw['label']?.toString().trim() ?? '';
    if (id.isEmpty || label.isEmpty) return null;

    return CustomCategory(
      id: id,
      label: label,
      iconKey: raw['icon']?.toString().trim() ?? '',
    );
  }

  CustomCategory copyWith({String? label, String? iconKey}) => CustomCategory(
        id: id,
        label: label ?? this.label,
        iconKey: iconKey ?? this.iconKey,
      );

  @override
  String toString() =>
      'CustomCategory($id, $label${iconKey.isEmpty ? '' : ', icon=$iconKey'})';
}

/// 解析后的**分类视图模型**：内置分类、用户自定义分类共用它。
///
/// **相等性按 [id] 判定**：分类实例会随注册表重建而更换（每次 rescan），但同一个
/// id 必须视为同一个分类 —— 否则「按分类筛选」在配置刷新后会失配。
@immutable
class PluginCategory {
  const PluginCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    this.isBuiltin = false,
  });

  /// 「其他」的固定 id。声明为该值时等价于「未声明」，会继续回退到方法推断。
  static const String unknownId = 'unknown';

  /// 分类 id（小写规范形式）
  final String id;

  /// 展示名
  final String label;

  /// 分类图标（由 [CategoryIcons] 按落盘 key 解析得到）
  final IconData icon;

  /// 分类标识色：categorical palette，M3 无对应 token，作为"数据"挂在模型上
  /// （与主题种子色列表同性质，规范见 docs/ui-routing-design-spec.md 8A 节）。
  final Color color;

  /// 是否为应用内置分类（内置分类的顺序与配色由代码固定）
  final bool isBuiltin;

  // ===== 内置分类 =====

  static const PluginCategory video = PluginCategory(
    id: 'video',
    label: '视频',
    icon: Icons.movie_outlined,
    color: Colors.redAccent,
    isBuiltin: true,
  );

  static const PluginCategory manga = PluginCategory(
    id: 'manga',
    label: '漫画',
    icon: Icons.menu_book_outlined,
    color: Colors.blueAccent,
    isBuiltin: true,
  );

  static const PluginCategory novel = PluginCategory(
    id: 'novel',
    label: '小说',
    icon: Icons.article_outlined,
    color: Colors.green,
    isBuiltin: true,
  );

  static const PluginCategory unknown = PluginCategory(
    id: unknownId,
    label: '其他',
    icon: Icons.extension,
    color: Colors.grey,
    isBuiltin: true,
  );

  /// 内置分类（顺序固定：UI 菜单依赖这个顺序）
  static const List<PluginCategory> builtins = [video, manga, novel, unknown];

  /// 自定义分类未选图标时的默认图标（= [CategoryIcons.fallback]）
  static const IconData customIcon = CategoryIcons.fallback;

  /// 自定义分类的统一标识色
  static const Color customColor = Colors.grey;

  /// 构造一个自定义分类；[icon] 不传时取默认图标。
  factory PluginCategory.custom({
    required String id,
    required String label,
    IconData? icon,
  }) =>
      PluginCategory(
        id: id,
        label: label,
        icon: icon ?? customIcon,
        color: customColor,
      );

  /// 在内置分类里按 id 查找（大小写不敏感）；找不到返回 null。
  static PluginCategory? builtinById(String? id) {
    final key = id?.trim().toLowerCase();
    if (key == null || key.isEmpty) return null;
    for (final category in builtins) {
      if (category.id == key) return category;
    }
    return null;
  }

  /// 分类 id 的「未指定」判定：null / 空串 / `unknown` 都视为未声明。
  static bool isUnspecified(String? id) {
    if (id == null) return true;
    final text = id.trim();
    return text.isEmpty || text.toLowerCase() == unknownId;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is PluginCategory && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PluginCategory($id, $label)';
}

/// 分类注册表：内置分类 + 用户自定义分类。
///
/// 匹配一律**大小写不敏感**：`video` 与 `Video` 命中同一个内置分类；
/// 自定义分类的 id 统一取小写。
class PluginCategoryRegistry {
  PluginCategoryRegistry({Iterable<CustomCategory> custom = const []}) {
    for (final category in PluginCategory.builtins) {
      _byId[category.id] = category;
    }
    for (final item in custom) {
      final id = item.id.trim().toLowerCase();
      if (id.isEmpty) continue;
      // 内置分类不可被用户自定义顶掉（'video' 永远是「视频」）；
      // 自定义之间同 id 也以先登记者为准。
      if (_byId.containsKey(id)) continue;
      _byId[id] = PluginCategory.custom(
        id: id,
        label: item.label,
        icon: CategoryIcons.resolve(item.iconKey),
      );
    }
  }

  /// id（小写）-> 分类。插入顺序 = 内置在前 + `categories.json` 里的顺序。
  final Map<String, PluginCategory> _byId = {};

  /// 内置分类（顺序固定）
  List<PluginCategory> get builtins => PluginCategory.builtins;

  /// 自定义分类，顺序 = `categories.json` 里的顺序。
  List<PluginCategory> get custom =>
      _byId.values.where((c) => !c.isBuiltin).toList();

  /// 全部分类：内置在前（固定顺序），自定义在后
  List<PluginCategory> get all => [...builtins, ...custom];

  /// 按 id 查找（大小写不敏感），不产生副作用
  PluginCategory? byId(String? id) {
    final key = id?.trim().toLowerCase();
    if (key == null || key.isEmpty) return null;
    return _byId[key];
  }

  /// 解析分类 id，**必定返回一个分类**。
  ///
  /// 未注册的 id（例如插件写了个 `categoryId: podcast` 但用户没建过这个分类）
  /// 会就地登记成自定义分类，label 取 id 原文，因此不会退化成「其他」。
  PluginCategory resolve(String? id) {
    final raw = id?.trim() ?? '';
    if (raw.isEmpty) return PluginCategory.unknown;
    final key = raw.toLowerCase();
    final existing = _byId[key];
    if (existing != null) return existing;
    final implicit = PluginCategory.custom(id: key, label: raw);
    _byId[key] = implicit;
    return implicit;
  }
}
