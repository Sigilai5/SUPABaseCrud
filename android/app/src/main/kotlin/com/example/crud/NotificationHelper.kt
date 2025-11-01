package com.example.crud

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

object NotificationHelper {
    private const val CHANNEL_ID = "mpesa_transactions"
    private const val CHANNEL_NAME = "MPESA Transactions"
    private const val CHANNEL_DESCRIPTION = "Notifications for detected MPESA transactions"
    private const val TAG = "NotificationHelper"

    fun createNotificationChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val importance = NotificationManager.IMPORTANCE_HIGH
            val channel = NotificationChannel(CHANNEL_ID, CHANNEL_NAME, importance).apply {
                description = CHANNEL_DESCRIPTION
                enableVibration(true)
                enableLights(true)
            }

            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
            android.util.Log.d(TAG, "✓ Notification channel created: $CHANNEL_ID")
        }
    }

    fun showTransactionNotification(
        context: Context,
        transactionCode: String,
        title: String,
        amount: Double,
        type: String,
        sender: String,
        rawMessage: String,
        categoryId: String? = null,
        notes: String? = null
    ) {
        android.util.Log.d(TAG, "=== showTransactionNotification called ===")
        android.util.Log.d(TAG, "Transaction Code: $transactionCode")
        android.util.Log.d(TAG, "Title: $title")
        android.util.Log.d(TAG, "Amount: $amount")
        android.util.Log.d(TAG, "Type: $type")

        // CRITICAL: Check notification permission first (Android 13+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val hasPermission = context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED

            android.util.Log.d(TAG, "Android version: ${Build.VERSION.SDK_INT} (Tiramisu = 33)")
            android.util.Log.d(TAG, "POST_NOTIFICATIONS permission granted: $hasPermission")

            if (!hasPermission) {
                android.util.Log.e(TAG, "❌ POST_NOTIFICATIONS permission not granted!")
                android.util.Log.e(TAG, "❌ Cannot show notification - user must enable notification permission in settings")
                android.util.Log.e(TAG, "❌ Settings > Apps > Expense Tracker > Permissions > Notifications")
                return
            }
        } else {
            android.util.Log.d(TAG, "Android version: ${Build.VERSION.SDK_INT} (below Tiramisu, no runtime permission needed)")
        }

        // Create notification channel
        createNotificationChannel(context)

        val notificationId = transactionCode.hashCode()
        android.util.Log.d(TAG, "Notification ID: $notificationId")

        // Intent for "Add" action
        val addIntent = Intent(context, NotificationActionReceiver::class.java).apply {
            action = "com.example.crud.ACTION_ADD_TRANSACTION"
            putExtra("transactionCode", transactionCode)
            putExtra("title", title)
            putExtra("amount", amount)
            putExtra("type", type)
            putExtra("sender", sender)
            putExtra("rawMessage", rawMessage)
            putExtra("categoryId", categoryId)
            putExtra("notes", notes)
        }

        val addPendingIntent = PendingIntent.getBroadcast(
            context,
            notificationId * 2,
            addIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        android.util.Log.d(TAG, "✓ Add PendingIntent created")

        // Intent for "Dismiss" action
        val dismissIntent = Intent(context, NotificationActionReceiver::class.java).apply {
            action = "com.example.crud.ACTION_DISMISS_TRANSACTION"
            putExtra("transactionCode", transactionCode)
            putExtra("notificationId", notificationId)
        }

        val dismissPendingIntent = PendingIntent.getBroadcast(
            context,
            notificationId * 2 + 1,
            dismissIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        android.util.Log.d(TAG, "✓ Dismiss PendingIntent created")

        // Build notification
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("📱 MPESA Transaction Detected")
            .setContentText("$title - KES ${"%.2f".format(amount)}")
            .setStyle(NotificationCompat.BigTextStyle()
                .bigText("$title\nAmount: KES ${"%.2f".format(amount)}\nFrom: $sender\nCode: $transactionCode"))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(
                android.R.drawable.ic_menu_add,
                "Add",
                addPendingIntent
            )
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "Dismiss",
                dismissPendingIntent
            )
            .build()

        android.util.Log.d(TAG, "✓ Notification built")

        // Show notification
        try {
            val notificationManager = NotificationManagerCompat.from(context)

            // Double-check if notifications are enabled at the system level
            val areNotificationsEnabled = notificationManager.areNotificationsEnabled()
            android.util.Log.d(TAG, "System notifications enabled: $areNotificationsEnabled")

            if (!areNotificationsEnabled) {
                android.util.Log.e(TAG, "❌ Notifications are disabled at system level!")
                android.util.Log.e(TAG, "❌ User must enable notifications in: Settings > Apps > Expense Tracker > Notifications")
                return
            }

            // Check if the specific channel is enabled (Android O+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val notificationManager2 = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val channel = notificationManager2.getNotificationChannel(CHANNEL_ID)
                if (channel != null) {
                    val importance = channel.importance
                    android.util.Log.d(TAG, "Channel importance: $importance (NONE=0, MIN=1, LOW=2, DEFAULT=3, HIGH=4, MAX=5)")

                    if (importance == NotificationManager.IMPORTANCE_NONE) {
                        android.util.Log.e(TAG, "❌ Notification channel is disabled!")
                        android.util.Log.e(TAG, "❌ User must enable the channel in: Settings > Apps > Expense Tracker > Notifications > MPESA Transactions")
                        return
                    }
                } else {
                    android.util.Log.w(TAG, "⚠ Notification channel not found, recreating...")
                    createNotificationChannel(context)
                }
            }

            // Actually show the notification
            notificationManager.notify(notificationId, notification)

            android.util.Log.d(TAG, "✅✅✅ NOTIFICATION SHOWN SUCCESSFULLY! ✅✅✅")
            android.util.Log.d(TAG, "✓ Notification ID: $notificationId")
            android.util.Log.d(TAG, "✓ Transaction Code: $transactionCode")
            android.util.Log.d(TAG, "✓ Title: $title")
            android.util.Log.d(TAG, "✓ Amount: KES ${"%.2f".format(amount)}")

        } catch (e: SecurityException) {
            android.util.Log.e(TAG, "❌ SecurityException - Permission denied for notification!", e)
            android.util.Log.e(TAG, "❌ Stack trace:", e)
        } catch (e: Exception) {
            android.util.Log.e(TAG, "❌ Unexpected error showing notification!", e)
            android.util.Log.e(TAG, "❌ Exception type: ${e.javaClass.name}")
            android.util.Log.e(TAG, "❌ Message: ${e.message}")
            android.util.Log.e(TAG, "❌ Stack trace:", e)
        }
    }

    fun cancelNotification(context: Context, notificationId: Int) {
        try {
            NotificationManagerCompat.from(context).cancel(notificationId)
            android.util.Log.d(TAG, "✓ Notification cancelled: $notificationId")
        } catch (e: Exception) {
            android.util.Log.e(TAG, "❌ Error cancelling notification: ${e.message}", e)
        }
    }

    /**
     * Check if notifications are enabled for the app
     * This is a helper method for debugging
     */
    fun areNotificationsEnabled(context: Context): Boolean {
        val notificationManager = NotificationManagerCompat.from(context)
        val enabled = notificationManager.areNotificationsEnabled()
        android.util.Log.d(TAG, "Notifications enabled status: $enabled")
        return enabled
    }

    /**
     * Get detailed notification status for debugging
     */
    fun getNotificationStatus(context: Context): String {
        val status = StringBuilder()
        status.append("=== Notification Status ===\n")

        // Check if notifications are enabled
        val notificationManager = NotificationManagerCompat.from(context)
        val areEnabled = notificationManager.areNotificationsEnabled()
        status.append("Notifications Enabled: $areEnabled\n")

        // Check permission (Android 13+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val hasPermission = context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED
            status.append("POST_NOTIFICATIONS Permission: $hasPermission\n")
        } else {
            status.append("POST_NOTIFICATIONS Permission: Not required (Android < 13)\n")
        }

        // Check channel status (Android O+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val systemNotificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channel = systemNotificationManager.getNotificationChannel(CHANNEL_ID)

            if (channel != null) {
                status.append("Channel Exists: Yes\n")
                status.append("Channel Importance: ${channel.importance}\n")
                status.append("Channel Name: ${channel.name}\n")
            } else {
                status.append("Channel Exists: No\n")
            }
        }

        status.append("Android Version: ${Build.VERSION.SDK_INT}\n")
        status.append("=========================")

        val statusString = status.toString()
        android.util.Log.d(TAG, statusString)
        return statusString
    }

    /**
     * Request notification permission (Android 13+)
     * Note: This can only be called from an Activity, not from a Service or BroadcastReceiver
     */
    fun shouldRequestPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val hasPermission = context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                    PackageManager.PERMISSION_GRANTED

            android.util.Log.d(TAG, "Should request permission: ${!hasPermission}")
            return !hasPermission
        }

        android.util.Log.d(TAG, "Should request permission: false (Android < 13)")
        return false
    }
}