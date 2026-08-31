package com.sheliming.coco

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MethodChannel：看手机投屏 + 后台语音保活/悬浮狗。
 */
class MainActivity : FlutterActivity() {
    private val screenShareChannel = "coco/screen_share"
    private val voiceBgChannel = "coco/voice_background"
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, screenShareChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> requestProjection(result)
                    "stop" -> {
                        ScreenCaptureService.stop(this)
                        result.success(null)
                    }
                    "captureLatestFrame" -> result.success(ScreenCaptureService.latestJpeg)
                    "captureLatestFrameMeta" -> {
                        // 带采集时间戳，供 Flutter 判帧是否够新
                        val bytes = ScreenCaptureService.latestJpeg
                        val at = ScreenCaptureService.latestCapturedAt
                        if (bytes == null || at <= 0L) {
                            result.success(null)
                        } else {
                            result.success(
                                mapOf(
                                    "bytes" to bytes,
                                    "capturedAtMs" to at,
                                ),
                            )
                        }
                    }
                    "isCapturing" -> result.success(ScreenCaptureService.isRunning)
                    "updateNotification" -> {
                        val text = call.argument<String>("text") ?: "打开要看的页面后跟我说"
                        ScreenCaptureService.updateNotification(this, text)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, voiceBgChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startVoiceKeepAlive" -> {
                        VoiceCallForegroundService.start(this)
                        result.success(null)
                    }
                    "stopVoiceKeepAlive" -> {
                        VoiceCallForegroundService.stop(this)
                        CocoOverlayService.hide(this)
                        result.success(null)
                    }
                    "showBubble" -> {
                        ensureOverlayPermissionThen {
                            val mode = call.argument<String>("mode")
                            if (mode != null) {
                                CocoOverlayService.showWithMode(this, mode)
                            } else {
                                val sharing = call.argument<Boolean>("screenSharing") == true
                                CocoOverlayService.show(this, sharing)
                            }
                        }
                        result.success(null)
                    }
                    "updateBubble" -> {
                        val mode = call.argument<String>("mode") ?: CocoOverlayService.MODE_WATCHING
                        if (CocoOverlayService.canDrawOverlays(this)) {
                            CocoOverlayService.updateMode(this, mode)
                        }
                        result.success(null)
                    }
                    "hideBubble" -> {
                        CocoOverlayService.hide(this)
                        result.success(null)
                    }
                    "hasOverlayPermission" -> {
                        result.success(CocoOverlayService.canDrawOverlays(this))
                    }
                    "requestOverlayPermission" -> {
                        openOverlaySettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun ensureOverlayPermissionThen(block: () -> Unit) {
        if (CocoOverlayService.canDrawOverlays(this)) {
            block()
        } else {
            // 无权限时仍可依赖通知栏；尝试引导设置
            openOverlaySettings()
        }
    }

    private fun openOverlaySettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName"),
            )
            startActivity(intent)
        } catch (_: Exception) {
        }
    }

    private fun requestProjection(result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("busy", "已有投屏授权进行中", null)
            return
        }
        pendingResult = result
        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        @Suppress("DEPRECATION")
        startActivityForResult(mpm.createScreenCaptureIntent(), REQUEST_MEDIA_PROJECTION)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_MEDIA_PROJECTION) return
        val pending = pendingResult
        pendingResult = null
        if (pending == null) return

        if (resultCode != Activity.RESULT_OK || data == null) {
            pending.success(false)
            return
        }

        val intent = Intent(this, ScreenCaptureService::class.java).apply {
            action = ScreenCaptureService.ACTION_START
            putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
            putExtra(ScreenCaptureService.EXTRA_RESULT_DATA, data)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
        window.decorView.postDelayed({
            pending.success(ScreenCaptureService.isRunning)
        }, 600)
    }

    companion object {
        private const val REQUEST_MEDIA_PROJECTION = 0xC0C0
    }
}
