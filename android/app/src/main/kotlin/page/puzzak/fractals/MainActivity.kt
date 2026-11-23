package page.puzzak.fractals

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.view.RoundedCorner
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private var displayChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        displayChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "page.puzzak.fractals/display",
        )
        displayChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getTopCornerRadius" -> {
                    val radius = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        window.decorView.rootWindowInsets
                            ?.getRoundedCorner(RoundedCorner.POSITION_TOP_LEFT)
                            ?.radius
                            ?.toDouble() ?: 0.0
                    } else {
                        0.0
                    }
                    result.success(radius)
                }

                "getInitialDeepLink" -> {
                    val link = intent?.dataString
                    intent?.data = null
                    result.success(link)
                }

                "getInstallReferrer" -> {
                    val replied = AtomicBoolean(false)
                    fun replyOnce(value: String?) {
                        if (replied.compareAndSet(false, true)) {
                            result.success(value)
                        }
                    }

                    val referrerClient = try {
                        InstallReferrerClient.newBuilder(applicationContext).build()
                    } catch (_: Exception) {
                        replyOnce(null)
                        return@setMethodCallHandler
                    }

                    try {
                        referrerClient.startConnection(object : InstallReferrerStateListener {
                            override fun onInstallReferrerSetupFinished(responseCode: Int) {
                                val referrer = if (responseCode == InstallReferrerClient.InstallReferrerResponse.OK) {
                                    try {
                                        referrerClient.installReferrer?.installReferrer
                                    } catch (_: Exception) {
                                        null
                                    }
                                } else {
                                    null
                                }
                                try {
                                    referrerClient.endConnection()
                                } catch (_: Exception) {}
                                replyOnce(referrer)
                            }

                            override fun onInstallReferrerServiceDisconnected() {
                                replyOnce(null)
                            }
                        })
                    } catch (_: Exception) {
                        try {
                            referrerClient.endConnection()
                        } catch (_: Exception) {}
                        replyOnce(null)
                    }
                }

                "encodeJpeg" -> {
                    val pngBytes = call.argument<ByteArray>("pngBytes")
                    val quality = (call.argument<Int>("quality") ?: 92).coerceIn(0, 100)
                    if (pngBytes == null) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    try {
                        val bitmap = BitmapFactory.decodeByteArray(pngBytes, 0, pngBytes.size)
                        if (bitmap == null) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        val out = ByteArrayOutputStream()
                        val ok = bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)
                        bitmap.recycle()
                        result.success(if (ok) out.toByteArray() else null)
                    } catch (_: Exception) {
                        result.success(null)
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val link = intent.dataString
        if (link != null) {
            displayChannel?.invokeMethod("onDeepLink", link)
        }
    }
}
