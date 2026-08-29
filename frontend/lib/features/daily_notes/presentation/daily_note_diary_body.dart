import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../domain/models.dart';
import 'daily_note_image.dart';

/// 日记式排版：交付稿撕边贴图纸（纸张 / 枝叶 / 爱心素材）。
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
    this.diaryTitle,
    @Deprecated('手账抬头自带日期') this.showDateHeader = false,
    @Deprecated('手账抬头自带日期') this.showCardDate = true,
  });

  final DailyNote note;
  final DailyNoteDiaryTone tone;
  final String? diaryTitle;
  final bool showDateHeader;
  final bool showCardDate;

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
    final lines = note.items.isNotEmpty
        ? note.items
        : (note.bodyText.trim().isEmpty
              ? const <String>[]
              : note.bodyText
                    .split('\n')
                    .where((e) => e.trim().isNotEmpty)
                    .toList());
    final bySeq = {for (final img in note.images) img.seq: img};
    final pairedSeq = <int>{
      for (var i = 0; i < lines.length; i++)
        if (bySeq.containsKey(i)) i,
    };
    final title = (diaryTitle?.trim().isNotEmpty == true)
        ? diaryTitle!.trim()
        : '今日小记';
    final date = note.noteDate;
    final weekday = _weekdayLabel(date.weekday);
    final bodySize = isParent ? 22.0 : 19.0;

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
            // 撕边纸底：九宫格拉伸，边缘不变形
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
                    // 给左上枝叶留空
                    const SizedBox(height: 28),
                    _DateRow(
                      month: date.month,
                      day: date.day,
                      year: date.year,
                      weekday: weekday,
                      ink: ink,
                      inkStrong: inkStrong,
                    ),
                    const SizedBox(height: CocoSpace.s4),
                    _TitleRow(title: title, inkStrong: inkStrong),
                    const SizedBox(height: CocoSpace.s6),
                    if (lines.isEmpty)
                      Text(
                        '（今天还没有写下内容）',
                        style: TextStyle(
                          fontSize: bodySize,
                          height: 1.6,
                          color: CocoColors.neutral500,
                        ),
                      )
                    else
                      for (var i = 0; i < lines.length; i++) ...[
                        if (i > 0) const SizedBox(height: CocoSpace.s5),
                        _ScrapbookEntry(
                          index: i + 1,
                          text: lines[i],
                          fontSize: bodySize,
                          ink: inkStrong,
                          badgeColor: i.isEven
                              ? Color.alphaBlend(
                                  CocoColors.warning.withValues(alpha: 0.22),
                                  CocoColors.white,
                                )
                              : CocoColors.neutral300,
                          image: bySeq[i],
                        ),
                      ],
                    for (final img in note.images)
                      if (!pairedSeq.contains(img.seq)) ...[
                        const SizedBox(height: CocoSpace.s4),
                        _RoundedPhoto(url: img.url),
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
            // 胶带枝叶压在纸角上
            const Positioned(
              left: 10,
              top: 6,
              child: _TapedLeaf(),
            ),
          ],
        ),
      ),
    );
  }

  static String _weekdayLabel(int weekday) {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    return '星期${labels[(weekday - 1).clamp(0, 6)]}';
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.month,
    required this.day,
    required this.year,
    required this.weekday,
    required this.ink,
    required this.inkStrong,
  });

  final int month;
  final int day;
  final int year;
  final String weekday;
  final Color ink;
  final Color inkStrong;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 左边给枝叶让位
        const SizedBox(width: 52),
        Text(
          '$month / $day',
          style: TextStyle(
            fontFamily: DailyNoteHandwriting.family,
            fontSize: 40,
            height: 1,
            color: inkStrong,
          ),
        ),
        const SizedBox(width: CocoSpace.s3),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$year',
                style: TextStyle(
                  fontFamily: DailyNoteHandwriting.family,
                  fontSize: 14,
                  height: 1.15,
                  color: ink,
                ),
              ),
              Text(
                weekday,
                style: TextStyle(
                  fontFamily: DailyNoteHandwriting.family,
                  fontSize: 14,
                  height: 1.15,
                  color: ink,
                ),
              ),
            ],
          ),
        ),
      ],
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

class _ScrapbookEntry extends StatelessWidget {
  const _ScrapbookEntry({
    required this.index,
    required this.text,
    required this.fontSize,
    required this.ink,
    required this.badgeColor,
    this.image,
  });

  final int index;
  final String text;
  final double fontSize;
  final Color ink;
  final Color badgeColor;
  final DailyNoteImageMeta? image;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$index',
                style: TextStyle(
                  fontFamily: DailyNoteHandwriting.family,
                  fontSize: 16,
                  height: 1,
                  color: ink,
                ),
              ),
            ),
            const SizedBox(width: CocoSpace.s3),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontFamily: DailyNoteHandwriting.family,
                  fontSize: fontSize,
                  height: 1.4,
                  color: ink,
                ),
              ),
            ),
          ],
        ),
        if (image != null) ...[
          const SizedBox(height: CocoSpace.s3),
          _RoundedPhoto(url: image!.url),
        ],
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
