package com.example.crud

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class NotificationActionReceiver : BroadcastReceiver() {
    private val TAG = "NotificationAction"
    private val CHANNEL = "com.example.crud/mpesa"

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            "com.example.crud.ACTION_ADD_TRANSACTION" -> {
                handleAddTransaction(context, intent)
            }
            "com.example.crud.ACTION_DISMISS_TRANSACTION" -> {
                handleDismissTransaction(context, intent)
            }
        }
    }

    private fun handleAddTransaction(context: Context, intent: Intent) {
        Log.d(TAG, "=== Add Transaction Clicked ===")

        val transactionCode = intent.getStringExtra("transactionCode") ?: ""
        val title = intent.getStringExtra("title") ?: ""
        val amount = intent.getDoubleExtra("amount", 0.0)
        val type = intent.getStringExtra("type") ?: "expense"
        val sender = intent.getStringExtra("sender") ?: ""
        val rawMessage = intent.getStringExtra("rawMessage") ?: ""
        val categoryId = intent.getStringExtra("categoryId")
        val notes = intent.getStringExtra("notes")

        Log.d(TAG, "Transaction Code: $transactionCode")
        Log.d(TAG, "Title: $title")
        Log.d(TAG, "Amount: $amount")

        // Cancel the notification
        val notificationId = transactionCode.hashCode()
        NotificationHelper.cancelNotification(context, notificationId)

        // Try to send to Flutter
        val engine = FlutterEngineCache.getInstance().get("crud_engine")
        if (engine != null) {
            Log.d(TAG, "Flutter engine available - sending to Flutter")

            val transactionData = mapOf(
                "confirmed" to true,
                "title" to title,
                "amount" to amount,
                "type" to type,
                "categoryId" to categoryId,
                "notes" to notes,
                "transactionCode" to transactionCode,
                "sender" to sender,
                "rawMessage" to rawMessage
            )

            try {
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("onTransactionConfirmed", transactionData)

                Log.d(TAG, "✓ Transaction sent to Flutter successfully")
            } catch (e: Exception) {
                Log.e(TAG, "✗ Error sending to Flutter: ${e.message}", e)
                // Fall back to SharedPreferences
                savePendingTransaction(context, intent)
            }
        } else {
            Log.d(TAG, "Flutter engine not available - saving to SharedPreferences")
            savePendingTransaction(context, intent)

            // Try to launch the app
            tryLaunchApp(context)
        }
    }

    private fun handleDismissTransaction(context: Context, intent: Intent) {
        Log.d(TAG, "=== Dismiss Transaction Clicked ===")

        val transactionCode = intent.getStringExtra("transactionCode") ?: ""
        val notificationId = intent.getIntExtra("notificationId", transactionCode.hashCode())

        Log.d(TAG, "Dismissing transaction: $transactionCode")

        // Cancel the notification
        NotificationHelper.cancelNotification(context, notificationId)

        // Optionally notify Flutter
        val engine = FlutterEngineCache.getInstance().get("crud_engine")
        if (engine != null) {
            try {
                val dismissData = mapOf(
                    "confirmed" to false,
                    "transactionCode" to transactionCode
                )

                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("onTransactionDismissed", dismissData)

                Log.d(TAG, "✓ Dismiss notification sent to Flutter")
            } catch (e: Exception) {
                Log.e(TAG, "Error sending dismiss to Flutter: ${e.message}")
            }
        }

        Log.d(TAG, "Transaction dismissed")
    }

    private fun savePendingTransaction(context: Context, intent: Intent) {
        try {
            val prefs = context.getSharedPreferences("MpesaPrefs", Context.MODE_PRIVATE)

            val transactionCode = intent.getStringExtra("transactionCode") ?: ""
            val title = intent.getStringExtra("title") ?: ""
            val amount = intent.getDoubleExtra("amount", 0.0)
            val type = intent.getStringExtra("type") ?: "expense"
            val categoryId = intent.getStringExtra("categoryId") ?: ""
            val notes = intent.getStringExtra("notes") ?: ""

            val jsonString = """
                {
                    "title": "${title.replace("\"", "\\\"")}",
                    "amount": $amount,
                    "type": "$type",
                    "categoryId": "$categoryId",
                    "transactionCode": "$transactionCode",
                    "notes": "${notes.replace("\"", "\\\"")}",
                    "timestamp": ${System.currentTimeMillis()}
                }
            """.trimIndent()

            val existingJson = prefs.getString("pending_transactions", "[]")
            val updatedJson = if (existingJson == "[]") {
                "[$jsonString]"
            } else {
                existingJson?.dropLast(1) + ",$jsonString]"
            }

            prefs.edit().putString("pending_transactions", updatedJson).apply()
            Log.d(TAG, "✓ Transaction saved to SharedPreferences")
        } catch (e: Exception) {
            Log.e(TAG, "Error saving to SharedPreferences: ${e.message}", e)
        }
    }

    private fun tryLaunchApp(context: Context) {
        try {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(launchIntent)
                Log.d(TAG, "✓ App launch attempted")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error launching app: ${e.message}")
        }
    }
}