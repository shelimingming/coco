import 'package:coco/features/parent/domain/voice_call_state.dart';
import 'package:coco/features/parent/domain/voice_call_transcript.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paused 时 isInSession 为真且 isActive 为假', () {
    const state = VoiceCallState(phase: VoiceCallPhase.paused);
    expect(state.isPaused, isTrue);
    expect(state.isInSession, isTrue);
    expect(state.isActive, isFalse);
    expect(state.statusLabel, '聊天已暂停');
  });

  test('播报中提示点小狗可打断', () {
    const state = VoiceCallState(phase: VoiceCallPhase.speaking);
    expect(state.canInterrupt, isTrue);
    expect(state.statusLabel, '点我可以打断我～');
  });

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

  test('看图字幕只取最近一轮用户话和可可回复', () {
    const state = VoiceCallState(
      phase: VoiceCallPhase.speaking,
      assistantCaption: '这是向日葵',
      transcript: [
        VoiceCallTranscriptEntry(
          role: VoiceCallTranscriptRole.user,
          text: '你好',
        ),
        VoiceCallTranscriptEntry(
          role: VoiceCallTranscriptRole.assistant,
          text: '您好呀',
        ),
        VoiceCallTranscriptEntry(
          role: VoiceCallTranscriptRole.user,
          text: '这是什么花',
        ),
      ],
    );
    expect(state.currentRoundEntries.map((e) => e.text).toList(), [
      '这是什么花',
      '这是向日葵',
    ]);
  });
}
