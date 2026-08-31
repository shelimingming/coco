package com.sheliming.coco

import android.annotation.SuppressLint
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.TextView
import androidx.core.content.ContextCompat

/**
 * 系统悬浮狗：通话/投屏划到后台时显示，提示仍可对话（可看屏），点击回 App。
 */
class CocoOverlayService : Service() {
    private var windowManager: WindowManager? = null
    private var bubbleView: View? = null
    private var labelView: TextView? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_HIDE -> {
                removeBubble()
                stopSelf()
                return START_NOT_STICKY
            }
            ACTION_SHOW -> {
                val mode = intent.getStringExtra(EXTRA_MODE)
                    ?: if (intent.getBooleanExtra(EXTRA_SCREEN_SHARING, false)) {
                        MODE_WATCHING
                    } else {
                        MODE_LISTENING
                    }
                showBubble(mode)
            }
            ACTION_UPDATE -> {
                val mode = intent.getStringExtra(EXTRA_MODE) ?: MODE_WATCHING
                updateLabel(mode)
            }
        }
        return START_STICKY
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun showBubble(mode: String) {
        if (!canDrawOverlays(this)) {
            stopSelf()
            return
        }
        removeBubble()

        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        windowManager = wm

        val density = resources.displayMetrics.density
        val size = (72 * density).toInt()
        val pad = (8 * density).toInt()

        val container = FrameLayout(this).apply {
            setBackgroundColor(0x00000000)
            setPadding(pad, pad, pad, pad)
        }

        val image = ImageView(this).apply {
            setImageResource(R.drawable.coco_bubble)
            scaleType = ImageView.ScaleType.CENTER_CROP
            background = ContextCompat.getDrawable(this@CocoOverlayService, R.drawable.coco_bubble_ring)
            layoutParams = FrameLayout.LayoutParams(size, size)
        }
        container.addView(image)

        // 投屏态用更大字号与更高对比，老人划走后一眼能看懂「在看屏」
        val label = TextView(this).apply {
            text = labelForMode(mode)
            textSize = if (mode == MODE_LISTENING) 11f else 13f
            setTextColor(0xFFFFFFFF.toInt())
            setBackgroundColor(0xF0C85F36.toInt())
            setPadding(
                (10 * density).toInt(),
                (3 * density).toInt(),
                (10 * density).toInt(),
                (3 * density).toInt(),
            )
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            ).apply {
                gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            }
        }
        container.addView(label)
        labelView = label

        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = (12 * density).toInt()
            y = (120 * density).toInt()
        }

        var lastX = 0
        var lastY = 0
        var startX = 0f
        var startY = 0f
        var moved = false

        container.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    lastX = params.x
                    lastY = params.y
                    startX = event.rawX
                    startY = event.rawY
                    moved = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - startX).toInt()
                    val dy = (event.rawY - startY).toInt()
                    if (kotlin.math.abs(dx) > 8 || kotlin.math.abs(dy) > 8) moved = true
                    // END gravity：x 增大向左移
                    params.x = (lastX - dx).coerceAtLeast(0)
                    params.y = (lastY + dy).coerceAtLeast(0)
                    wm.updateViewLayout(container, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) {
                        val launch = Intent(this, MainActivity::class.java).apply {
                            addFlags(
                                Intent.FLAG_ACTIVITY_NEW_TASK or
                                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                                    Intent.FLAG_ACTIVITY_CLEAR_TOP,
                            )
                        }
                        startActivity(launch)
                    }
                    true
                }
                else -> false
            }
        }

        wm.addView(container, params)
        bubbleView = container
        isShowing = true
        currentMode = mode
    }

    private fun updateLabel(mode: String) {
        val label = labelView
        if (label == null || bubbleView == null) {
            // 尚未展示时按新模式拉起
            if (canDrawOverlays(this)) {
                showBubble(mode)
            }
            return
        }
        label.text = labelForMode(mode)
        label.textSize = if (mode == MODE_LISTENING) 11f else 13f
        currentMode = mode
    }

    private fun removeBubble() {
        val view = bubbleView ?: return
        try {
            windowManager?.removeView(view)
        } catch (_: Exception) {
        }
        bubbleView = null
        labelView = null
        isShowing = false
        currentMode = MODE_LISTENING
    }

    override fun onDestroy() {
        removeBubble()
        super.onDestroy()
    }

    companion object {
        const val ACTION_SHOW = "com.sheliming.coco.OVERLAY_SHOW"
        const val ACTION_HIDE = "com.sheliming.coco.OVERLAY_HIDE"
        const val ACTION_UPDATE = "com.sheliming.coco.OVERLAY_UPDATE"
        const val EXTRA_SCREEN_SHARING = "screenSharing"
        const val EXTRA_MODE = "mode"

        const val MODE_LISTENING = "listening"
        const val MODE_WATCHING = "watching"
        const val MODE_LOOKING = "looking"

        @Volatile
        var isShowing: Boolean = false
            private set

        @Volatile
        var currentMode: String = MODE_LISTENING
            private set

        fun labelForMode(mode: String): String = when (mode) {
            MODE_LOOKING -> "正在看…"
            MODE_WATCHING -> "可可在看屏"
            else -> "可可在听"
        }

        fun canDrawOverlays(context: Context): Boolean {
            return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                Settings.canDrawOverlays(context)
            } else {
                true
            }
        }

        fun show(context: Context, screenSharing: Boolean) {
            showWithMode(
                context,
                if (screenSharing) MODE_WATCHING else MODE_LISTENING,
            )
        }

        fun showWithMode(context: Context, mode: String) {
            val intent = Intent(context, CocoOverlayService::class.java).apply {
                action = ACTION_SHOW
                putExtra(EXTRA_MODE, mode)
                putExtra(EXTRA_SCREEN_SHARING, mode != MODE_LISTENING)
            }
            context.startService(intent)
        }

        fun updateMode(context: Context, mode: String) {
            if (!isShowing) {
                showWithMode(context, mode)
                return
            }
            val intent = Intent(context, CocoOverlayService::class.java).apply {
                action = ACTION_UPDATE
                putExtra(EXTRA_MODE, mode)
            }
            context.startService(intent)
        }

        fun hide(context: Context) {
            val intent = Intent(context, CocoOverlayService::class.java).apply {
                action = ACTION_HIDE
            }
            context.startService(intent)
        }
    }
}
