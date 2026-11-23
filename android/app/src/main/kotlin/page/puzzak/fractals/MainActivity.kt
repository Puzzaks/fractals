package page.puzzak.fractals

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.view.RoundedCorner
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import com.google.android.gms.games.PlayGames
import com.google.android.gms.games.PlayGamesSdk
import com.google.android.gms.games.leaderboard.LeaderboardVariant
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private var displayChannel: MethodChannel? = null
    private var playGamesChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            PlayGamesSdk.initialize(this)
        } catch (_: Exception) {
            // Play Services unavailable or failed to initialize; ignore safely.
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
                                } catch (_: Exception) {
                                    false
                                }
                                replyOnce(authenticated)
                            }
                    } catch (_: Exception) {
                        replyOnce(false)
                    }
                }

                "signIn" -> {
                    try {
                        PlayGames.getGamesSignInClient(this).signIn()
                            .addOnCompleteListener { task ->
                                val authenticated = try {
                                    task.isSuccessful && (task.result?.isAuthenticated == true)
                                } catch (_: Exception) {
                                    false
                                }
                                replyOnce(authenticated)
                            }
                    } catch (_: Exception) {
                        replyOnce(false)
                    }
                }

                "submitScore" -> {
                    val leaderboardId = call.argument<String>("leaderboardId")
                    val score = call.argument<Number>("score")?.toLong()
                    if (leaderboardId.isNullOrEmpty() || score == null) {
                        replyOnce(false)
                        return@setMethodCallHandler
                    }
                    try {
                        PlayGames.getLeaderboardsClient(this).submitScore(leaderboardId, score)
                        replyOnce(true)
                    } catch (_: Exception) {
                        replyOnce(false)
                    }
                }

                "loadPlayerScore" -> {
                    val leaderboardId = call.argument<String>("leaderboardId")
                    if (leaderboardId.isNullOrEmpty()) {
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
                                        null
                                    }
                                } catch (_: Exception) {
                                    null
                                }
                                replyOnce(scoreData)
                            }
                    } catch (_: Exception) {
                        replyOnce(null)
                    }
                }

                "unlockAchievement" -> {
                    val achievementId = call.argument<String>("achievementId")
                    if (achievementId.isNullOrEmpty()) {
                        replyOnce(false)
                        return@setMethodCallHandler
                    }
                    try {
                        PlayGames.getAchievementsClient(this).unlock(achievementId)
                        replyOnce(true)
                    } catch (_: Exception) {
                        replyOnce(false)
                    }
                }

                "setAchievementSteps" -> {
                    val achievementId = call.argument<String>("achievementId")
                    val steps = call.argument<Number>("steps")?.toInt()
                    if (achievementId.isNullOrEmpty() || steps == null) {
                        replyOnce(false)
                        return@setMethodCallHandler
                    }
                    try {
                        if (steps > 0) {
                            PlayGames.getAchievementsClient(this).setSteps(achievementId, steps)
                        }
                        replyOnce(true)
                    } catch (_: Exception) {
                        replyOnce(false)
                    }
                }

                "showAllLeaderboards" -> {
                    try {
                        PlayGames.getLeaderboardsClient(this).allLeaderboardsIntent
                            .addOnSuccessListener { intent ->
                                try {
                                    @Suppress("DEPRECATION")
                                    startActivityForResult(intent, 9001)
                                    replyOnce(true)
                                } catch (_: Exception) {
                                    replyOnce(false)
                                }
                            }
                            .addOnFailureListener {
                                replyOnce(false)
                            }
                            .addOnCanceledListener {
                                replyOnce(false)
                            }
                    } catch (_: Exception) {
                        replyOnce(false)
                    }
                }

                "showLeaderboard" -> {
                    val leaderboardId = call.argument<String>("leaderboardId")
                    if (leaderboardId.isNullOrEmpty()) {
                        replyOnce(false)
                        return@setMethodCallHandler
                    }
                    try {
                        PlayGames.getLeaderboardsClient(this).getLeaderboardIntent(leaderboardId)
                            .addOnSuccessListener { intent ->
                                try {
                                    @Suppress("DEPRECATION")
                                    startActivityForResult(intent, 9002)
                                    replyOnce(true)
                                } catch (_: Exception) {
                                    replyOnce(false)
                                }
                            }
                            .addOnFailureListener {
                                replyOnce(false)
                            }
                            .addOnCanceledListener {
                                replyOnce(false)
                            }
                    } catch (_: Exception) {
                        replyOnce(false)
                    }
                }

                "showAchievements" -> {
                    try {
                        PlayGames.getAchievementsClient(this).achievementsIntent
                            .addOnSuccessListener { intent ->
                                try {
                                    @Suppress("DEPRECATION")
                                    startActivityForResult(intent, 9003)
                                    replyOnce(true)
                                } catch (_: Exception) {
                                    replyOnce(false)
                                }
                            }
                            .addOnFailureListener {
                                replyOnce(false)
                            }
                            .addOnCanceledListener {
                                replyOnce(false)
                            }
                    } catch (_: Exception) {
                        replyOnce(false)
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
}
