import 'package:flutter_test/flutter_test.dart';
import 'package:wyw/js/js_extends/js_bridge.dart';
import 'package:wyw/js/js_extends/js_dialog.dart';

/// `Dialog.*` 桥接层的行为测试。
///
/// 覆盖 venera 移植插件的关键依赖：`showInputDialog` / `showSelectDialog` /
/// `showLoading` / `cancelLoading` 的参数转发，以及**宿主未注册回调时返回 null**
/// （插件侧据此优雅降级，而不是崩溃）。
void main() {
  final dialog = JsDialog();

  tearDown(() {
    JSEngineCommonApi.onShowToast = null;
    JSEngineCommonApi.onShowDialog = null;
    JSEngineCommonApi.onShowInputDialog = null;
    JSEngineCommonApi.onShowSelectDialog = null;
    JSEngineCommonApi.onShowLoading = null;
    JSEngineCommonApi.onCancelLoading = null;
  });

  group('showToast', () {
    test('转发 message 到宿主回调', () {
      String? got;
      JSEngineCommonApi.onShowToast = (m) => got = m;
      dialog.handleDialogCallback({
        'function': 'showToast',
        'message': '你好',
      });
      expect(got, '你好');
    });

    test('未注册回调时不抛错（no-op）', () {
      expect(
        () => dialog.handleDialogCallback({
          'function': 'showToast',
          'message': 'x',
        }),
        returnsNormally,
      );
    });
  });

  group('showInputDialog', () {
    test('未注册回调时返回 null（插件应据此降级）', () {
      expect(
        dialog.handleDialogCallback({
          'function': 'showInputDialog',
          'title': '验证码',
        }),
        isNull,
      );
    });

    test('注册回调后转发 title/image/validator，并透传返回值', () async {
      String? gotTitle;
      Object? gotImage;
      Object? gotValidator;
      JSEngineCommonApi.onShowInputDialog = ({
        required String title,
        Object? image,
        Object? validator,
      }) async {
        gotTitle = title;
        gotImage = image;
        gotValidator = validator;
        return '1234';
      };

      final imageBytes = [1, 2, 3];
      final result = dialog.handleDialogCallback({
        'function': 'showInputDialog',
        'title': '验证码',
        'image': imageBytes,
        'validator': 'fn',
      }) as Future<String?>?;

      // 返回 Future（flutter_qjs 会转成 JS Promise，故 JS 侧可 await）
      expect(result, isA<Future<String?>>());
      expect(await result, '1234');
      expect(gotTitle, '验证码');
      expect(gotImage, imageBytes);
      expect(gotValidator, 'fn');
    });

    test('用户取消（回调返回 null）时返回 null', () async {
      JSEngineCommonApi.onShowInputDialog = ({
        required String title,
        Object? image,
        Object? validator,
      }) async =>
          null;
      final r = await (dialog.handleDialogCallback({
        'function': 'showInputDialog',
        'title': 't',
      }) as Future<String?>?);
      expect(r, isNull);
    });
  });

  group('showSelectDialog', () {
    test('未注册回调时返回 null', () {
      expect(
        dialog.handleDialogCallback({
          'function': 'showSelectDialog',
          'title': 't',
          'options': ['a', 'b'],
        }),
        isNull,
      );
    });

    test('选项被规范化为 String 列表，并透传选中下标', () async {
      List<String>? gotOptions;
      int? gotIndex;
      JSEngineCommonApi.onShowSelectDialog = ({
        required String title,
        required List<String> options,
        int? initialIndex,
      }) async {
        gotOptions = options;
        gotIndex = initialIndex;
        return 1;
      };

      final r = await (dialog.handleDialogCallback({
        'function': 'showSelectDialog',
        'title': '选择',
        'options': ['a', 2, null],
        'initialIndex': 0,
      }) as Future<int?>?);

      expect(r, 1);
      expect(gotOptions, ['a', '2', '']);
      expect(gotIndex, 0);
    });
  });

  group('showLoading / cancelLoading', () {
    test('showLoading 返回宿主给的 id；未注册时返回 -1', () {
      expect(
        dialog.handleDialogCallback({'function': 'showLoading'}),
        -1,
      );

      JSEngineCommonApi.onShowLoading = ({Object? onCancel}) => 7;
      expect(dialog.handleDialogCallback({'function': 'showLoading'}), 7);
    });

    test('cancelLoading 转发 id', () {
      int? got;
      JSEngineCommonApi.onCancelLoading = (id) => got = id;
      dialog.handleDialogCallback({'function': 'cancelLoading', 'id': 7});
      expect(got, 7);
    });
  });

  group('showDialog', () {
    test('actions 被规范化为 Map 列表并转发', () {
      String? gotTitle;
      String? gotContent;
      List<Map<String, dynamic>>? gotActions;
      JSEngineCommonApi.onShowDialog = ({
        required String title,
        required String content,
        List<Map<String, dynamic>> actions = const [],
      }) {
        gotTitle = title;
        gotContent = content;
        gotActions = actions;
      };

      dialog.handleDialogCallback({
        'function': 'showDialog',
        'title': '提示',
        'content': '该章节需付费后阅读',
        'actions': [
          {'text': '取消', 'callback': 'fn1'},
          {'text': '去购买', 'callback': 'fn2'},
          'not-a-map', // 非法项应被跳过
        ],
      });

      expect(gotTitle, '提示');
      expect(gotContent, '该章节需付费后阅读');
      expect(gotActions, hasLength(2));
      expect(gotActions![0]['text'], '取消');
      expect(gotActions![1]['callback'], 'fn2');
    });

    test('未注册回调时不抛错', () {
      expect(
        () => dialog.handleDialogCallback({
          'function': 'showDialog',
          'title': 't',
          'content': 'c',
        }),
        returnsNormally,
      );
    });
  });

  test('未知 function 返回 null 且不抛错', () {
    expect(
      dialog.handleDialogCallback({'function': 'somethingElse'}),
      isNull,
    );
  });
}
