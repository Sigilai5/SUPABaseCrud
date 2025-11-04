package com.example.crud

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.ComponentName
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
import android.widget.*
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.text.NumberFormat
import java.util.Locale

class OverlayService : Service() {
    private lateinit var windowManager: WindowManager
    private lateinit var overlayView: View
    private val CHANNEL = "com.example.crud/mpesa"
    private val TAG = "OverlayService"
    private val PREFS_NAME = "MpesaPrefs"
    private val PENDING_TRANSACTIONS = "pending_transactions"

    // Store transaction data
    private var transactionCode: String? = null
    private var transactionTitle: String = ""
    private var transactionAmount: Double = 0.0
    private var transactionType: String = "expense"
    private var transactionSender: String = ""
    private var transactionRawMessage: String = ""

    // UI Elements
    private lateinit var tvTitle: TextView
    private lateinit var tvAmount: TextView
    private lateinit var tvType: TextView
    private lateinit var btnAdd: Button
    private lateinit var btnDismiss: Button
    private lateinit var closeButton: ImageButton

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "=== OverlayService Created ===")

        createNotificationChannel()
        startForeground(1, createNotification())

        val inflater = getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
        overlayView = inflater.inflate(R.layout.transaction_overlay, null)

        // Initialize UI elements
        tvTitle = overlayView.findViewById(R.id.tvTitle)
        tvAmount = overlayView.findViewById(R.id.tvAmount)
        tvType = overlayView.findViewById(R.id.tvType)
        btnAdd = overlayView.findViewById(R.id.btnAdd)
        btnDismiss = overlayView.findViewById(R.id.btnDismiss)
        closeButton = overlayView.findViewById(R.id.closeButton)

        setupWindowManager()
        setupClickListeners()

        Log.d(TAG, "✓ OverlayService initialized successfully")
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
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            y = 100 // Offset from top
        }

        windowManager.addView(overlayView, params)
    }

    private fun setupClickListeners() {
        // Add button - saves to pending and launches app
        btnAdd.setOnClickListener {
            Log.d(TAG, "=== Add button clicked ===")

            // Save transaction data for the app to process
            savePendingTransaction()

            // Launch the app to the transaction form
            launchAppWithTransaction()

            stopSelf()
        }

        // Dismiss button
        btnDismiss.setOnClickListener {
            Log.d(TAG, "=== Dismiss button clicked ===")

            // Notify Flutter if available
            val engine = FlutterEngineCache.getInstance().get("crud_engine")
            if (engine != null) {
                val dismissData = mapOf(
                    "confirmed" to false,
                    "transactionCode" to (transactionCode ?: "UNKNOWN")
                )

                try {
                    MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                        .invokeMethod("onTransactionDismissed", dismissData)
                } catch (e: Exception) {
                    Log.e(TAG, "Error sending dismiss to Flutter: ${e.message}")
                }
            }

            stopSelf()
        }

        // Close button (X)
        closeButton.setOnClickListener {
            Log.d(TAG, "Close button clicked")
            stopSelf()
        }
    }

    private fun savePendingTransaction() {
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            val jsonString = """
                {
                    "title": "${transactionTitle.replace("\"", "\\\"")}",
                    "amount": $transactionAmount,
                    "type": "$transactionType",
                    "transactionCode": "$transactionCode",
                    "sender": "$transactionSender",
                    "rawMessage": "${transactionRawMessage.replace("\"", "\\\"")}",
                    "timestamp": ${System.currentTimeMillis()}
                }
            """.trimIndent()

            val existingJson = prefs.getString(PENDING_TRANSACTIONS, "[]")
            val updatedJson = if (existingJson == "[]") {
                "[$jsonString]"
            } else {
                existingJson?.dropLast(1) + ",$jsonString]"
            }

            prefs.edit().putString(PENDING_TRANSACTIONS, updatedJson).apply()
            Log.d(TAG, "✓ Transaction saved to pending")

        } catch (e: Exception) {
            Log.e(TAG, "Error saving pending transaction: ${e.message}", e)
        }
    }

    private fun launchAppWithTransaction() {
        try {
            // Create intent to launch MainActivity
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                action = "com.example.crud.ADD_TRANSACTION"

                // Pass transaction data
                putExtra("title", transactionTitle)
                putExtra("amount", transactionAmount)
                putExtra("type", transactionType)
                putExtra("transactionCode", transactionCode)
                putExtra("sender", transactionSender)
                putExtra("rawMessage", transactionRawMessage)
            }

            startActivity(intent)
            Log.d(TAG, "✓ Launched app with transaction data")

        } catch (e: Exception) {
            Log.e(TAG, "Error launching app: ${e.message}", e)

            // Fallback: Try to just launch the app without extras
            try {
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                if (launchIntent != null) {
                    launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(launchIntent)
                    Log.d(TAG, "✓ Launched app (fallback)")
                }
            } catch (fallbackError: Exception) {
                Log.e(TAG, "Fallback launch failed: ${fallbackError.message}")
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.let {
            transactionTitle = it.getStringExtra("title") ?: "Unknown"
            transactionAmount = it.getDoubleExtra("amount", 0.0)
            transactionType = it.getStringExtra("type") ?: "expense"
            transactionSender = it.getStringExtra("sender") ?: "MPESA"
            transactionRawMessage = it.getStringExtra("rawMessage") ?: ""
            transactionCode = it.getStringExtra("transactionCode")

            Log.d(TAG, "=== Overlay Service Started ===")
            Log.d(TAG, "Title: $transactionTitle")
            Log.d(TAG, "Amount: $transactionAmount")
            Log.d(TAG, "Type: $transactionType")
            Log.d(TAG, "Transaction Code: $transactionCode")

            // Update UI
            tvTitle.text = transactionTitle

            // Format amount with proper currency formatting
            val formattedAmount = NumberFormat.getCurrencyInstance(Locale("en", "KE"))
                .format(transactionAmount)
                .replace("KES", "KES ")
            tvAmount.text = formattedAmount

            // Set type badge
            if (transactionType == "income") {
                tvType.text = "INCOME"
                tvType.setBackgroundColor(android.graphics.Color.parseColor("#4CAF50"))
                tvAmount.setTextColor(android.graphics.Color.parseColor("#4CAF50"))
            } else {
                tvType.text = "EXPENSE"
                tvType.setBackgroundColor(android.graphics.Color.parseColor("#F44336"))
                tvAmount.setTextColor(android.graphics.Color.parseColor("#F44336"))
            }

            Log.d(TAG, "✓ Overlay UI setup complete")
        }

        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        if (::overlayView.isInitialized && ::windowManager.isInitialized) {
            try {
                windowManager.removeView(overlayView)
                Log.d(TAG, "Overlay removed")
            } catch (e: Exception) {
                Log.e(TAG, "Error removing overlay: ${e.message}")
            }
        }
    }
}