package com.gkeep.app.gkeep

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.gkeep.app/share_intent"
    private var methodChannel: MethodChannel? = null
    private var pendingSharePayload: Map<String, Any?>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleShareIntent(intent, notifyImmediate = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent, notifyImmediate = true)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedData" -> {
                    result.success(pendingSharePayload)
                    pendingSharePayload = null
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun handleShareIntent(intent: Intent?, notifyImmediate: Boolean) {
        if (intent == null) return
        val action = intent.action
        val type = intent.type ?: return

        if (Intent.ACTION_SEND == action) {
            if (type.startsWith("text/")) {
                val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
                val sharedSubject = intent.getStringExtra(Intent.EXTRA_SUBJECT)
                if (!sharedText.isNullOrBlank()) {
                    val payload = mapOf(
                        "title" to (sharedSubject ?: ""),
                        "text" to sharedText,
                        "images" to emptyList<String>()
                    )
                    dispatchPayload(payload, notifyImmediate)
                }
            } else if (type.startsWith("image/")) {
                val uri = getParcelableUri(intent)
                val copiedPath = uri?.let { copyUriToCache(it) }
                if (copiedPath != null) {
                    val payload = mapOf(
                        "title" to (intent.getStringExtra(Intent.EXTRA_SUBJECT) ?: ""),
                        "text" to (intent.getStringExtra(Intent.EXTRA_TEXT) ?: ""),
                        "images" to listOf(copiedPath)
                    )
                    dispatchPayload(payload, notifyImmediate)
                }
            }
        } else if (Intent.ACTION_SEND_MULTIPLE == action && type.startsWith("image/")) {
            val uris = getParcelableUriList(intent)
            val copiedPaths = uris.mapNotNull { copyUriToCache(it) }
            if (copiedPaths.isNotEmpty()) {
                val payload = mapOf(
                    "title" to (intent.getStringExtra(Intent.EXTRA_SUBJECT) ?: ""),
                    "text" to (intent.getStringExtra(Intent.EXTRA_TEXT) ?: ""),
                    "images" to copiedPaths
                )
                dispatchPayload(payload, notifyImmediate)
            }
        }
    }

    private fun dispatchPayload(payload: Map<String, Any?>, notifyImmediate: Boolean) {
        if (notifyImmediate && methodChannel != null) {
            methodChannel?.invokeMethod("onSharedData", payload)
        } else {
            pendingSharePayload = payload
        }
    }

    @Suppress("DEPRECATION")
    private fun getParcelableUri(intent: Intent): Uri? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }
    }

    @Suppress("DEPRECATION")
    private fun getParcelableUriList(intent: Intent): List<Uri> {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java) ?: emptyList()
        } else {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: emptyList()
        }
    }

    private fun copyUriToCache(uri: Uri): String? {
        return try {
            val inputStream = contentResolver.openInputStream(uri) ?: return null
            val outFile = File(cacheDir, "shared_${System.currentTimeMillis()}.jpg")
            FileOutputStream(outFile).use { output ->
                inputStream.copyTo(output)
            }
            inputStream.close()
            outFile.absolutePath
        } catch (e: Exception) {
            null
        }
    }
}
