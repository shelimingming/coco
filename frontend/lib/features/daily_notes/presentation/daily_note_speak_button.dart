import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/audio/mp3_bytes_source.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_loading.dart';
import '../../look/data/look_api.dart';
import '../domain/models.dart';
import 'daily_note_diary_body.dart';

/// 手账右上角：朗读小记正文（服务端 TTS）。
class DailyNoteSpeakButton extends ConsumerStatefulWidget {
  const DailyNoteSpeakButton({
    super.key,
    required this.note,
    required this.tone,
  });

  final DailyNote note;
  final DailyNoteDiaryTone tone;

  @override
  ConsumerState<DailyNoteSpeakButton> createState() =>
      _DailyNoteSpeakButtonState();
}

class _DailyNoteSpeakButtonState extends ConsumerState<DailyNoteSpeakButton> {
  final AudioPlayer _player = AudioPlayer();
  var _loading = false;
  var _playing = false;
  int _generation = 0;

  @override
  void dispose() {
    _generation++;
    _player.dispose();
    super.dispose();
  }

  String get _speechText {
    final parts = <String>[];
    final title = widget.note.title.trim();
    if (title.isNotEmpty) {
      parts.add(title);
    }
    if (widget.note.items.isNotEmpty) {
      parts.addAll(
        widget.note.items.map((e) => e.trim()).where((e) => e.isNotEmpty),
      );
    } else if (widget.note.bodyText.trim().isNotEmpty) {
      parts.add(widget.note.bodyText.trim());
    }
    final closing = widget.note.closing.trim();
    if (closing.isNotEmpty) {
      parts.add(closing);
    }
    return parts.join('。');
  }

  /// 与服务端 SpeechRequest / qwen3-tts-flash 上限对齐
  static const _maxSpeechChars = 600;

  Future<void> _toggle() async {
    if (_playing) {
      _generation++;
      await _player.stop();
      if (mounted) {
        setState(() {
          _playing = false;
          _loading = false;
        });
      }
      return;
    }

    var text = _speechText;
    if (text.length > _maxSpeechChars) {
      text = text.substring(0, _maxSpeechChars);
    }
    if (text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('这篇小记还没有可朗读的内容。')));
      return;
    }

    final generation = ++_generation;
    setState(() {
      _loading = true;
      _playing = false;
    });

    try {
      final bytes = await ref.read(audioApiProvider).speech(text);
      if (!mounted || generation != _generation) return;
      await _player.setAudioSource(Mp3BytesSource(bytes));
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _playing = true;
      });
      await _player.play();
      if (!mounted || generation != _generation) return;
      setState(() => _playing = false);
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _playing = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('朗读没成功，请稍后再试。小记内容没有丢。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isParent = widget.tone == DailyNoteDiaryTone.parent;
    final color = isParent ? CocoColors.parentPrimary : CocoColors.childPrimary;
    final soft = isParent
        ? CocoColors.parentPrimarySoft
        : CocoColors.childPrimarySoft;
    final label = _playing ? '停止朗读' : (_loading ? '准备朗读' : '朗读小记');
    final icon = _playing ? Icons.stop_rounded : Icons.volume_up_rounded;

    return Tooltip(
      message: label,
      child: Material(
        color: soft,
        borderRadius: BorderRadius.circular(CocoRadius.md),
        child: InkWell(
          onTap: _loading && !_playing ? null : _toggle,
          borderRadius: BorderRadius.circular(CocoRadius.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: CocoSpace.s3,
                vertical: CocoSpace.s2,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loading && !_playing)
                    CocoLoadingIndicator(size: 22, color: color)
                  else
                    Icon(icon, size: 26, color: color),
                  const SizedBox(width: 4),
                  Text(
                    _playing ? '停止' : '朗读',
                    style: TextStyle(
                      fontSize: isParent ? 16 : 14,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
