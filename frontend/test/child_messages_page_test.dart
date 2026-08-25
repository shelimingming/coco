import 'package:coco/core/theme/theme.dart';
import 'package:coco/features/messages/data/messages_api.dart';
import 'package:coco/features/messages/domain/models.dart';
import 'package:coco/features/messages/presentation/child_messages_page.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('自定义报平安内容在停止输入后自动展示转述预览', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeMessagesApi();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [messagesApiProvider.overrideWithValue(api)],
        child: MaterialApp(
          theme: CocoTheme.child(),
          home: const ChildMessagesPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '我正在拉粑粑，不用担心');
    await tester.pump(const Duration(milliseconds: 599));
    expect(api.previewRequests, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();

    expect(api.previewRequests, ['我正在拉粑粑，不用担心']);
    expect(find.text('可可想告诉您，孩子一切都好。'), findsOneWidget);
  });
}

class _FakeMessagesApi extends MessagesApi {
  _FakeMessagesApi() : super(Dio());

  final List<String> previewRequests = [];

  @override
  Future<List<FamilyMessage>> list() async => [];

  @override
  Future<MessagePreview> preview(String text) async {
    previewRequests.add(text);
    return MessagePreview(
      originalText: text,
      deliveredText: '可可想告诉您，孩子一切都好。',
      translated: true,
    );
  }
}
