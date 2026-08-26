import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import '../../../core/widgets/coco_loading.dart';
import '../../../core/widgets/coco_safe_area.dart';
import '../../care/application/care_providers.dart';
import '../application/messages_providers.dart';
import '../data/messages_api.dart';
import '../domain/models.dart';

/// 子女端报平安 Tab：快捷状态 + 自定义，可可第三人称转述后发送。
class ChildMessagesPage extends ConsumerStatefulWidget {
  const ChildMessagesPage({super.key});

  @override
  ConsumerState<ChildMessagesPage> createState() => _ChildMessagesPageState();
}

class _ChildMessagesPageState extends ConsumerState<ChildMessagesPage> {
  // 与交付稿一致；自定义最多 60 字
  static const _presets = ['吃过饭了', '在忙，一切都好', '已经到家', '准备休息'];
  static const _maxChars = 60;
  static const _customPreviewDelay = Duration(milliseconds: 600);

  final _customController = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _customPreviewDebounce;
  int _previewRequestVersion = 0;
  String? _selectedPreset;
  MessagePreview? _preview;
  _ComposeBusy? _busy;
  String? _error;

  bool get _isBusy => _busy != null;

  @override
  void dispose() {
    _customPreviewDebounce?.cancel();
    _customController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _selectPreset(String text) async {
    if (_isBusy) return;
    _customPreviewDebounce?.cancel();
    _previewRequestVersion++;
    setState(() {
      _selectedPreset = text;
      _customController.text = text;
      _error = null;
    });
    await _previewText(text);
  }

  Future<void> _previewText(String text) async {
    final cleaned = text.trim();
    if (cleaned.isEmpty) {
      setState(() {
        _preview = null;
        _error = '请先选择或输入要发送的内容。';
      });
      return;
    }
    if (cleaned.characters.length > _maxChars) {
      setState(() {
        _error = '最多 $_maxChars 个字，请缩短后再试。';
      });
      return;
    }
    final requestVersion = ++_previewRequestVersion;
    setState(() {
      _busy = _ComposeBusy.preview;
      _error = null;
    });
    try {
      final preview = await ref.read(messagesApiProvider).preview(cleaned);
      if (!mounted || requestVersion != _previewRequestVersion) return;
      setState(() {
        _preview = preview;
        _busy = null;
      });
    } catch (error) {
      if (!mounted || requestVersion != _previewRequestVersion) return;
      setState(() {
        _busy = null;
        _preview = null;
        _error = error is ApiException
            ? error.message
            : '预览失败。您可以再试一次，消息没有发出去。';
      });
    }
  }

  void _onCustomChanged(String value) {
    final cleaned = value.trim();
    _customPreviewDebounce?.cancel();
    _previewRequestVersion++;
    setState(() {
      if (_selectedPreset != null && cleaned != _selectedPreset) {
        _selectedPreset = null;
      }
      if (_preview != null && cleaned != _preview!.originalText) {
        _preview = null;
      }
      if (_busy == _ComposeBusy.preview) {
        _busy = null;
      }
      _error = null;
    });

    if (cleaned.isEmpty || cleaned.characters.length > _maxChars) return;
    _customPreviewDebounce = Timer(_customPreviewDelay, () {
      if (!mounted || _customController.text.trim() != cleaned) return;
      _previewText(cleaned);
    });
  }

  void _previewCustomTextNow() {
    _customPreviewDebounce?.cancel();
    _previewText(_customController.text);
  }

  Future<void> _send() async {
    _customPreviewDebounce?.cancel();
    final preview = _preview;
    if (preview == null) {
      await _previewText(_customController.text);
      return;
    }
    setState(() {
      _busy = _ComposeBusy.send;
      _error = null;
    });
    try {
      await ref
          .read(messagesApiProvider)
          .send(
            originalText: preview.originalText,
            deliveredText: preview.deliveredText,
          );
      ref.invalidate(familyMessagesProvider);
      if (!mounted) return;
      setState(() {
        _previewRequestVersion++;
        _busy = null;
        _selectedPreset = null;
        _customController.clear();
        _preview = null;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('已让可可转达给父母。')));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = null;
        _error = error is ApiException
            ? error.message
            : '发送失败。您可以再试一次，消息没有发出去。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = CocoSafeInsets.paddingOf(context).top;
    final messagesAsync = ref.watch(familyMessagesProvider);

    return Scaffold(
      backgroundColor: CocoColors.childBackground,
      body: messagesAsync.when(
        loading: () => const CocoPageLoading(message: '正在加载…'),
        error: (error, _) {
          if (isFamilyNotFound(error)) {
            return CocoSafeArea(
              child: Padding(
                padding: const EdgeInsets.all(CocoSpace.s5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('报平安', style: theme.textTheme.displayLarge),
                    const SizedBox(height: CocoSpace.s3),
                    Text('请先加入家庭，才能给父母报平安。', style: theme.textTheme.bodyLarge),
                    const Spacer(),
                    CocoPrimaryButton(
                      label: '去加入家庭',
                      onPressed: () => context.push('/child/join'),
                    ),
                  ],
                ),
              ),
            );
          }
          return CocoSafeArea(
            child: Padding(
              padding: const EdgeInsets.all(CocoSpace.s5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    error is ApiException
                        ? error.message
                        : '加载失败。您可以再试一次，数据没有丢失。',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const Spacer(),
                  CocoPrimaryButton(
                    label: '再试一次',
                    onPressed: () => ref.invalidate(familyMessagesProvider),
                  ),
                ],
              ),
            ),
          );
        },
        data: (_) => Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  CocoSpace.s5,
                  top + CocoSpace.s4,
                  CocoSpace.s5,
                  CocoSpace.s4,
                ),
                children: [
                  Text(
                    '报平安',
                    style: theme.textTheme.displayLarge?.copyWith(fontSize: 28),
                  ),
                  const SizedBox(height: CocoSpace.s2),
                  Text(
                    '选择快捷状态或自定义',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: CocoColors.neutral700,
                    ),
                  ),
                  const SizedBox(height: CocoSpace.s5),
                  Wrap(
                    spacing: CocoSpace.s3,
                    runSpacing: CocoSpace.s3,
                    children: _presets.map((text) {
                      final selected = _selectedPreset == text;
                      return _PresetChip(
                        label: text,
                        selected: selected,
                        onTap: _isBusy ? null : () => _selectPreset(text),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: CocoSpace.s5),
                  _EditableMessageCard(
                    controller: _customController,
                    focusNode: _focusNode,
                    enabled: _busy != _ComposeBusy.send,
                    maxChars: _maxChars,
                    onChanged: _onCustomChanged,
                    onSubmit: _previewCustomTextNow,
                  ),
                  const SizedBox(height: CocoSpace.s6),
                  Text('可可将这样转述', style: theme.textTheme.titleMedium),
                  const SizedBox(height: CocoSpace.s3),
                  _RelayPreview(
                    preview: _preview,
                    loading: _busy == _ComposeBusy.preview,
                  ),
                  const SizedBox(height: CocoSpace.s2),
                  Text(
                    '可可以自己的身份转述，不会代替孩子说话',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: CocoColors.neutral500,
                      fontSize: 13,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: CocoSpace.s4),
                    Text(
                      _error!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: CocoColors.danger,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            CocoSafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  CocoSpace.s5,
                  CocoSpace.s2,
                  CocoSpace.s5,
                  CocoSpace.s3,
                ),
                child: CocoPrimaryButton(
                  label: '让可可转达',
                  loading: _busy == _ComposeBusy.send,
                  loadingLabel: '正在转达…',
                  onPressed: _isBusy
                      ? null
                      : () async {
                          if (_preview == null) {
                            await _previewText(_customController.text);
                            if (_preview != null && mounted) await _send();
                          } else {
                            await _send();
                          }
                        },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? CocoColors.childPrimary : CocoColors.childSurface,
      borderRadius: BorderRadius.circular(CocoRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(CocoRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: CocoSpace.s4,
            vertical: CocoSpace.s3,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(CocoRadius.md),
            border: Border.all(
              color: selected
                  ? CocoColors.childPrimary
                  : CocoColors.childBorder,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: selected ? CocoColors.white : CocoColors.neutral950,
            ),
          ),
        ),
      ),
    );
  }
}

class _EditableMessageCard extends StatelessWidget {
  const _EditableMessageCard({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.maxChars,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final int maxChars;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        CocoSpace.s4,
        CocoSpace.s3,
        CocoSpace.s3,
        CocoSpace.s3,
      ),
      decoration: BoxDecoration(
        color: CocoColors.childSurface,
        borderRadius: BorderRadius.circular(CocoRadius.lg),
        border: Border.all(color: CocoColors.childBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              maxLines: 3,
              maxLength: maxChars,
              onChanged: onChanged,
              onEditingComplete: onSubmit,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                counterText: '',
                hintText: '写一句想让可可转达的话',
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          IconButton(
            onPressed: enabled
                ? () {
                    focusNode.requestFocus();
                  }
                : null,
            icon: SvgPicture.asset(
              'assets/icons/child/icon-edit.svg',
              width: 20,
              height: 20,
              colorFilter: const ColorFilter.mode(
                CocoColors.childPrimary,
                BlendMode.srcIn,
              ),
            ),
            tooltip: '编辑',
          ),
        ],
      ),
    );
  }
}

class _RelayPreview extends StatelessWidget {
  const _RelayPreview({required this.preview, required this.loading});

  final MessagePreview? preview;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text =
        preview?.deliveredText ??
        (loading ? '可可正在组织转述…' : '选择或输入内容后，这里会显示可可的转述预览。');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(CocoSpace.s4),
      decoration: BoxDecoration(
        color: CocoColors.childPrimarySoft,
        borderRadius: BorderRadius.circular(CocoRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(CocoRadius.md),
            child: Image.asset(
              'assets/images/child/peace_coco_avatar.png',
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              excludeFromSemantics: true,
            ),
          ),
          const SizedBox(width: CocoSpace.s3),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: CocoColors.neutral950,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _ComposeBusy { preview, send }
