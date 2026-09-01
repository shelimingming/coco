import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_loading.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../application/daily_notes_providers.dart';
import '../data/daily_notes_api.dart';
import 'daily_note_image.dart';

/// 每日小记设置：自动生成、发给子女、可选参考照。
class DailyNoteSettingsPage extends ConsumerStatefulWidget {
  const DailyNoteSettingsPage({super.key});

  @override
  ConsumerState<DailyNoteSettingsPage> createState() =>
      _DailyNoteSettingsPageState();
}

class _DailyNoteSettingsPageState extends ConsumerState<DailyNoteSettingsPage> {
  bool _uploading = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settingsAsync = ref.watch(dailyNoteSettingsProvider);

    return CocoScaffold(
      title: '小记设置',
      leading: ParentBackButton(onPressed: () => context.pop()),
      leadingWidth: 104,
      body: settingsAsync.when(
        loading: () => const CocoPageLoading(),
        error: (error, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              error is ApiException ? error.message : '设置加载失败。您可以再试一次，数据没有丢失。',
              style: theme.textTheme.bodyLarge,
            ),
            const Spacer(),
            CocoPrimaryButton(
              label: '再试一次',
              onPressed: () => ref.invalidate(dailyNoteSettingsProvider),
            ),
          ],
        ),
        data: (settings) => ListView(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('每天自动生成', style: theme.textTheme.bodyLarge),
              subtitle: Text(
                '默认关闭；开启后每晚 ${settings.generateHour}:00 整理当天聊天',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: CocoColors.neutral700,
                ),
              ),
              value: settings.generateEnabled,
              activeThumbColor: CocoColors.parentPrimary,
              onChanged: (v) => _patch(generateEnabled: v),
            ),
            const SizedBox(height: CocoSpace.s2),
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
              onChanged: (v) => _patch(shareToChildEnabled: v),
            ),
            const SizedBox(height: CocoSpace.s5),
            Text('我的参考照（可选）', style: theme.textTheme.titleMedium),
            const SizedBox(height: CocoSpace.s2),
            Text(
              '有照片时，配图会严格按照片上的样子来画；没有照片时，默认画女性长辈形象。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: CocoColors.neutral700,
              ),
            ),
            const SizedBox(height: CocoSpace.s3),
            if (settings.hasParentPhoto && settings.parentPhotoUrl != null) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(CocoRadius.md),
                  child: SizedBox(
                    width: 96,
                    height: 96,
                    child: DailyNoteImage(url: settings.parentPhotoUrl!),
                  ),
                ),
              ),
              const SizedBox(height: CocoSpace.s3),
            ],
            CocoPrimaryButton(
              label: settings.hasParentPhoto ? '更换照片' : '从相册选择',
              loading: _uploading,
              loadingLabel: '正在上传…',
              onPressed: _uploading ? null : _pickAndUpload,
            ),
            if (settings.hasParentPhoto) ...[
              const SizedBox(height: CocoSpace.s3),
              CocoSecondaryButton(
                label: '删除照片',
                onPressed: _uploading ? null : _deletePhoto,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _patch({
    bool? generateEnabled,
    bool? shareToChildEnabled,
  }) async {
    try {
      await ref
          .read(dailyNotesApiProvider)
          .updateSettings(
            generateEnabled: generateEnabled,
            shareToChildEnabled: shareToChildEnabled,
          );
      ref.invalidate(dailyNoteSettingsProvider);
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _pickAndUpload() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await picked.readAsBytes();
      final name = picked.name.toLowerCase();
      var subtype = 'jpeg';
      var filename = 'parent.jpg';
      if (name.endsWith('.png')) {
        subtype = 'png';
        filename = 'parent.png';
      } else if (name.endsWith('.webp')) {
        subtype = 'webp';
        filename = 'parent.webp';
      }
      await ref
          .read(dailyNotesApiProvider)
          .uploadParentPhoto(
            bytes: bytes,
            filename: filename,
            mimeSubtype: subtype,
          );
      ref.invalidate(dailyNoteSettingsProvider);
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _deletePhoto() async {
    setState(() => _uploading = true);
    try {
      await ref.read(dailyNotesApiProvider).deleteParentPhoto();
      ref.invalidate(dailyNoteSettingsProvider);
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }
}
