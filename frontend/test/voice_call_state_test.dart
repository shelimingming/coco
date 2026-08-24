import 'package:coco/features/parent/domain/voice_call_state.dart';
import 'package:coco/features/parent/domain/voice_call_transcript.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('已落定的用户句不会因残留 caption 再插一条', () {
    const state = VoiceCallState(
      phase: VoiceCallPhase.listening,
      userCaption: '今天天气真好',
      transcript: [
        VoiceCallTranscriptEntry(
          role: VoiceCallTranscriptRole.user,
          text: '今天天气真好',
        ),
        VoiceCallTranscriptEntry(
          role: VoiceCallTranscriptRole.assistant,
          text: '是呀，挺暖和的',
        ),
      ],
    );

    final texts = state.displayTranscript
        .where((e) => e.role == VoiceCallTranscriptRole.user)
        .map((e) => e.text)
        .toList();
    expect(texts, ['今天天气真好']);
  });

  test('倾听中的半句在 transcript 尚无该句时会显示', () {
    const state = VoiceCallState(
      phase: VoiceCallPhase.listening,
      userCaption: '我想喝水',
    );
    expect(state.displayTranscript.single.text, '我想喝水');
  });
}
