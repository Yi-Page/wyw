import 'package:wyw/plugins/plugin.dart';

/// 插件管理操作的结果（无返回值的那类）。每次调用自带结果，谁调用谁负责展示。
class PluginOpResult {
  const PluginOpResult.success() : error = null;

  const PluginOpResult.failure(this.error);

  /// 失败原因（成功时为 null）
  final String? error;

  bool get isSuccess => error == null;

  bool get isFailure => !isSuccess;

  @override
  String toString() =>
      isSuccess ? 'PluginOpResult.success()' : 'PluginOpResult.failure($error)';
}

/// 创建 / 导入单个插件的结果（调用方需要拿到创建出来的 [Plugin]）。
class PluginCreateResult {
  const PluginCreateResult.success(Plugin created)
      : plugin = created,
        error = null;

  const PluginCreateResult.failure(this.error) : plugin = null;

  final Plugin? plugin;

  final String? error;

  bool get isSuccess => error == null;

  bool get isFailure => !isSuccess;

  @override
  String toString() => isSuccess
      ? 'PluginCreateResult.success(${plugin?.name})'
      : 'PluginCreateResult.failure($error)';
}

/// 批量导入结果：成功的名字 + 失败项及原因。
///
/// 批量导入是「尽力而为」：单个文件失败不影响其余，所以失败原因必须逐条带回。
class PluginImportReport {
  const PluginImportReport({
    this.imported = const [],
    this.failed = const {},
  });

  /// 成功导入并已注册的插件名
  final List<String> imported;

  /// 失败项：来源标识（文件名 / 插件名）-> 原因
  final Map<String, String> failed;

  bool get isEmpty => imported.isEmpty && failed.isEmpty;

  bool get hasFailure => failed.isNotEmpty;

  /// 给用户看的一行摘要
  String get summary {
    final parts = <String>[];
    if (imported.isNotEmpty) parts.add('成功 ${imported.length} 个');
    if (failed.isNotEmpty) parts.add('失败 ${failed.length} 个');
    return parts.isEmpty ? '没有可导入的插件' : parts.join('，');
  }

  @override
  String toString() => 'PluginImportReport($summary)';
}
