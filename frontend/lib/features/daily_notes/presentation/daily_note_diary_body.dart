import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../domain/models.dart';
import 'daily_note_image.dart';

/// 日记式排版：交付稿撕边贴图纸手账。
enum DailyNoteDiaryTone { parent, child }

/// 小记手账字体（龙藏体，见 assets/fonts）。
abstract final class DailyNoteHandwriting {
  static const family = 'CocoHandwriting';
}

abstract final class _DiaryAssets {
  static const paper = 'assets/images/daily_notes/paper_blank.png';
  static const leaf = 'assets/images/daily_notes/leaf.png';
  static const heart = 'assets/images/daily_notes/heart.png';
  // 纸张 365×710：四周撕边保留，中间可拉伸以适配不同条目数
  static const paperCenterSlice = Rect.fromLTRB(48, 56, 317, 654);
}

class DailyNoteDiaryBody extends StatelessWidget {
  const DailyNoteDiaryBody({
    super.key,
    required this.note,
    required this.tone,
    this.fallbackTitle,
    this.onTalkToCoco,
    @Deprecated('手账抬头自带日期') this.showDateHeader = false,
    @Deprecated('手账抬头自带日期') this.showCardDate = true,
    @Deprecated('改用 fallbackTitle / note.title') this.diaryTitle,
  });

  final DailyNote note;
  final DailyNoteDiaryTone tone;

  /// 无 note.title 时的兜底标题（如子女端「××的今日小记」）。
  final String? fallbackTitle;

  /// 父母端 empty：去和可可聊聊。
  final VoidCallback? onTalkToCoco;
  final bool showDateHeader;
  final bool showCardDate;
  final String? diaryTitle;

