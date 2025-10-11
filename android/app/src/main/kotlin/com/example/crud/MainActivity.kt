package com.example.crud

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.crud/mpesa"
    private val TAG = "MainActivity"
    private val PREFS_NAME = "MpesaPrefs"
    private val PENDING_TRANSACTIONS = "pending_transactions"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Cache FlutterEngine for access in OverlayService
        FlutterEngineCache.getInstance().put("crud_engine", flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasOverlayPermission" -> {
                    result.success(Settings.canDrawOverlays(this))
                }
                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        result.success(true)
                    } else {
                        result.success(true)
                    }
                }
                "showTransactionOverlay" -> {
                    val title = call.argument<String>("title") ?: "Unknown"
                    val amount = call.argument<Double>("amount") ?: 0.0
                    val type = call.argument<String>("type") ?: "expense"
                    val sender = call.argument<String>("sender") ?: "Unknown"
                    val rawMessage = call.argument<String>("rawMessage") ?: ""
                    val transactionCode = call.argument<String>("transactionCode") ?: ""

                    @Suppress("UNCHECKED_CAST")
                    val categories = call.argument<List<Map<String, Any>>>("categories") ?: emptyList()

                    Log.d(TAG, "showTransactionOverlay called")
                    Log.d(TAG, "Received ${categories.size} categories from Flutter")

                    val intent = Intent(this, OverlayService::class.java).apply {
                        putExtra("title", title)
                        putExtra("amount", amount)
                        putExtra("type", type)
                        putExtra("sender", sender)
                        putExtra("rawMessage", rawMessage)
                        putExtra("transactionCode", transactionCode)
                        putExtra("categories", ArrayList(categories.map { HashMap(it) }))
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }

                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "getPendingTransactions" -> {
                    val transactions = getPendingTransactions()
                    Log.d(TAG, "Returning ${transactions.size} pending transactions to Flutter")
                    result.success(transactions)
                }
                "clearPendingTransactions" -> {
                    clearPendingTransactions()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        Log.d(TAG, "Flutter engine configured and cached")
    }

    private fun getPendingTransactions(): List<Map<String, Any>> {
        val transactions = mutableListOf<Map<String, Any>>()

        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val jsonString = prefs.getString(PENDING_TRANSACTIONS, "[]") ?: "[]"

            Log.d(TAG, "Retrieved pending transactions JSON: $jsonString")

            val jsonArray = JSONArray(jsonString)

            for (i in 0 until jsonArray.length()) {
                val jsonObject = jsonArray.getJSONObject(i)
                val transaction = mapOf(
                    "title" to jsonObject.getString("title"),
                    "amount" to jsonObject.getDouble("amount"),
                    "type" to jsonObject.getString("type"),
                    "transactionCode" to jsonObject.getString("transactionCode"),
                    "timestamp" to jsonObject.getLong("timestamp")
                )
                transactions.add(transaction)
            }

            Log.d(TAG, "Parsed ${transactions.size} pending transactions")

        } catch (e: Exception) {
            Log.e(TAG, "Error getting pending transactions: ${e.message}", e)
        }

        return transactions
    }

    private fun clearPendingTransactions() {
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            prefs.edit().putString(PENDING_TRANSACTIONS, "[]").apply()
            Log.d(TAG, "Cleared all pending transactions")
        } catch (e: Exception) {
            Log.e(TAG, "Error clearing pending transactions: ${e.message}")
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        FlutterEngineCache.getInstance().remove("crud_engine")
        Log.d(TAG, "Flutter engine removed from cache")
    }
}