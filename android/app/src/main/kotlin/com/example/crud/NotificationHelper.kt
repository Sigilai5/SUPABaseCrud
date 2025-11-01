package com.example.crud

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

object NotificationHelper {
    private const val CHANNEL_ID = "mpesa_transactions"
    private const val CHANNEL_NAME = "MPESA Transactions"
    private const val CHANNEL_DESCRIPTION = "Notifications for detected MPESA transactions"

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
        createNotificationChannel(context)

        val notificationId = transactionCode.hashCode()

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

        // Build notification
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle("📱 MPESA Transaction Detected")
            .setContentText("$title - KES ${"%.2f".format(amount)}")
            .setStyle(NotificationCompat.BigTextStyle()
                .bigText("$title\nAmount: KES ${"%.2f".format(amount)}\nFrom: $sender\nCode: $transactionCode"))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
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

        // Show notification
        try {
            NotificationManagerCompat.from(context).notify(notificationId, notification)
        } catch (e: SecurityException) {
            android.util.Log.e("NotificationHelper", "Permission denied for notification", e)
        }
    }

    fun cancelNotification(context: Context, notificationId: Int) {
        NotificationManagerCompat.from(context).cancel(notificationId)
    }
}