  @override
  Widget build(BuildContext context) {
    final isParent = tone == DailyNoteDiaryTone.parent;
    final ink = CocoColors.neutral700;
    final inkStrong = CocoColors.neutral950;
    final matte = isParent
        ? Color.alphaBlend(
            CocoColors.parentSecondary.withValues(alpha: 0.22),
            CocoColors.parentBackground,
          )
        : Color.alphaBlend(
            CocoColors.neutral500.withValues(alpha: 0.18),
            CocoColors.childBackground,
          );
    final bodySize = isParent ? 22.0 : 19.0;

    // 素材不足：引导再聊，不冒充日记正文
    if (note.isEmpty) {
      return _EmptyDiaryGuide(
        matte: matte,
        ink: ink,
        inkStrong: inkStrong,
        bodySize: bodySize,
        message: note.bodyText.trim().isNotEmpty
            ? note.bodyText.trim()
            : '今天聊得还不多，再和可可说说今天发生了什么，我再帮您写日记。',
        onTalkToCoco: isParent ? onTalkToCoco : null,
      );
    }

    final paragraphs = note.items.isNotEmpty
        ? note.items
        : (note.bodyText.trim().isEmpty
              ? const <String>[]
              : note.bodyText
                    .split('\n')
                    .where((e) => e.trim().isNotEmpty)
                    .toList());
    final title = note.title.trim().isNotEmpty
        ? note.title.trim()
        : (diaryTitle?.trim().isNotEmpty == true
              ? diaryTitle!.trim()
              : (fallbackTitle?.trim().isNotEmpty == true
                    ? fallbackTitle!.trim()
                    : '今日小记'));
    final header = note.headerLine.trim().isNotEmpty
        ? note.headerLine.trim()
        : _localHeader(note.noteDate);
    final closing = note.closing.trim();
    // seq 与段落下标对齐，便于段落后插图
    final bySeq = {for (final img in note.images) img.seq: img};
    final pairedSeq = <int>{
      for (var i = 0; i < paragraphs.length; i++)
        if (bySeq.containsKey(i)) i,
    };

    return ColoredBox(
      color: matte,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          CocoSpace.s2,
          CocoSpace.s2,
          CocoSpace.s2,
          CocoSpace.s4,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Image.asset(
                _DiaryAssets.paper,
                fit: BoxFit.fill,
                centerSlice: _DiaryAssets.paperCenterSlice,
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 36, 28, 36),
              child: DefaultTextStyle.merge(
                style: const TextStyle(
                  fontFamily: DailyNoteHandwriting.family,
                  fontWeight: FontWeight.w400,
                  color: CocoColors.neutral700,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 给左上枝叶留空，避免挡住日期首字
                    const SizedBox(height: 28),
                    Padding(
                      padding: const EdgeInsets.only(left: 52),
                      child: Text(
                        header,
                        style: TextStyle(
                          fontFamily: DailyNoteHandwriting.family,
                          fontSize: isParent ? 18 : 16,
                          height: 1.3,
                          color: ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: CocoSpace.s4),
                    _TitleRow(title: title, inkStrong: inkStrong),
                    const SizedBox(height: CocoSpace.s6),
                    if (paragraphs.isEmpty)
                      Text(
                        '（今天还没有写下内容）',
                        style: TextStyle(
                          fontSize: bodySize,
                          height: 1.6,
                          color: CocoColors.neutral500,
                        ),
                      )
                    else
                      for (var i = 0; i < paragraphs.length; i++) ...[
                        if (i > 0) const SizedBox(height: CocoSpace.s5),
                        Text(
                          paragraphs[i],
                          style: TextStyle(
                            fontFamily: DailyNoteHandwriting.family,
                            fontSize: bodySize,
                            height: 1.55,
                            color: inkStrong,
                          ),
                        ),
                        // 图文一一对应：该段有配图则紧跟段落后
                        if (bySeq[i] != null) ...[
                          const SizedBox(height: CocoSpace.s3),
                          _RoundedPhoto(url: bySeq[i]!.url),
                        ],
                      ],
                    // 未配对的多余图（异常兜底）放在正文后、收束前
                    for (final img in note.images)
                      if (!pairedSeq.contains(img.seq)) ...[
                        const SizedBox(height: CocoSpace.s3),
                        _RoundedPhoto(url: img.url),
                      ],
                    if (closing.isNotEmpty) ...[
                      const SizedBox(height: CocoSpace.s5),
                      Text(
                        closing,
                        style: TextStyle(
                          fontFamily: DailyNoteHandwriting.family,
                          fontSize: bodySize,
                          height: 1.5,
                          color: inkStrong,
                        ),
                      ),
                    ],
                    const SizedBox(height: CocoSpace.s6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            '可可根据今天的交流整理',
                            style: TextStyle(
                              fontSize: isParent ? 15 : 13,
                              height: 1.4,
                              color: ink.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                        _InkHeart(size: 18, color: inkStrong),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Positioned(left: 10, top: 6, child: _TapedLeaf()),
          ],
        ),
      ),
    );
  }

  static String _localHeader(DateTime date) {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    final weekday = '星期${labels[(date.weekday - 1).clamp(0, 6)]}';
    return '${date.month}月${date.day}日 $weekday';
  }
}

/// 素材不足时的引导卡（不走假日记排版）。
class _EmptyDiaryGuide extends StatelessWidget {
  const _EmptyDiaryGuide({
    required this.matte,
    required this.ink,
    required this.inkStrong,
    required this.bodySize,
    required this.message,
    this.onTalkToCoco,
  });

  final Color matte;
  final Color ink;
  final Color inkStrong;
  final double bodySize;
  final String message;
  final VoidCallback? onTalkToCoco;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: matte,
      child: Padding(
        padding: const EdgeInsets.all(CocoSpace.s4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              message,
              style: TextStyle(
                fontFamily: DailyNoteHandwriting.family,
                fontSize: bodySize,
                height: 1.55,
                color: inkStrong,
              ),
            ),
            const SizedBox(height: CocoSpace.s3),
            Text(
              '聊几件今天发生的小事，再点「立即生成」就好。',
              style: TextStyle(fontSize: 16, height: 1.4, color: ink),
            ),
            if (onTalkToCoco != null) ...[
              const SizedBox(height: CocoSpace.s5),
              CocoPrimaryButton(label: '去和可可聊聊', onPressed: onTalkToCoco),
            ],
          ],
        ),
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.title, required this.inkStrong});

  final String title;
  final Color inkStrong;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: DailyNoteHandwriting.family,
              fontSize: 28,
              height: 1.3,
              color: inkStrong,
            ),
          ),
        ),
        _InkHeart(size: 22, color: inkStrong),
      ],
    );
  }
}

class _RoundedPhoto extends StatelessWidget {
  const _RoundedPhoto({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(CocoRadius.lg),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: DailyNoteImage(url: url),
      ),
    );
  }
}

/// 奶油色爱心描边染成墨色，贴在米纸上才看得清。
class _InkHeart extends StatelessWidget {
  const _InkHeart({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      child: Image.asset(
        _DiaryAssets.heart,
        width: size,
        height: size,
        filterQuality: FilterQuality.medium,
        excludeFromSemantics: true,
      ),
    );
  }
}

/// 交付稿枝叶 + 半透明胶带。
class _TapedLeaf extends StatelessWidget {
  const _TapedLeaf();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      height: 100,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          Transform.rotate(
            angle: -0.18,
            child: Image.asset(
              _DiaryAssets.leaf,
              width: 52,
              height: 104,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              excludeFromSemantics: true,
            ),
          ),
          Positioned(
            top: 28,
            child: Transform.rotate(
              angle: 0.2,
              child: Container(
                width: 48,
                height: 16,
                decoration: BoxDecoration(
                  color: CocoColors.neutral300.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: [
                    BoxShadow(
                      color: CocoColors.neutral950.withValues(alpha: 0.06),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
