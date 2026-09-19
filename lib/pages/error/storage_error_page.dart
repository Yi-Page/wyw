import 'dart:io';
import 'package:flutter/material.dart';
import 'package:wyw/bean/widget/error_widget.dart';
import 'package:wyw/bean/widget/loading_indicator.dart';
import 'package:wyw/bean/widget/state_presentation.dart';
import 'package:path_provider/path_provider.dart';

class StorageErrorPage extends StatelessWidget {
  const StorageErrorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 故意使用裸 AppBar（全项目唯一豁免）：本页是存储初始化失败的降级页，
      // 而 SysAppBar / EmbeddedNativeControlArea 依赖 GStorage，此时可能不可用。
      appBar: AppBar(
        title: const Text('内部错误'),
      ),
      body: Center(
        child: FutureBuilder<Directory>(
          future: getApplicationSupportDirectory(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done) {
              final supportDir = snapshot.data;
              final path = supportDir != null ? '$supportDir' : '未知路径';
              return GeneralErrorWidget(
                errMsg: '存储初始化错误 \n 当前储存位置 $path \n 尝试删除该目录以重置本地存储',
                // 退出不是重试：走 actions，避免继承重试按钮的刷新图标。
                actions: [
                  StateActionButton.tonal(
                    onPressed: () {
                      exit(0);
                    },
                    text: '退出程序',
                  ),
                ],
              );
            } else {
              return const Center(child: LoadingIndicator());
            }
          },
        ),
      ),
    );
  }
}
