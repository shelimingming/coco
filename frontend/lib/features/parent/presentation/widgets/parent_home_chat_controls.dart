import 'package:flutter/material.dart';

import '../../../../core/theme/tokens.dart';
import 'parent_home_palette.dart';

/// 首页对话控制：未开始大钮；聊天中/已暂停为暂停·继续 + 结束双圆钮。
class ParentHomeChatControls extends StatelessWidget {
  const ParentHomeChatControls({
    super.key,
    required this.palette,
    required this.inSession,
    required this.paused,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onEnd,
  });

  final ParentHomePalette palette;
  final bool inSession;
  final bool paused;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onEnd;

  /// 设计基准：开始钮与工具条间距 15pt
  static const double gapAboveToolbar = 15;

  @override
  Widget build(BuildContext context) {
    if (!inSession) {
      return _StartChatButton(palette: palette, onPressed: onStart);
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RoundChatAction(
          palette: palette,
          filled: true,
          iconAsset: paused
              ? 'assets/icons/parent/icon-chat-resume.png'
              : 'assets/icons/parent/icon-chat-pause.png',
          label: paused ? '继续聊天' : '暂停一下',
          semanticsLabel: paused ? '继续聊天' : '暂停聊天',
          onPressed: paused ? onResume : onPause,
        ),
        const SizedBox(width: 56),
        _RoundChatAction(
          palette: palette,
          filled: false,
          iconAsset: 'assets/icons/parent/icon-chat-end.png',
          label: '结束聊天',
          semanticsLabel: '结束聊天',
          onPressed: onEnd,
        ),
      ],
    );
  }
}

class _StartChatButton extends StatelessWidget {
  const _StartChatButton({required this.palette, required this.onPressed});

  final ParentHomePalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '开始聊天',
      child: SizedBox(
        width: double.infinity,
        height: 71,
        child: Material(
          color: palette.chatOrange,
          borderRadius: BorderRadius.circular(26),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(26),
            child: const Center(
              child: Text(
                '开始聊天',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  color: CocoColors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundChatAction extends StatelessWidget {
  const _RoundChatAction({
    required this.palette,
    required this.filled,
    required this.iconAsset,
    required this.label,
    required this.semanticsLabel,
    required this.onPressed,
  });

  final ParentHomePalette palette;
  final bool filled;
  final String iconAsset;
  final String label;
  final String semanticsLabel;
  final VoidCallback onPressed;

  static const double _diameter = 68;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Material(
            color: filled ? palette.chatOrange : CocoColors.white,
            shape: CircleBorder(
              side: filled
                  ? BorderSide.none
                  : BorderSide(color: palette.iconOrange, width: 2),
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: SizedBox(
                width: _diameter,
                height: _diameter,
                child: Center(
                  child: Image.asset(
                    iconAsset,
                    width: 28,
                    height: 28,
                    // 暂停/继续为白形；结束叉已是橙，不再染色以免糊成实块
                    color: filled ? CocoColors.white : null,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: CocoSpace.s2),
          Text(
            label,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.2,
              color: palette.text,
            ),
          ),
        ],
      ),
    );
  }
}
