import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_scaffold.dart';
import '../../parent/domain/coco_companion_pose.dart';
import '../../parent/presentation/widgets/coco_companion_view.dart';
import '../data/look_api.dart';
import '../domain/models.dart';

/// 帮我看看取图：拍一张或从相册选，上传后进结果页。
class LookCapturePage extends ConsumerStatefulWidget {
  const LookCapturePage({super.key});

  @override
  ConsumerState<LookCapturePage> createState() => _LookCapturePageState();
}

class _LookCapturePageState extends ConsumerState<LookCapturePage> {
  final ImagePicker _picker = ImagePicker();
  File? _preview;
  bool _busy = false;
  String? _errorTitle;
  String? _errorMessage;

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    setState(() {
      _errorTitle = null;
      _errorMessage = null;
    });
    try {
      final file = await _picker.pickImage(
        source: source,
        // 压缩后上传，控制体积
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 85,
      );
      if (file == null) return;
      setState(() => _preview = File(file.path));
      await _submit();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorTitle = '打不开相机或相册';
        _errorMessage = '请到系统设置里允许可可使用相机和相册，然后再试一次。';
      });
    }
  }

  Future<void> _submit() async {
    final file = _preview;
    if (file == null || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(lookApiProvider).look(imageFile: file);
      if (!mounted) return;
      context.push(
        '/parent/look/result',
        extra: LookSession(result: result, imagePath: file.path),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorTitle = '刚才没看清';
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorTitle = '刚才没看清';
        _errorMessage = '网络或服务暂时不可用。您可以重新拍一张，照片没有保存在可可这边。';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CocoScaffold(
      title: '帮我看看',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: CocoSpace.s3),
          child: Center(
            child: ParentChipButton(
              label: '返回',
              onPressed: _busy ? null : () => context.pop(),
            ),
          ),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: CocoColors.neutral100,
                borderRadius: BorderRadius.circular(CocoRadius.xl),
              ),
              clipBehavior: Clip.antiAlias,
              child: _preview != null
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(_preview!, fit: BoxFit.cover),
                        if (_busy)
                          ColoredBox(
                            color: CocoColors.neutral950.withValues(
                              alpha: 0.35,
                            ),
                            child: const Center(
                              child: CocoCompanionView(
                                pose: CocoCompanionPose.idle,
                                size: 120,
                              ),
                            ),
                          ),
                      ],
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(CocoSpace.s6),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CocoCompanionView(
                              pose: CocoCompanionPose.idle,
                              size: 132,
                            ),
                            const SizedBox(height: CocoSpace.s4),
                            Text(
                              '把想看的东西对准镜头，\n或从相册里选一张。',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: CocoColors.neutral700,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ),
          if (_errorTitle != null) ...[
            const SizedBox(height: CocoSpace.s4),
            Container(
              padding: const EdgeInsets.all(CocoSpace.s4),
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  CocoColors.warning.withValues(alpha: 0.12),
                  CocoColors.parentSurface,
                ),
                borderRadius: BorderRadius.circular(CocoRadius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _errorTitle!,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: CocoColors.warning,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: CocoSpace.s2),
                  Text(
                    _errorMessage ?? '',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: CocoColors.neutral700,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: CocoSpace.s5),
          CocoPrimaryButton(
            label: '拍这张',
            loading: _busy,
            loadingLabel: '可可正在看…',
            onPressed: () => _pick(ImageSource.camera),
          ),
          const SizedBox(height: CocoSpace.s3),
          CocoSecondaryButton(
            label: '从相册里选',
            onPressed: _busy ? null : () => _pick(ImageSource.gallery),
          ),
        ],
      ),
    );
  }
}
