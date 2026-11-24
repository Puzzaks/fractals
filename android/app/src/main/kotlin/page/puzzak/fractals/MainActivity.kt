package page.puzzak.fractals

import android.app.assist.AssistContent
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.RoundedCorner
import android.widget.Toast
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import com.google.android.gms.games.PlayGames
import com.google.android.gms.games.PlayGamesSdk
import com.google.android.gms.games.achievement.Achievement
import com.google.android.gms.games.leaderboard.LeaderboardVariant
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private var displayChannel: MethodChannel? = null
    private var playGamesChannel: MethodChannel? = null
    private var latestShareUrl: String? = null
    private val videoExecutor = Executors.newSingleThreadExecutor()
    private var videoEncoder: Mp4VideoEncoder? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            PlayGamesSdk.initialize(this)
            Log.i("PlayGames", "PlayGamesSdk.initialize called")
        } catch (e: Exception) {
            Log.w("PlayGames", "PlayGamesSdk.initialize failed", e)
        }
    }

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

                "showToast" -> {
                    val message = call.argument<String>("message")
                    val long = call.argument<Boolean>("long") ?: false
                    if (!message.isNullOrEmpty()) {
                        runOnUiThread {
                            Toast.makeText(
                                this,
                                message,
                                if (long) Toast.LENGTH_LONG else Toast.LENGTH_SHORT,
                            ).show()
                        }
                    }
                    result.success(true)
                }

                "setAssistShareUrl" -> {
                    latestShareUrl = call.argument<String>("url")
                    result.success(true)
                }

                "startExportNotification" -> {
                    val title = call.argument<String>("title") ?: "Exporting"
                    val detail = call.argument<String>("detail") ?: ""
                    try {
                        val serviceIntent = Intent(this, ExportForegroundService::class.java).apply {
                            action = ExportForegroundService.ACTION_START
                            putExtra(ExportForegroundService.EXTRA_TITLE, title)
                            putExtra(ExportForegroundService.EXTRA_DETAIL, detail)
                            putExtra(ExportForegroundService.EXTRA_PROGRESS, 0.0)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        Log.w("ExportService", "startExportNotification failed", e)
                        result.success(false)
                    }
                }

                "updateExportNotification" -> {
                    val title = call.argument<String>("title") ?: "Exporting"
                    val detail = call.argument<String>("detail") ?: ""
                    val progress = call.argument<Number>("progress")?.toDouble() ?: 0.0
                    try {
                        val serviceIntent = Intent(this, ExportForegroundService::class.java).apply {
                            action = ExportForegroundService.ACTION_UPDATE
                            putExtra(ExportForegroundService.EXTRA_TITLE, title)
                            putExtra(ExportForegroundService.EXTRA_DETAIL, detail)
                            putExtra(ExportForegroundService.EXTRA_PROGRESS, progress)
                        }
                        startService(serviceIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.w("ExportService", "updateExportNotification failed", e)
                        result.success(false)
                    }
                }

                "stopExportNotification" -> {
                    try {
                        val serviceIntent = Intent(this, ExportForegroundService::class.java).apply {
                            action = ExportForegroundService.ACTION_STOP
                        }
                        startService(serviceIntent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            stopService(Intent(this, ExportForegroundService::class.java))
                        } catch (_: Exception) {}
                        Log.w("ExportService", "stopExportNotification failed", e)
                        result.success(false)
                    }
                }

                "startVideoEncode" -> {
                    val path = call.argument<String>("path")
                    val width = call.argument<Number>("width")?.toInt()
                    val height = call.argument<Number>("height")?.toInt()
                    val fps = call.argument<Number>("fps")?.toInt() ?: 30
                    if (path.isNullOrEmpty() || width == null || height == null || width <= 0 || height <= 0) {
                        result.error("INVALID_ARGS", "Invalid video encode arguments", null)
                        return@setMethodCallHandler
                    }
                    videoExecutor.execute {
                        try {
                            videoEncoder?.release()
                            videoEncoder = Mp4VideoEncoder(path, width, height, fps)
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            Log.e("Mp4VideoEncoder", "startVideoEncode failed", e)
                            videoEncoder?.release()
                            videoEncoder = null
                            runOnUiThread { result.error("ENCODE_START_FAILED", e.message, null) }
                        }
                    }
                }

                "appendVideoFrame" -> {
                    val pngBytes = call.argument<ByteArray>("pngBytes")
                    if (pngBytes == null) {
                        result.error("INVALID_ARGS", "Missing pngBytes", null)
                        return@setMethodCallHandler
                    }
                    videoExecutor.execute {
                        try {
                            val encoder = videoEncoder
                                ?: throw IllegalStateException("Video encoder is not started")
                            encoder.appendFrame(pngBytes)
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            Log.e("Mp4VideoEncoder", "appendVideoFrame failed", e)
                            runOnUiThread { result.error("ENCODE_FRAME_FAILED", e.message, null) }
                        }
                    }
                }

                "finishVideoEncode" -> {
                    videoExecutor.execute {
                        try {
                            videoEncoder?.finish()
                            videoEncoder = null
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            Log.e("Mp4VideoEncoder", "finishVideoEncode failed", e)
                            videoEncoder?.release()
                            videoEncoder = null
                            runOnUiThread { result.error("ENCODE_FINISH_FAILED", e.message, null) }
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }

        playGamesChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "page.puzzak.fractals/play_games",
        )
        playGamesChannel?.setMethodCallHandler { call, result ->
            val replied = AtomicBoolean(false)
            fun replyOnce(value: Any?) {
                if (replied.compareAndSet(false, true)) {
                    result.success(value)
                }
            }

            when (call.method) {
                "isSignedIn" -> {
                    try {
                        PlayGames.getGamesSignInClient(this).isAuthenticated
                            .addOnCompleteListener { task ->
                                val authenticated = try {
                                    task.isSuccessful && (task.result?.isAuthenticated == true)
                                } catch (e: Exception) {
                                    Log.w("PlayGames", "isSignedIn result exception", e)
                                    false
                                }
                                Log.i("PlayGames", "isSignedIn: isSuccessful=${task.isSuccessful}, isAuthenticated=$authenticated")
                                if (!task.isSuccessful) {
                                    Log.w("PlayGames", "isSignedIn failed", task.exception)
                                }
                                replyOnce(authenticated)
                            }
                    } catch (e: Exception) {
                        Log.w("PlayGames", "isSignedIn exception", e)
                        replyOnce(false)
                    }
                }

                "signIn" -> {
                    try {
                        PlayGames.getGamesSignInClient(this).signIn()
                            .addOnCompleteListener { task ->
                                val authenticated = try {
                                    task.isSuccessful && (task.result?.isAuthenticated == true)
                                } catch (e: Exception) {
                                    Log.w("PlayGames", "signIn result exception", e)
                                    false
                                }
                                Log.i("PlayGames", "signIn: isSuccessful=${task.isSuccessful}, isAuthenticated=$authenticated")
                                if (!task.isSuccessful) {
                                    Log.w("PlayGames", "signIn failed", task.exception)
                                }
                                replyOnce(authenticated)
                            }
                    } catch (e: Exception) {
                        Log.w("PlayGames", "signIn exception", e)
                        replyOnce(false)
                    }
                }

                "getPlayerName" -> {
                    try {
                        PlayGames.getPlayersClient(this).currentPlayer
                            .addOnCompleteListener { task ->
                                if (task.isSuccessful) {
                                    replyOnce(task.result?.displayName)
                                } else {
                                    Log.w("PlayGames", "getPlayerName failed", task.exception)
                                    replyOnce(null)
                                }
                            }
                    } catch (e: Exception) {
                        Log.w("PlayGames", "getPlayerName exception", e)
                        replyOnce(null)
                    }
                }

                "submitScore" -> {
                    val leaderboardId = call.argument<String>("leaderboardId")
                    val score = call.argument<Number>("score")?.toLong()
                    if (leaderboardId.isNullOrEmpty() || score == null) {
                        Log.w("PlayGames", "submitScore skipped: invalid args (leaderboardId=$leaderboardId, score=$score)")
                        replyOnce(false)
                        return@setMethodCallHandler
                    }
                    try {
                        PlayGames.getLeaderboardsClient(this).submitScore(leaderboardId, score)
                        Log.i("PlayGames", "submitScore: leaderboardId=$leaderboardId, score=$score")
                        replyOnce(true)
                    } catch (e: Exception) {
                        Log.w("PlayGames", "submitScore failed: leaderboardId=$leaderboardId", e)
                        replyOnce(false)
                    }
                }

                "loadPlayerScore" -> {
                    val leaderboardId = call.argument<String>("leaderboardId")
                    if (leaderboardId.isNullOrEmpty()) {
                        Log.w("PlayGames", "loadPlayerScore skipped: missing leaderboardId")
                        replyOnce(null)
                        return@setMethodCallHandler
                    }
                    try {
                        PlayGames.getLeaderboardsClient(this)
                            .loadCurrentPlayerLeaderboardScore(
                                leaderboardId,
                                LeaderboardVariant.TIME_SPAN_ALL_TIME,
                                LeaderboardVariant.COLLECTION_PUBLIC,
                            )
                            .addOnCompleteListener { task ->
                                val scoreData = try {
                                    if (task.isSuccessful) {
                                        task.result?.get()?.let { score ->
                                            mapOf<String, Any>(
                                                "rank" to score.rank,
                                                "rawScore" to score.rawScore,
                                                "displayRank" to score.displayRank,
                                            )
                                        }
                                    } else {
                                        Log.w("PlayGames", "loadPlayerScore failed: leaderboardId=$leaderboardId", task.exception)
                                        null
                                    }
                                } catch (e: Exception) {
                                    Log.w("PlayGames", "loadPlayerScore result exception: leaderboardId=$leaderboardId", e)
                                    null
                                }
                                if (task.isSuccessful) {
                                    Log.i("PlayGames", "loadPlayerScore: leaderboardId=$leaderboardId, hasScore=${scoreData != null}")
                                }
                                replyOnce(scoreData)
                            }
                    } catch (e: Exception) {
                        Log.w("PlayGames", "loadPlayerScore exception: leaderboardId=$leaderboardId", e)
                        replyOnce(null)
                    }
                }

                "unlockAchievement" -> {
                    val achievementId = call.argument<String>("achievementId")
                    if (achievementId.isNullOrEmpty()) {
                        Log.w("PlayGames", "unlockAchievement skipped: missing achievementId")
                        replyOnce(false)
                        return@setMethodCallHandler
                    }
                    try {
                        PlayGames.getAchievementsClient(this).unlock(achievementId)
                        Log.i("PlayGames", "unlockAchievement: achievementId=$achievementId")
                        replyOnce(true)
                    } catch (e: Exception) {
                        Log.w("PlayGames", "unlockAchievement failed: achievementId=$achievementId", e)
                        replyOnce(false)
                    }
                }

                "setAchievementSteps" -> {
                    val achievementId = call.argument<String>("achievementId")
                    val steps = call.argument<Number>("steps")?.toInt()
                    if (achievementId.isNullOrEmpty() || steps == null) {
                        Log.w("PlayGames", "setAchievementSteps skipped: invalid args (achievementId=$achievementId, steps=$steps)")
                        replyOnce(false)
                        return@setMethodCallHandler
                    }
                    try {
                        if (steps > 0) {
                            PlayGames.getAchievementsClient(this).setSteps(achievementId, steps)
                            Log.i("PlayGames", "setAchievementSteps: achievementId=$achievementId, steps=$steps")
                        }
                        replyOnce(true)
                    } catch (e: Exception) {
                        Log.w("PlayGames", "setAchievementSteps failed: achievementId=$achievementId", e)
                        replyOnce(false)
                    }
                }

                "showAllLeaderboards" -> {
                    try {
                        PlayGames.getLeaderboardsClient(this).allLeaderboardsIntent
                            .addOnSuccessListener { intent ->
                                try {
                                    Log.i("PlayGames", "showAllLeaderboards: launching intent")
                                    @Suppress("DEPRECATION")
                                    startActivityForResult(intent, 9001)
                                    replyOnce(true)
                                } catch (e: Exception) {
                                    Log.w("PlayGames", "showAllLeaderboards startActivityForResult failed", e)
                                    replyOnce(false)
                                }
                            }
                            .addOnFailureListener { e ->
                                Log.w("PlayGames", "showAllLeaderboards failed", e)
                                replyOnce(false)
                            }
                            .addOnCanceledListener {
                                Log.i("PlayGames", "showAllLeaderboards canceled")
                                replyOnce(false)
                            }
                    } catch (e: Exception) {
                        Log.w("PlayGames", "showAllLeaderboards exception", e)
                        replyOnce(false)
                    }
                }

                "showLeaderboard" -> {
                    val leaderboardId = call.argument<String>("leaderboardId")
                    if (leaderboardId.isNullOrEmpty()) {
                        Log.w("PlayGames", "showLeaderboard skipped: missing leaderboardId")
                        replyOnce(false)
                        return@setMethodCallHandler
                    }
                    try {
                        PlayGames.getLeaderboardsClient(this).getLeaderboardIntent(leaderboardId)
                            .addOnSuccessListener { intent ->
                                try {
                                    Log.i("PlayGames", "showLeaderboard: launching intent for $leaderboardId")
                                    @Suppress("DEPRECATION")
                                    startActivityForResult(intent, 9002)
                                    replyOnce(true)
                                } catch (e: Exception) {
                                    Log.w("PlayGames", "showLeaderboard startActivityForResult failed: $leaderboardId", e)
                                    replyOnce(false)
                                }
                            }
                            .addOnFailureListener { e ->
                                Log.w("PlayGames", "showLeaderboard failed: $leaderboardId", e)
                                replyOnce(false)
                            }
                            .addOnCanceledListener {
                                Log.i("PlayGames", "showLeaderboard canceled: $leaderboardId")
                                replyOnce(false)
                            }
                    } catch (e: Exception) {
                        Log.w("PlayGames", "showLeaderboard exception: $leaderboardId", e)
                        replyOnce(false)
                    }
                }

                "showAchievements" -> {
                    try {
                        PlayGames.getAchievementsClient(this).achievementsIntent
                            .addOnSuccessListener { intent ->
                                try {
                                    Log.i("PlayGames", "showAchievements: launching intent")
                                    @Suppress("DEPRECATION")
                                    startActivityForResult(intent, 9003)
                                    replyOnce(true)
                                } catch (e: Exception) {
                                    Log.w("PlayGames", "showAchievements startActivityForResult failed", e)
                                    replyOnce(false)
                                }
                            }
                            .addOnFailureListener { e ->
                                Log.w("PlayGames", "showAchievements failed", e)
                                replyOnce(false)
                            }
                            .addOnCanceledListener {
                                Log.i("PlayGames", "showAchievements canceled")
                                replyOnce(false)
                            }
                    } catch (e: Exception) {
                        Log.w("PlayGames", "showAchievements exception", e)
                        replyOnce(false)
                    }
                }

                "loadAchievementsSummary" -> {
                    try {
                        PlayGames.getAchievementsClient(this).load(false)
                            .addOnCompleteListener { task ->
                                if (!task.isSuccessful) {
                                    Log.w("PlayGames", "loadAchievementsSummary failed", task.exception)
                                    replyOnce(null)
                                    return@addOnCompleteListener
                                }
                                try {
                                    val buffer = task.result?.get()
                                    if (buffer == null) {
                                        replyOnce(null)
                                        return@addOnCompleteListener
                                    }
                                    try {
                                        var unlocked = 0
                                        val total = buffer.count
                                        for (i in 0 until total) {
                                            if (buffer.get(i).state == Achievement.STATE_UNLOCKED) {
                                                unlocked++
                                            }
                                        }
                                        Log.i("PlayGames", "loadAchievementsSummary: unlocked=$unlocked, total=$total")
                                        replyOnce(mapOf("unlocked" to unlocked, "total" to total))
                                    } finally {
                                        buffer.release()
                                    }
                                } catch (e: Exception) {
                                    Log.w("PlayGames", "loadAchievementsSummary result exception", e)
                                    replyOnce(null)
                                }
                            }
                    } catch (e: Exception) {
                        Log.w("PlayGames", "loadAchievementsSummary exception", e)
                        replyOnce(null)
                    }
                }

                else -> {
                    if (replied.compareAndSet(false, true)) {
                        result.notImplemented()
                    }
                }
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

    override fun onProvideAssistContent(outContent: AssistContent) {
        super.onProvideAssistContent(outContent)
        val url = latestShareUrl
        if (!url.isNullOrEmpty()) {
            try {
                outContent.webUri = Uri.parse(url)
            } catch (_: Exception) {}
        }
    }

    override fun onDestroy() {
        videoExecutor.execute {
            videoEncoder?.release()
            videoEncoder = null
        }
        videoExecutor.shutdown()
        super.onDestroy()
    }
}
