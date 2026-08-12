import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import '../../domain/voice_call_transcript.dart';
import 'parent_home_palette.dart';

/// 「字」打开时：半透明气泡列表，展示本通全部对话；默认滚到最新。
class ParentCallTranscriptPanel extends StatefulWidget {
  const ParentCallTranscriptPanel({
    super.key,
    required this.palette,
    required this.entries,
  });

  final ParentHomePalette palette;
  final List<VoiceCallTranscriptEntry> entries;

  @override
  State<ParentCallTranscriptPanel> createState() =>
      _ParentCallTranscriptPanelState();
}

class _ParentCallTranscriptPanelState extends State<ParentCallTranscriptPanel> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  @override
  void didUpdateWidget(covariant ParentCallTranscriptPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.entries.length != oldWidget.entries.length ||
        (widget.entries.isNotEmpty &&
            oldWidget.entries.isNotEmpty &&
            widget.entries.last.text != oldWidget.entries.last.text)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(CocoSpace.s5),
          decoration: BoxDecoration(
            color: widget.palette.captionBubble,
            borderRadius: BorderRadius.circular(CocoRadius.xl),
          ),
          child: Text(
            '开始说话后，这里会记下你们说的话',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: widget.palette.textMuted,
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.only(bottom: CocoSpace.s4),
      itemCount: widget.entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: CocoSpace.s3),
      itemBuilder: (context, index) {
        final entry = widget.entries[index];
        return _TranscriptBubble(palette: widget.palette, entry: entry);
      },
    );
  }
}

class _TranscriptBubble extends StatelessWidget {
  const _TranscriptBubble({required this.palette, required this.entry});

  final ParentHomePalette palette;
  final VoiceCallTranscriptEntry entry;

  @override
  Widget build(BuildContext context) {
    final isUser = entry.isUser;
    final label = isUser ? '您' : '可可';
    // 用户句偏暖、可可句半透明白，叠在模糊场景上仍可读
    final background = isUser
        ? CocoColors.parentPrimarySoft.withValues(alpha: 0.92)
        : palette.captionBubble;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        // 单条气泡加高一点，老人端更好读、更好点
        constraints: const BoxConstraints(maxWidth: 320, minHeight: 96),
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            CocoSpace.s5,
            CocoSpace.s4,
            CocoSpace.s5,
            CocoSpace.s5,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(CocoRadius.lg),
            boxShadow: [
              BoxShadow(
                color: CocoColors.neutral950.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(height: CocoSpace.s3),
              Text(
                entry.text,
                style: TextStyle(
                  fontSize: 22,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: palette.captionText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
