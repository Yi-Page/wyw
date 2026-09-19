import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wyw/bean/dialog/dialog_helper.dart';

/// 弹出「跳过秒数」输入对话框（仅允许数字），确认后调用 [onSave]。
///
/// 统一替代各播放器面板里手写的 AlertDialog + TextField 样板。
Future<void> showSkipSecondsDialog({
  required int currentSkipTime,
  required ValueChanged<int> onSave,
}) {
  return WywDialog.show(builder: (context) {
    String input = '';
    return AlertDialog(
      title: const Text('跳过秒数'),
      content: StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return TextField(
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly, // 只允许输入数字
            ],
            decoration: InputDecoration(
              floatingLabelBehavior:
                  FloatingLabelBehavior.never, // 控制label的显示方式
              labelText: currentSkipTime.toString(),
            ),
            onChanged: (value) {
              input = value;
            },
          );
        },
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => WywDialog.dismiss(),
          child: Text(
            '取消',
            style: TextStyle(color: Theme.of(context).colorScheme.outline),
          ),
        ),
        TextButton(
          onPressed: () async {
            if (input != '') {
              onSave(int.parse(input));
            }
            WywDialog.dismiss();
          },
          child: const Text('确定'),
        ),
      ],
    );
  });
}
