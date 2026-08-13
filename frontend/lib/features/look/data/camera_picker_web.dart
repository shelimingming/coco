import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/coco_button.dart';
import 'camera_picker.dart';

CameraPicker createCameraPicker() => WebCameraPicker();

/// Web：getUserMedia 预览 + 画布抓帧，避免桌面 Chrome 退化成选文件。
class WebCameraPicker implements CameraPicker {
  @override
  Future<CameraPickResult> pick({required BuildContext context}) async {
    final result = await showDialog<CameraPickResult>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => const _WebCameraCaptureDialog(),
    );
    return result ?? const CameraPickResult.cancelled();
  }
}

class _WebCameraCaptureDialog extends StatefulWidget {
  const _WebCameraCaptureDialog();

  @override
  State<_WebCameraCaptureDialog> createState() =>
      _WebCameraCaptureDialogState();
}

class _WebCameraCaptureDialogState extends State<_WebCameraCaptureDialog> {
  static int _viewSeq = 0;

  late final String _viewType;
  web.MediaStream? _stream;
  web.HTMLVideoElement? _video;
  String? _error;
  bool _starting = true;
  bool _capturing = false;

  @override
  void initState() {
    super.initState();
    _viewSeq += 1;
    _viewType = 'coco-web-camera-$_viewSeq';
    // 先建 video，再注册工厂，避免 getUserMedia 早于 HtmlElementView 挂载
    final video = web.HTMLVideoElement()
      ..autoplay = true
      ..muted = true
      ..controls = false;
    video.setAttribute('playsinline', 'true');
    video.style
      ..width = '100%'
      ..height = '100%'
      ..objectFit = 'cover'
      ..backgroundColor = '#000';
    _video = video;
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => video,
    );
    unawaited(_startCamera());
  }

  Future<void> _startCamera() async {
    try {
      final devices = web.window.navigator.mediaDevices;
      // 先试后置；桌面无对应设备时再退回默认摄像头
      web.MediaStream stream;
      try {
        stream = await devices
            .getUserMedia(
              web.MediaStreamConstraints(
                audio: false.toJS,
                video: <String, Object>{
                  'facingMode': 'environment',
                  'width': <String, Object>{'ideal': 1280},
                  'height': <String, Object>{'ideal': 960},
                }.jsify()!,
              ),
            )
            .toDart;
      } catch (_) {
        stream = await devices
            .getUserMedia(
              web.MediaStreamConstraints(audio: false.toJS, video: true.toJS),
            )
            .toDart;
      }
      if (!mounted) {
        _stopTracks(stream);
        return;
      }
      _stream = stream;
      final video = _video;
      if (video != null) {
        video.srcObject = stream;
        await video.play().toDart;
      }
      setState(() {
        _starting = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _error = '摄像头还没有允许使用。请在浏览器地址栏允许摄像头，然后再试一次。';
      });
    }
  }

  Future<void> _capture() async {
    final video = _video;
    if (video == null || _capturing) return;
    final width = video.videoWidth;
    final height = video.videoHeight;
    if (width <= 0 || height <= 0) return;

    setState(() => _capturing = true);
    try {
      // 与 image_picker 一致：最长边不超过 1600
      const maxSide = 1600.0;
      var outW = width.toDouble();
      var outH = height.toDouble();
      final longest = outW > outH ? outW : outH;
      if (longest > maxSide) {
        final scale = maxSide / longest;
        outW = outW * scale;
        outH = outH * scale;
      }

      final canvas = web.HTMLCanvasElement()
        ..width = outW.round()
        ..height = outH.round();
      final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
      ctx.drawImage(
        video,
        0,
        0,
        width,
        height,
        0,
        0,
        canvas.width,
        canvas.height,
      );

      // toDataURL 比 toBlob 回调更稳，便于转 Uint8List
      final dataUrl = canvas.toDataURL('image/jpeg', 0.85.toJS);
      final comma = dataUrl.indexOf(',');
      if (comma < 0) {
        throw StateError('empty jpeg');
      }
      final bytes = Uint8List.fromList(
        base64Decode(dataUrl.substring(comma + 1)),
      );
      if (!mounted) return;
      Navigator.of(context).pop(CameraPickResult.success(bytes));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _capturing = false;
        _error = '没拍下来，请再试一次。';
      });
    }
  }

  void _stopTracks(web.MediaStream stream) {
    final tracks = stream.getTracks().toDart;
    for (final track in tracks) {
      track.stop();
    }
  }

  @override
  void dispose() {
    final stream = _stream;
    if (stream != null) {
      _stopTracks(stream);
    }
    final video = _video;
    if (video != null) {
      video.srcObject = null;
    }
    _stream = null;
    _video = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: CocoColors.parentBackground,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(CocoSpace.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '看眼前',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: CocoColors.neutral950,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: CocoSpace.s2),
              Text(
                '对准要看的东西，再点「拍一张」',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(color: CocoColors.neutral700),
              ),
              const SizedBox(height: CocoSpace.s4),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(CocoRadius.lg),
                  child: ColoredBox(
                    color: CocoColors.neutral950,
                    child: _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(CocoSpace.s5),
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 22,
                                  height: 1.4,
                                  color: CocoColors.white,
                                ),
                              ),
                            ),
                          )
                        : Stack(
                            fit: StackFit.expand,
                            children: [
                              HtmlElementView(viewType: _viewType),
                              if (_starting)
                                const Center(
                                  child: CircularProgressIndicator(
                                    color: CocoColors.white,
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(height: CocoSpace.s5),
              if (_error == null)
                CocoPrimaryButton(
                  label: '拍一张',
                  loading: _capturing,
                  loadingLabel: '正在拍照…',
                  onPressed: _starting || _capturing ? null : _capture,
                )
              else
                CocoPrimaryButton(
                  label: '再试一次',
                  onPressed: () {
                    setState(() {
                      _starting = true;
                      _error = null;
                    });
                    unawaited(_startCamera());
                  },
                ),
              const SizedBox(height: CocoSpace.s3),
              CocoSecondaryButton(
                label: '取消',
                onPressed: _capturing
                    ? null
                    : () => Navigator.of(
                        context,
                      ).pop(const CameraPickResult.cancelled()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
