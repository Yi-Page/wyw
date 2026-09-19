import 'dart:io';

import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:wyw/services/logging/log_tags.dart';
import 'package:wyw/services/logging/logger.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class ShaderAssetService {
  late Directory shadersDirectory;

  Future<void> copyShadersToExternalDirectory() async {
    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final assets = assetManifest.listAssets();
    final directory = await getApplicationSupportDirectory();
    shadersDirectory = Directory(path.join(directory.path, 'anime_shaders'));

    if (!await shadersDirectory.exists()) {
      await shadersDirectory.create(recursive: true);
      WywLogger().i('${LogTag.shader} 创建着色器目录 ${shadersDirectory.path}');
    }

    final shaderFiles = assets.where((String asset) =>
        asset.startsWith('assets/shaders/') && asset.endsWith('.glsl'));

    int copiedFilesCount = 0;

    for (var filePath in shaderFiles) {
      final fileName = filePath.split('/').last;
      final targetFile = File(path.join(shadersDirectory.path, fileName));
      if (await targetFile.exists()) {
        WywLogger().i('${LogTag.shader} 着色器已存在，跳过 ${targetFile.path}');
        continue;
      }

      try {
        final data = await rootBundle.load(filePath);
        final List<int> bytes = data.buffer.asUint8List();
        await targetFile.writeAsBytes(bytes);
        copiedFilesCount++;
        WywLogger().i('${LogTag.shader} 复制着色器 ${targetFile.path}');
      } catch (e, s) {
        WywLogger().e('${LogTag.shader} 复制着色器失败 filePath=$filePath',
            error: e, stackTrace: s);
      }
    }

    WywLogger().i(
        '${LogTag.shader} 共复制$copiedFilesCount个着色器文件到 ${shadersDirectory.path}');
  }
}
