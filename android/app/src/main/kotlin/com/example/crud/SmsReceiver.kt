package com.example.crud

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import android.util.Log
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class SmsReceiver : BroadcastReceiver() {
    private val CHANNEL = "com.example.crud/mpesa"
    private val TAG = "SmsReceiver"
    private val PREFS_NAME = "MpesaPrefs"
    private val PENDING_TRANSACTIONS = "pending_transactions"

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Telephony.Sms.Intents.SMS_RECEIVED_ACTION -> {
                handleSmsReceived(context, intent)
            }
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON" -> {
                Log.d(TAG, "Device booted - receiver ready")
            }
        }
    }

    private fun handleSmsReceived(context: Context, intent: Intent) {
        try {
            val smsMessages = Telephony.Sms.Intents.getMessagesFromIntent(intent)
            val fullMessage = smsMessages.joinToString(separator = "") { it.messageBody }
            val sender = smsMessages.firstOrNull()?.displayOriginatingAddress ?: "Unknown"

            Log.d(TAG, "SMS from $sender: $fullMessage")

            // Check if it's an MPESA message
            if (sender.contains("MPESA", ignoreCase = true) ||
                fullMessage.contains("MPESA", ignoreCase = true)) {

                Log.d(TAG, "MPESA message detected")

                // Try to send to Flutter if engine is available
                val engine = FlutterEngineCache.getInstance().get("crud_engine")
                if (engine != null) {
                    Log.d(TAG, "Flutter engine available - sending to Flutter")
                    val data = mapOf(
                        "sender" to sender,
                        "message" to fullMessage
                    )
                    MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                        .invokeMethod("onMpesaSmsReceived", data)
                } else {
                    // App is not running - handle locally with overlay
                    Log.d(TAG, "Flutter engine not available - showing overlay")
                    handleMpesaDirectly(context, sender, fullMessage)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing SMS: ${e.message}", e)
        }
    }

    private fun handleMpesaDirectly(context: Context, sender: String, message: String) {
        // Parse the MPESA message
        val parsedData = parseMpesaMessage(message)

        if (parsedData != null) {
            Log.d(TAG, "Parsed MPESA data: ${parsedData["title"]}, Amount: ${parsedData["amount"]}")

            // Save to SharedPreferences for when app opens
            savePendingTransaction(context, parsedData)

            // Show overlay
            val overlayIntent = Intent(context, OverlayService::class.java).apply {
                putExtra("title", parsedData["title"] as String)
                putExtra("amount", parsedData["amount"] as Double)
                putExtra("type", parsedData["type"] as String)
                putExtra("transactionCode", parsedData["transactionCode"] as String)
                putExtra("sender", sender)
                putExtra("rawMessage", message)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(overlayIntent)
            } else {
                context.startService(overlayIntent)
            }

            Log.d(TAG, "✓ Overlay shown for transaction: ${parsedData["transactionCode"]}")
        } else {
            Log.e(TAG, "Failed to parse MPESA message")
        }
    }

    private fun parseMpesaMessage(message: String): Map<String, Any>? {
        try {
            val cleanMessage = message.replace(Regex("\\s+"), " ").trim()

            // Extract transaction code
            val codeMatch = Regex("[A-Z0-9]{10}").find(cleanMessage)
            val transactionCode = codeMatch?.value ?: "UNKNOWN"

            // Extract amount
            val amountMatch = Regex("Ksh([\\d,]+\\.?\\d*)").find(cleanMessage)
            if (amountMatch == null) return null

            val amountStr = amountMatch.groupValues[1].replace(",", "")
            val amount = amountStr.toDoubleOrNull() ?: return null

            // Determine transaction type
            var type = "expense"
            var title = "MPESA Transaction"

            when {
                cleanMessage.contains("received", ignoreCase = true) -> {
                    type = "income"
                    val senderMatch = Regex("from\\s+([A-Z\\s]+)\\s+\\d").find(cleanMessage) ?:
                    Regex("from\\s+(\\d+)").find(cleanMessage)
                    val senderName = senderMatch?.groupValues?.get(1)?.trim()
                    title = if (senderName != null) "Received from $senderName" else "Money Received"
                }
                cleanMessage.contains("sent to", ignoreCase = true) -> {
                    type = "expense"
                    val recipientMatch = Regex("to\\s+([A-Za-z\\s]+)\\s+\\d").find(cleanMessage) ?:
                    Regex("to\\s+(\\d+)").find(cleanMessage)
                    val recipientName = recipientMatch?.groupValues?.get(1)?.trim()
                    title = if (recipientName != null) "Sent to $recipientName" else "Money Sent"
                }
                cleanMessage.contains("paid to", ignoreCase = true) -> {
                    type = "expense"
                    val merchantMatch = Regex("to\\s+([A-Z\\s]+)\\.").find(cleanMessage)
                    val merchantName = merchantMatch?.groupValues?.get(1)?.trim()
                    title = if (merchantName != null) "Paid to $merchantName" else "Payment"
                }
                cleanMessage.contains("withdrawn", ignoreCase = true) -> {
                    type = "expense"
                    title = "Cash Withdrawal"
                }
                cleanMessage.contains("bought", ignoreCase = true) -> {
                    type = "expense"
                    title = if (cleanMessage.contains("airtime")) "Airtime Purchase" else "Purchase"
                }
            }

            return mapOf(
                "title" to title,
                "amount" to amount,
                "type" to type,
                "transactionCode" to transactionCode
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing MPESA message: ${e.message}")
            return null
        }
    }

    private fun savePendingTransaction(context: Context, data: Map<String, Any>) {
        try {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val editor = prefs.edit()

            // Save as JSON string
            val jsonString = """
                {
                    "title": "${data["title"]}",
                    "amount": ${data["amount"]},
                    "type": "${data["type"]}",
                    "transactionCode": "${data["transactionCode"]}",
                    "timestamp": ${System.currentTimeMillis()}
                }
            """.trimIndent()

            // Get existing pending transactions
            val existingJson = prefs.getString(PENDING_TRANSACTIONS, "[]")
            val updatedJson = if (existingJson == "[]") {
                "[$jsonString]"
            } else {
                existingJson?.dropLast(1) + ",$jsonString]"
            }

            editor.putString(PENDING_TRANSACTIONS, updatedJson)
            editor.apply()

            Log.d(TAG, "Transaction saved to SharedPreferences")

        } catch (e: Exception) {
            Log.e(TAG, "Error saving pending transaction: ${e.message}")
        }
    }
}