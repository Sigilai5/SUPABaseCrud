package com.example.crud

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class OverlayService : Service() {
    private lateinit var windowManager: WindowManager
    private lateinit var overlayView: View
    private val CHANNEL = "com.example.crud/mpesa"
    private val TAG = "OverlayService"
    private val PREFS_NAME = "MpesaPrefs"
    private val PENDING_TRANSACTIONS = "pending_transactions"
    private var transactionCode: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(1, createNotification())

        val inflater = getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
        overlayView = inflater.inflate(R.layout.transaction_overlay, null)

        setupWindowManager()
        setupClickListeners()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "transaction_channel",
                "Transaction Detection",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun createNotification(): Notification {
        return NotificationCompat.Builder(this, "transaction_channel")
            .setContentTitle("Processing Transaction")
            .setContentText("Detected MPESA transaction")
            .setSmallIcon(R.drawable.launch_background)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun setupWindowManager() {
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER or Gravity.CENTER_HORIZONTAL
        }

        windowManager.addView(overlayView, params)
    }

    private fun setupClickListeners() {
        overlayView.findViewById<Button>(R.id.btnSave).setOnClickListener {
            Log.d(TAG, "Save button clicked")

            // Try to send to Flutter if available
            val engine = FlutterEngineCache.getInstance().get("crud_engine")
            if (engine != null) {
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("onTransactionConfirmed", true)
                Log.d(TAG, "Transaction confirmed sent to Flutter")
                Toast.makeText(this, "Transaction saved successfully!", Toast.LENGTH_SHORT).show()
            } else {
                // Save locally if Flutter not available
                Log.d(TAG, "Flutter not available - transaction will be processed when app opens")
                Toast.makeText(this, "Transaction saved! Open app to view.", Toast.LENGTH_SHORT).show()
                // The transaction is already saved in SharedPreferences by SmsReceiver
            }

            stopSelf()
        }

        overlayView.findViewById<Button>(R.id.btnDismiss).setOnClickListener {
            Log.d(TAG, "Dismiss button clicked")

            // Remove this specific transaction from SharedPreferences
            removeFromPendingTransactions()

            val engine = FlutterEngineCache.getInstance().get("crud_engine")
            if (engine != null) {
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("onTransactionConfirmed", false)
            }

            Toast.makeText(this, "Transaction dismissed", Toast.LENGTH_SHORT).show()
            stopSelf()
        }
    }

    private fun removeFromPendingTransactions() {
        try {
            if (transactionCode != null) {
                val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val existingJson = prefs.getString(PENDING_TRANSACTIONS, "[]") ?: "[]"

                // Remove the transaction with this code
                val updatedJson = existingJson.replace(
                    Regex("\\{[^}]*\"transactionCode\":\\s*\"$transactionCode\"[^}]*\\},?"),
                    ""
                ).replace(",]", "]").replace("[,", "[").replace(",,", ",")

                prefs.edit().putString(PENDING_TRANSACTIONS, updatedJson).apply()
                Log.d(TAG, "Removed transaction $transactionCode from pending list")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error removing pending transaction: ${e.message}")
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.let {
            val title = it.getStringExtra("title") ?: "Unknown"
            val amount = it.getDoubleExtra("amount", 0.0)
            val type = it.getStringExtra("type") ?: "expense"
            val sender = it.getStringExtra("sender") ?: "MPESA"
            transactionCode = it.getStringExtra("transactionCode")

            overlayView.findViewById<TextView>(R.id.tvTitle).text = title
            overlayView.findViewById<TextView>(R.id.tvAmount).text =
                "KES ${String.format("%.2f", amount)}"
            overlayView.findViewById<TextView>(R.id.tvType).text =
                type.uppercase()
            overlayView.findViewById<TextView>(R.id.tvSender).text = "From: $sender"

            // Update type badge color
            val tvType = overlayView.findViewById<TextView>(R.id.tvType)
            val tvAmount = overlayView.findViewById<TextView>(R.id.tvAmount)
            if (type == "income") {
                tvType.setBackgroundColor(android.graphics.Color.parseColor("#E8F5E9"))
                tvType.setTextColor(android.graphics.Color.parseColor("#4CAF50"))
                tvAmount.setTextColor(android.graphics.Color.parseColor("#4CAF50"))
            } else {
                tvType.setBackgroundColor(android.graphics.Color.parseColor("#FFEBEE"))
                tvType.setTextColor(android.graphics.Color.parseColor("#F44336"))
                tvAmount.setTextColor(android.graphics.Color.parseColor("#F44336"))
            }

            Log.d(TAG, "Overlay displayed: $title - $amount ($type)")
        }
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        if (::overlayView.isInitialized && ::windowManager.isInitialized) {
            windowManager.removeView(overlayView)
        }
    }
}