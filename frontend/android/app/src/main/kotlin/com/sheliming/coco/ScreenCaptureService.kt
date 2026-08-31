package com.sheliming.coco

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.util.DisplayMetrics
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import java.io.ByteArrayOutputStream
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

/**
 * MediaProjection 前台服务：约 2fps 写入最新 JPEG，供 Flutter 按需抽帧。
 */
class ScreenCaptureService : Service() {
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var handlerThread: HandlerThread? = null
    private var handler: Handler? = null

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            tearDown()
            stopSelf()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                tearDown()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_UPDATE_NOTIF -> {
                val text = intent.getStringExtra(EXTRA_NOTIF_TEXT)
                    ?: "打开要看的页面后跟我说"
                updateNotificationText(text)
                return START_STICKY
            }
            ACTION_START -> {
                val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
                @Suppress("DEPRECATION")
                val data = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
                } else {
                    intent.getParcelableExtra(EXTRA_RESULT_DATA)
                }
                if (data == null) {
                    stopSelf()
                    return START_NOT_STICKY
                }
                startInForeground()
                startProjection(resultCode, data)
            }
        }
        return START_STICKY
    }

    private fun startInForeground() {
        ensureChannel()
        val notification = buildNotification("打开要看的页面后跟我说")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // 投屏期间麦克风也在听：合并 mediaProjection + microphone，减少双通知
            val type = if (Build.VERSION.SDK_INT >= 34) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            } else {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            }
            startForeground(NOTIFICATION_ID, notification, type)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        isRunning = true
    }

    private fun buildNotification(contentText: String): Notification {
        val launch = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("可可正在看屏幕")
            .setContentText(contentText)
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setContentIntent(launch)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
    }

    private fun updateNotificationText(contentText: String) {
        if (!isRunning) return
        ensureChannel()
        val nm = getSystemService(NotificationManager::class.java)
        nm.notify(NOTIFICATION_ID, buildNotification(contentText))
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java)
        // 升级重要性：DEFAULT 状态栏可见；仍静音避免打扰老人
        val channel = NotificationChannel(
            CHANNEL_ID,
            "看手机",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "可可看手机投屏时显示"
            setSound(null, null)
            enableVibration(false)
        }
        nm.createNotificationChannel(channel)
    }

    private fun startProjection(resultCode: Int, data: Intent) {
        tearDownCaptureOnly()
        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        val projection = mpm.getMediaProjection(resultCode, data) ?: run {
            stopSelf()
            return
        }
        mediaProjection = projection
        projection.registerCallback(projectionCallback, null)

        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        (getSystemService(Context.WINDOW_SERVICE) as WindowManager).defaultDisplay.getRealMetrics(metrics)
        // 降采样约 720p 宽，控上传体积
        val scale = (720.0 / metrics.widthPixels.coerceAtLeast(1)).coerceAtMost(1.0)
        val width = (metrics.widthPixels * scale).toInt().coerceAtLeast(360)
        val height = (metrics.heightPixels * scale).toInt().coerceAtLeast(640)
        val density = metrics.densityDpi

        handlerThread = HandlerThread("coco-screen-capture").also { it.start() }
        handler = Handler(handlerThread!!.looper)

        val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2)
        imageReader = reader
        // 约 2fps：避免无意义高频 JPEG 编码
        var lastEncodeAt = 0L
        reader.setOnImageAvailableListener({ r ->
            val image = r.acquireLatestImage() ?: return@setOnImageAvailableListener
            try {
                val now = System.currentTimeMillis()
                if (now - lastEncodeAt < 500) {
                    return@setOnImageAvailableListener
                }
                lastEncodeAt = now
                val plane = image.planes[0]
                val buffer = plane.buffer
                val pixelStride = plane.pixelStride
                val rowStride = plane.rowStride
                val rowPadding = rowStride - pixelStride * width
                val bitmap = Bitmap.createBitmap(
                    width + rowPadding / pixelStride,
                    height,
                    Bitmap.Config.ARGB_8888,
                )
                bitmap.copyPixelsFromBuffer(buffer)
                val cropped = Bitmap.createBitmap(bitmap, 0, 0, width, height)
                if (cropped != bitmap) bitmap.recycle()
                val out = ByteArrayOutputStream()
                cropped.compress(Bitmap.CompressFormat.JPEG, 75, out)
                cropped.recycle()
                latestJpegRef.set(out.toByteArray())
                latestCapturedAtMs.set(System.currentTimeMillis())
            } catch (_: Exception) {
                // 单帧失败忽略
            } finally {
                image.close()
            }
        }, handler)

        virtualDisplay = projection.createVirtualDisplay(
            "coco-screen",
            width,
            height,
            density,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader.surface,
            null,
            handler,
        )
    }

    private fun tearDownCaptureOnly() {
        virtualDisplay?.release()
        virtualDisplay = null
        imageReader?.setOnImageAvailableListener(null, null)
        imageReader?.close()
        imageReader = null
        mediaProjection?.unregisterCallback(projectionCallback)
        mediaProjection?.stop()
        mediaProjection = null
        handlerThread?.quitSafely()
        handlerThread = null
        handler = null
    }

    private fun tearDown() {
        tearDownCaptureOnly()
        latestJpegRef.set(null)
        latestCapturedAtMs.set(0L)
        isRunning = false
        stopForeground(STOP_FOREGROUND_REMOVE)
    }

    override fun onDestroy() {
        tearDown()
        super.onDestroy()
    }

    companion object {
        const val ACTION_START = "com.sheliming.coco.SCREEN_CAPTURE_START"
        const val ACTION_STOP = "com.sheliming.coco.SCREEN_CAPTURE_STOP"
        const val ACTION_UPDATE_NOTIF = "com.sheliming.coco.SCREEN_CAPTURE_UPDATE_NOTIF"
        const val EXTRA_RESULT_CODE = "resultCode"
        const val EXTRA_RESULT_DATA = "resultData"
        const val EXTRA_NOTIF_TEXT = "notifText"
        private const val CHANNEL_ID = "coco_screen_share"
        private const val NOTIFICATION_ID = 0xC0C0

        @Volatile
        var isRunning: Boolean = false
            private set

        private val latestJpegRef = AtomicReference<ByteArray?>(null)
        private val latestCapturedAtMs = AtomicLong(0L)

        val latestJpeg: ByteArray?
            get() = latestJpegRef.get()

        val latestCapturedAt: Long
            get() = latestCapturedAtMs.get()

        fun stop(context: Context) {
            val intent = Intent(context, ScreenCaptureService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }

        fun updateNotification(context: Context, text: String) {
            if (!isRunning) return
            val intent = Intent(context, ScreenCaptureService::class.java).apply {
                action = ACTION_UPDATE_NOTIF
                putExtra(EXTRA_NOTIF_TEXT, text)
            }
            context.startService(intent)
        }
    }
}
