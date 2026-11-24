package page.puzzak.fractals

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.util.Log
import kotlin.math.roundToInt

class ExportForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "fractals_export"
        const val COMPLETE_CHANNEL_ID = "fractals_export_complete"
        const val NOTIFICATION_ID = 4201
        const val COMPLETE_NOTIFICATION_ID = 4202

        const val ACTION_START = "page.puzzak.fractals.action.EXPORT_START"
        const val ACTION_UPDATE = "page.puzzak.fractals.action.EXPORT_UPDATE"
        const val ACTION_STOP = "page.puzzak.fractals.action.EXPORT_STOP"

        const val EXTRA_TITLE = "title"
        const val EXTRA_DETAIL = "detail"
        const val EXTRA_PROGRESS = "progress"

        fun showCompleteNotification(
            context: Context,
            title: String,
            detail: String,
            contentUri: String?,
            mimeType: String?,
        ): Boolean {
            return try {
                val manager = context.getSystemService(NotificationManager::class.java) ?: return false
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    if (manager.getNotificationChannel(COMPLETE_CHANNEL_ID) == null) {
                        val channel = NotificationChannel(
                            COMPLETE_CHANNEL_ID,
                            "Completed Exports",
                            NotificationManager.IMPORTANCE_DEFAULT,
                        ).apply {
                            description = "Notifications when image or video exports finish"
                        }
                        manager.createNotificationChannel(channel)
                    }
                }

                val tapIntent = if (!contentUri.isNullOrEmpty()) {
                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = mimeType?.takeIf { it.isNotBlank() } ?: "video/mp4"
                        putExtra(Intent.EXTRA_STREAM, Uri.parse(contentUri))
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    Intent.createChooser(shareIntent, title).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                } else {
                    (context.packageManager.getLaunchIntentForPackage(context.packageName)
                        ?: Intent(context, MainActivity::class.java)).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                }

                val pendingIntent = PendingIntent.getActivity(
                    context,
                    1,
                    tapIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )

                val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Notification.Builder(context, COMPLETE_CHANNEL_ID)
                } else {
                    @Suppress("DEPRECATION")
                    Notification.Builder(context)
                }

                builder
                    .setContentTitle(title)
                    .setSmallIcon(context.applicationInfo.icon)
                    .setAutoCancel(true)
                    .setContentIntent(pendingIntent)

                if (detail.isNotEmpty()) {
                    builder.setContentText(detail)
                }

                manager.notify(COMPLETE_NOTIFICATION_ID, builder.build())
                true
            } catch (e: SecurityException) {
                Log.w("ExportService", "Notification permission denied for completion notification", e)
                false
            } catch (e: Exception) {
                Log.w("ExportService", "Failed to post completion notification", e)
                false
            }
        }
    }

    private var isForegroundStarted = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_STOP) {
            stopServiceCleanly()
            return START_NOT_STICKY
        }

        val title = intent?.getStringExtra(EXTRA_TITLE)?.takeIf { it.isNotBlank() } ?: "Exporting"
        val detail = intent?.getStringExtra(EXTRA_DETAIL) ?: ""
        val progress = intent?.getDoubleExtra(EXTRA_PROGRESS, 0.0) ?: 0.0
        val progressPct = (progress.coerceIn(0.0, 1.0) * 100.0).roundToInt()

        try {
            ensureChannel()
            val notification = buildNotification(title, detail, progressPct)
            if (!isForegroundStarted || action == ACTION_START) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        NOTIFICATION_ID,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                    )
                } else {
                    startForeground(NOTIFICATION_ID, notification)
                }
                isForegroundStarted = true
            } else {
                val manager = getSystemService(NotificationManager::class.java)
                manager?.notify(NOTIFICATION_ID, notification)
            }
        } catch (e: Exception) {
            Log.w("ExportService", "Failed to post export notification", e)
        }

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        isForegroundStarted = false
        super.onDestroy()
    }

    private fun stopServiceCleanly() {
        try {
            if (isForegroundStarted) {
                stopForeground(STOP_FOREGROUND_REMOVE)
                isForegroundStarted = false
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager?.cancel(NOTIFICATION_ID)
        } catch (e: Exception) {
            Log.w("ExportService", "Error stopping foreground notification", e)
        }
        stopSelf()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java) ?: return
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Fractal Exports",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Progress notifications for image and video exports"
                    setShowBadge(false)
                }
                manager.createNotificationChannel(channel)
            }
        }
    }

    private fun buildNotification(title: String, detail: String, progressPct: Int): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = if (launchIntent != null) {
            PendingIntent.getActivity(
                this,
                0,
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        } else {
            null
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }

        builder
            .setContentTitle(title)
            .setSmallIcon(applicationInfo.icon)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setProgress(100, progressPct, false)

        if (detail.isNotEmpty()) {
            builder.setContentText(detail)
        }
        if (pendingIntent != null) {
            builder.setContentIntent(pendingIntent)
        }

        return builder.build()
    }
}
