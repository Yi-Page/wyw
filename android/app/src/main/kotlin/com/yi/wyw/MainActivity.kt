package com.yi.wyw

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.StatFs
import android.util.Rational
import androidx.annotation.NonNull
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {

    private val CHANNEL = "com.yi.wyw/intent"
    private val STORAGE_CHANNEL = "com.yi.wyw/storage"
    private val PIP_CHANNEL = "com.yi.wyw/pip"

    private var intentChannel: MethodChannel? = null
    private var pipChannel: MethodChannel? = null

    private var pipIsPlaying = false
    private var pipActionReceiverRegistered = false
    private var autoEnterPipOnHomeGesture = false
    private var pipInPlayerPage = false
    private var pipAspectWidth = 16
    private var pipAspectHeight = 9
    private var androidFullscreen = false

    private val actionPipPlayPause = "com.yi.wyw.pip.PLAY_PAUSE"
    private val actionPipForward = "com.yi.wyw.pip.FORWARD"

    private val pipActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.action ?: return
            when (action) {
                actionPipPlayPause -> notifyFlutterPipAction("play_pause")
                actionPipForward -> notifyFlutterPipAction("forward")
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        registerPipActionReceiverIfNeeded()
    }

    override fun onDestroy() {
        unregisterPipActionReceiverIfNeeded()
        super.onDestroy()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        // 从分屏 / 通知栏 / 其他窗口返回时重新隐藏系统栏，避免全屏状态被系统打断。
        if (hasFocus && androidFullscreen) {
            applyAndroidFullscreen()
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupIntentChannel(flutterEngine)
        setupStorageChannel(flutterEngine)
        setupPipChannel(flutterEngine)
    }

    private fun setupIntentChannel(flutterEngine: FlutterEngine) {
        intentChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        intentChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "openWithMime" -> {
                    val url = call.argument<String>("url")
                    val mimeType = call.argument<String>("mimeType")
                    if (url != null && mimeType != null) {
                        openWithMime(url, mimeType)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "URL and MIME type required", null)
                    }
                }
                "checkIfInMultiWindowMode" -> result.success(checkIfInMultiWindowMode())
                "getAndroidSdkVersion" -> result.success(Build.VERSION.SDK_INT)
                "isRunningOnX11" -> result.success(false)
                "enterFullscreen" -> {
                    enterAndroidFullscreen()
                    result.success(null)
                }
                "exitFullscreen" -> {
                    exitAndroidFullscreen()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun setupStorageChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "getAvailableStorage") {
                    val path = call.argument<String>("path") ?: filesDir.absolutePath
                    result.success(getAvailableStorage(path))
                } else {
                    result.notImplemented()
                }
            }
    }

    private fun setupPipChannel(flutterEngine: FlutterEngine) {
        pipChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
        pipChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isPictureInPictureSupported" -> result.success(isPictureInPictureSupported())
                "enterPictureInPictureMode" -> {
                    pipAspectWidth = call.argument<Int>("width") ?: pipAspectWidth
                    pipAspectHeight = call.argument<Int>("height") ?: pipAspectHeight
                    result.success(enterPictureInPicture())
                }
                "updatePictureInPictureActions" -> {
                    pipIsPlaying = call.argument<Boolean>("playing") ?: false
                    pipAspectWidth = call.argument<Int>("width") ?: pipAspectWidth
                    pipAspectHeight = call.argument<Int>("height") ?: pipAspectHeight
                    refreshPictureInPictureParamsIfNeeded()
                    result.success(true)
                }
                "setAndroidAutoEnterPIPEnabled" -> {
                    autoEnterPipOnHomeGesture = call.argument<Boolean>("enabled") ?: false
                    refreshPictureInPictureParamsIfNeeded()
                    result.success(true)
                }
                "setAndroidPIPInPlayerPage" -> {
                    pipInPlayerPage = call.argument<Boolean>("inPlayerPage") ?: false
                    refreshPictureInPictureParamsIfNeeded()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun openWithMime(url: String, mimeType: String) {
        val intent = Intent()
        intent.action = Intent.ACTION_VIEW
        intent.setDataAndType(Uri.parse(url), mimeType)
        startActivity(intent)
    }

    private fun checkIfInMultiWindowMode(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            this.isInMultiWindowMode
        } else {
            false
        }
    }

    private fun enterAndroidFullscreen() {
        androidFullscreen = true
        applyAndroidFullscreen()
    }

    private fun applyAndroidFullscreen() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowCompat.getInsetsController(window, window.decorView).apply {
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
        }
    }

    private fun exitAndroidFullscreen() {
        androidFullscreen = false
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowCompat.getInsetsController(window, window.decorView)
            .show(WindowInsetsCompat.Type.systemBars())
    }

    private fun isPictureInPictureSupported(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }
        return packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun enterPictureInPicture(): Boolean {
        if (!isPictureInPictureSupported()) {
            return false
        }
        if (isInPictureInPictureMode) {
            return true
        }
        return enterPictureInPictureMode(buildPictureInPictureParams())
    }

    private fun refreshPictureInPictureParamsIfNeeded() {
        if (!isPictureInPictureSupported()) {
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            setPictureInPictureParams(buildPictureInPictureParams())
        }
    }

    private fun buildPictureInPictureParams(): PictureInPictureParams {
        val actions = buildPipActions()
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(pipAspectWidth, pipAspectHeight))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoEnterPipOnHomeGesture && pipInPlayerPage)
            builder.setSeamlessResizeEnabled(false)
        }
        if (actions.isNotEmpty()) {
            builder.setActions(actions)
        }
        return builder.build()
    }

    private fun buildPipActions(): List<RemoteAction> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return emptyList()
        }
        val allActions = mutableListOf<RemoteAction>(
            createPipAction(
                action = actionPipPlayPause,
                requestCode = 1001,
                iconRes = if (pipIsPlaying) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play,
                title = if (pipIsPlaying) "Pause" else "Play",
                description = if (pipIsPlaying) "Pause playback" else "Play playback",
                enabled = true
            ),
            createPipAction(
                action = actionPipForward,
                requestCode = 1002,
                iconRes = android.R.drawable.ic_media_ff,
                title = "Forward",
                description = "Forward by custom seconds",
                enabled = true
            )
        )
        val maxActions = maxNumPictureInPictureActions
        if (allActions.size > maxActions) {
            allActions.subList(maxActions, allActions.size).clear()
        }
        return allActions
    }

    private fun createPipAction(
        action: String,
        requestCode: Int,
        iconRes: Int,
        title: String,
        description: String,
        enabled: Boolean
    ): RemoteAction {
        val intent = Intent(action).setPackage(packageName)
        val pendingIntent = PendingIntent.getBroadcast(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return RemoteAction(
            Icon.createWithResource(this, iconRes),
            title,
            description,
            pendingIntent
        ).apply {
            setEnabled(enabled)
        }
    }

    private fun notifyFlutterPipAction(action: String) {
        pipChannel?.invokeMethod("onAction", mapOf("action" to action))
    }

    private fun registerPipActionReceiverIfNeeded() {
        if (pipActionReceiverRegistered || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val filter = IntentFilter().apply {
            addAction(actionPipPlayPause)
            addAction(actionPipForward)
        }
        ContextCompat.registerReceiver(
            this,
            pipActionReceiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
        pipActionReceiverRegistered = true
    }

    private fun unregisterPipActionReceiverIfNeeded() {
        if (!pipActionReceiverRegistered) {
            return
        }
        unregisterReceiver(pipActionReceiver)
        pipActionReceiverRegistered = false
    }

    private fun getAvailableStorage(path: String): Long {
        return try {
            val stat = StatFs(path)
            stat.availableBlocksLong * stat.blockSizeLong
        } catch (e: Exception) {
            -1L
        }
    }
}
