import 'dart:io';
import 'dart:ui' as ui;

import 'package:coco/core/theme/tokens.dart';
import 'package:coco/features/parent/domain/pending_voice_action.dart';
import 'package:coco/features/parent/domain/voice_call_transcript.dart';
import 'package:coco/features/parent/presentation/widgets/parent_call_transcript_panel.dart';
import 'package:coco/features/parent/presentation/widgets/parent_home_palette.dart';
import 'package:coco/features/parent/presentation/widgets/parent_pending_action_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// 给飞书「确认截图」用：把三处 P0 改动打成 PNG。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const shotDir = '/tmp/coco_p0_screenshots';

  testWidgets('通话中「更多」可点', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: CocoColors.parentBackground,
          body: Center(
            child: RepaintBoundary(
              key: const ValueKey('shot-more'),
              child: Padding(
                padding: const EdgeInsets.all(CocoSpace.s5),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '对话中',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          color: CocoColors.neutral950,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {},
                      style: TextButton.styleFrom(
                        foregroundColor: CocoColors.parentPrimary,
                        textStyle: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                        ),
                        minimumSize: const Size(56, 56),
                      ),
                      child: const Text('更多'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await _savePng(
      tester,
      find.byKey(const ValueKey('shot-more')),
      '$shotDir/more_enabled.png',
    );
    expect(find.text('更多'), findsOneWidget);
  });

  testWidgets('字幕不重复同一句「您」', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 520));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: CocoColors.parentBackground,
          body: RepaintBoundary(
            key: const ValueKey('shot-transcript'),
            child: Padding(
              padding: const EdgeInsets.all(CocoSpace.s4),
              child: SizedBox(
                height: 480,
                child: ParentCallTranscriptPanel(
                  palette: ParentHomePalette.standard,
                  entries: const [
                    VoiceCallTranscriptEntry(
                      role: VoiceCallTranscriptRole.user,
                      text: '今天天气真好',
                    ),
                    VoiceCallTranscriptEntry(
                      role: VoiceCallTranscriptRole.assistant,
                      text: '是呀，挺暖和的',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _savePng(
      tester,
      find.byKey(const ValueKey('shot-transcript')),
      '$shotDir/transcript_no_duplicate.png',
    );
    expect(find.text('今天天气真好'), findsOneWidget);
  });

  testWidgets('告诉家人按钮与口播一致', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: CocoColors.parentBackground,
          body: Padding(
            padding: const EdgeInsets.all(CocoSpace.s4),
            child: RepaintBoundary(
              key: const ValueKey('shot-share'),
              child: SizedBox(
                height: 640,
                child: ParentPendingActionCard(
                  action: const PendingVoiceAction(
                    draftId: 'draft-shot',
                    kind: PendingVoiceActionKind.shareToChild,
                    summary: '今天腿有些酸，还能正常走路。',
                    shareTo: '小林',
                  ),
                  onConfirm: () {},
                  onCancel: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _savePng(
      tester,
      find.byKey(const ValueKey('shot-share')),
      '$shotDir/share_button_tell_family.png',
    );
    expect(find.text('告诉家人'), findsWidgets);
  });
}

Future<void> _savePng(WidgetTester tester, Finder finder, String path) async {
  final boundary = tester.renderObject(finder) as RenderRepaintBoundary;
  // widget 测试默认假异步，toImage 必须走 runAsync
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 2));
  if (image == null) {
    fail('截图失败：$path');
  }
  final bytes = await tester.runAsync(
    () => image.toByteData(format: ui.ImageByteFormat.png),
  );
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}
