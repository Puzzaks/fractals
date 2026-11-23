package page.puzzak.fractals

import android.os.Build
import android.view.RoundedCorner
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "page.puzzak.fractals/display",
        ).setMethodCallHandler { call, result ->
            if (call.method == "getTopCornerRadius") {
                val radius = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    window.decorView.rootWindowInsets
                        ?.getRoundedCorner(RoundedCorner.POSITION_TOP_LEFT)
                        ?.radius
                        ?.toDouble() ?: 0.0
                } else {
                    0.0
                }
                result.success(radius)
            } else {
                result.notImplemented()
            }
        }
    }
}
