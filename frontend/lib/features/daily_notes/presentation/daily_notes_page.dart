import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_loading.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../application/daily_notes_providers.dart';
import '../data/daily_notes_api.dart';
import '../domain/models.dart';
import 'daily_note_image.dart';

/// 父母端每日小记：设置 + 立即生成 + 历史列表。
class DailyNotesPage extends ConsumerStatefulWidget {
  const DailyNotesPage({super.key});

  @override
  ConsumerState<DailyNotesPage> createState() => _DailyNotesPageState();
}

class _DailyNotesPageState extends ConsumerState<DailyNotesPage> {
  bool _generating = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(dailyNoteSettingsProvider);
    final listAsync = ref.watch(dailyNotesListProvider);

    return CocoScaffold(
      title: '每日小记',
      leading: ParentBackButton(onPressed: () => context.pop()),
      leadingWidth: 104,
      bottom: ParentHomeButton(onPressed: () => context.go('/parent')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(dailyNoteSettingsProvider);
          ref.invalidate(dailyNotesListProvider);
        },
        child: ListView(
          children: [
            settingsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: CocoSpace.s4),
                child: CocoPageLoading(),
              ),
              error: (error, _) => Text(
                error is ApiException
                    ? error.message
                    : '设置加载失败。您可以下拉重试，数据没有丢失。',
                style: theme.textTheme.bodyLarge,
              ),
              data: (settings) => _SettingsCard(
                settings: settings,
                generating: _generating,
                onGenerate: _onGenerate,
                onToggleGenerate: (v) => _patch(generateEnabled: v),
                onToggleShare: (v) => _patch(shareToChildEnabled: v),
                onGender: (g) => _patch(gender: g),
              ),
            ),
            const SizedBox(height: CocoSpace.s6),
            Text('往日小记', style: theme.textTheme.titleLarge),
            const SizedBox(height: CocoSpace.s3),
            listAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: CocoSpace.s6),
                child: CocoPageLoading(),
              ),
              error: (error, _) => Text(
                error is ApiException
                    ? error.message
                    : '列表加载失败。您可以下拉重试，数据没有丢失。',
                style: theme.textTheme.bodyLarge,
              ),
              data: (items) {
                final ready = items.where((e) => e.isReady).toList();
                if (ready.isEmpty) {
                  return Text(
                    '还没有生成过小记。晚上 20:00 会自动整理，也可以点「立即生成」。',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: CocoColors.neutral700,
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final note in ready) ...[
                      _NoteListTile(
                        note: note,
                        onTap: () =>
                            context.push('/parent/daily-notes/${note.id}'),
                      ),
                      const SizedBox(height: CocoSpace.s3),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _patch({
    bool? generateEnabled,
    bool? shareToChildEnabled,
    String? gender,
  }) async {
    try {
      await ref.read(dailyNotesApiProvider).updateSettings(
            generateEnabled: generateEnabled,
            shareToChildEnabled: shareToChildEnabled,
            gender: gender,
          );
      ref.invalidate(dailyNoteSettingsProvider);
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  Future<void> _onGenerate() async {
    if (_generating) return;
    setState(() => _generating = true);
    try {
      final note = await ref.read(dailyNotesApiProvider).generate();
      ref.invalidate(dailyNotesListProvider);
      if (!mounted) return;
      if (note.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('今天聊到的日常还不够，暂时没有生成小记。')),
        );
      } else if (note.isReady) {
        context.push('/parent/daily-notes/${note.id}');
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.settings,
    required this.generating,
    required this.onGenerate,
    required this.onToggleGenerate,
    required this.onToggleShare,
    required this.onGender,
  });

  final DailyNoteSettings settings;
  final bool generating;
  final VoidCallback onGenerate;
  final ValueChanged<bool> onToggleGenerate;
  final ValueChanged<bool> onToggleShare;
  final ValueChanged<String> onGender;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(CocoSpace.s4),
      decoration: BoxDecoration(
        color: CocoColors.white,
        borderRadius: BorderRadius.circular(CocoRadius.lg),
        border: Border.all(color: CocoColors.parentPrimarySoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('设置', style: theme.textTheme.titleMedium),
          const SizedBox(height: CocoSpace.s2),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('每天自动生成', style: theme.textTheme.bodyLarge),
            subtitle: Text(
              '默认晚上 ${settings.generateHour}:00 整理当天聊天',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: CocoColors.neutral700,
              ),
            ),
            value: settings.generateEnabled,
            activeThumbColor: CocoColors.parentPrimary,
            onChanged: onToggleGenerate,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('生成后发给子女', style: theme.textTheme.bodyLarge),
            subtitle: Text(
              '关闭时只保存在您这边，默认不发送',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: CocoColors.neutral700,
              ),
            ),
            value: settings.shareToChildEnabled,
            activeThumbColor: CocoColors.parentPrimary,
            onChanged: onToggleShare,
          ),
          const SizedBox(height: CocoSpace.s2),
          Text('配图里的长辈形象', style: theme.textTheme.bodyLarge),
          const SizedBox(height: CocoSpace.s2),
          Row(
            children: [
              _GenderChip(
                label: '男',
                selected: settings.gender == 'male',
                onTap: () => onGender('male'),
              ),
              const SizedBox(width: CocoSpace.s2),
              _GenderChip(
                label: '女',
                selected: settings.gender == 'female',
                onTap: () => onGender('female'),
              ),
            ],
          ),
          const SizedBox(height: CocoSpace.s4),
          CocoPrimaryButton(
            label: '立即生成',
            loading: generating,
            loadingLabel: '正在生成…',
            onPressed: onGenerate,
          ),
        ],
      ),
    );
  }
}

class _GenderChip extends StatelessWidget {
  const _GenderChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? CocoColors.parentPrimarySoft : CocoColors.neutral100,
      borderRadius: BorderRadius.circular(CocoRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CocoRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: CocoSpace.s4,
            vertical: CocoSpace.s2,
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: selected
                      ? CocoColors.parentPrimary
                      : CocoColors.neutral950,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
          ),
        ),
      ),
    );
  }
}

class _NoteListTile extends StatelessWidget {
  const _NoteListTile({required this.note, required this.onTap});

  final DailyNote note;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateLabel =
        '${note.noteDate.year}-${note.noteDate.month.toString().padLeft(2, '0')}-${note.noteDate.day.toString().padLeft(2, '0')}';
    final preview = note.items.isNotEmpty
        ? note.items.first
        : (note.bodyText.isNotEmpty ? note.bodyText : '（无正文）');

    return Material(
      color: CocoColors.white,
      borderRadius: BorderRadius.circular(CocoRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CocoRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(CocoSpace.s4),
          child: Row(
            children: [
              if (note.images.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(CocoRadius.md),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: DailyNoteImage(urlPath: note.images.first.urlPath),
                  ),
                )
              else
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: CocoColors.parentPrimarySoft,
                    borderRadius: BorderRadius.circular(CocoRadius.md),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '记',
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: CocoColors.parentPrimary,
                    ),
                  ),
                ),
              const SizedBox(width: CocoSpace.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dateLabel, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: CocoColors.neutral700,
                      ),
                    ),
                    if (note.sharedAt != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '已发给家人',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: CocoColors.parentPrimary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: CocoColors.neutral500),
            ],
          ),
        ),
      ),
    );
  }
}
