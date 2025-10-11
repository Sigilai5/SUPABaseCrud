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
import android.widget.EditText
import android.widget.TextView
import android.widget.Toast
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.*

class OverlayService : Service() {
    private lateinit var windowManager: WindowManager
    private lateinit var overlayView: View
    private val CHANNEL = "com.example.crud/mpesa"
    private val TAG = "OverlayService"
    private val PREFS_NAME = "MpesaPrefs"
    private val PENDING_TRANSACTIONS = "pending_transactions"
    private var transactionCode: String? = null

    // Store original transaction data
    private var originalAmount: Double = 0.0
    private var originalType: String = "expense"

    // UI Elements
    private lateinit var etTitle: EditText
    private lateinit var etNotes: EditText
    private lateinit var tvAmount: TextView
    private lateinit var tvType: TextView
    private lateinit var tvSender: TextView
    private lateinit var tvCategory: TextView
    private lateinit var tvDate: TextView
    private lateinit var viewCategoryColor: View

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(1, createNotification())

        val inflater = getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
        overlayView = inflater.inflate(R.layout.transaction_overlay, null)

        // Initialize UI elements
        etTitle = overlayView.findViewById(R.id.etTitle)
        etNotes = overlayView.findViewById(R.id.etNotes)
        tvAmount = overlayView.findViewById(R.id.tvAmount)
        tvType = overlayView.findViewById(R.id.tvType)
        tvSender = overlayView.findViewById(R.id.tvSender)
        tvCategory = overlayView.findViewById(R.id.tvCategory)
        tvDate = overlayView.findViewById(R.id.tvDate)
        viewCategoryColor = overlayView.findViewById(R.id.viewCategoryColor)

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

            // Get user-edited values
            val editedTitle = etTitle.text.toString().trim()
            val editedNotes = etNotes.text.toString().trim()

            // Validate
            if (editedTitle.isEmpty()) {
                Toast.makeText(this, "Please enter a title", Toast.LENGTH_SHORT).show()
                etTitle.requestFocus()
                return@setOnClickListener
            }

            // Try to send to Flutter if available
            val engine = FlutterEngineCache.getInstance().get("crud_engine")
            if (engine != null) {
                // Send the edited data to Flutter as a Map
                val transactionData = mapOf(
                    "confirmed" to true,
                    "title" to editedTitle,
                    "amount" to originalAmount,
                    "type" to originalType,
                    "notes" to if (editedNotes.isNotEmpty()) editedNotes else null,
                    "transactionCode" to transactionCode
                )

                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("onTransactionConfirmed", transactionData)

                Log.d(TAG, "Transaction confirmed with edited data: title='$editedTitle', notes='$editedNotes'")
                Toast.makeText(this, "Transaction saved successfully!", Toast.LENGTH_SHORT).show()
            } else {
                // Save to SharedPreferences with edited data
                Log.d(TAG, "Flutter not available - saving edited transaction to SharedPreferences")
                savePendingTransactionWithEdits(editedTitle, editedNotes)
                Toast.makeText(this, "Transaction saved! Open app to view.", Toast.LENGTH_SHORT).show()
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
                    .invokeMethod("onTransactionConfirmed", mapOf("confirmed" to false))
            }

            Toast.makeText(this, "Transaction dismissed", Toast.LENGTH_SHORT).show()
            stopSelf()
        }
    }

    private fun savePendingTransactionWithEdits(title: String, notes: String) {
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            // Escape quotes in strings for JSON
            val escapedTitle = title.replace("\"", "\\\"").replace("\n", "\\n")
            val escapedNotes = notes.replace("\"", "\\\"").replace("\n", "\\n")

            // Create JSON with edited data
            val jsonString = """
                {
                    "title": "$escapedTitle",
                    "amount": $originalAmount,
                    "type": "$originalType",
                    "transactionCode": "$transactionCode",
                    "notes": "$escapedNotes",
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

            prefs.edit().putString(PENDING_TRANSACTIONS, updatedJson).apply()
            Log.d(TAG, "Transaction with edits saved to SharedPreferences: $jsonString")

        } catch (e: Exception) {
            Log.e(TAG, "Error saving pending transaction with edits: ${e.message}", e)
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
            Log.e(TAG, "Error removing pending transaction: ${e.message}", e)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.let {
            val title = it.getStringExtra("title") ?: "Unknown"
            val amount = it.getDoubleExtra("amount", 0.0)
            val type = it.getStringExtra("type") ?: "expense"
            val sender = it.getStringExtra("sender") ?: "MPESA"
            transactionCode = it.getStringExtra("transactionCode")

            // Store original data
            originalAmount = amount
            originalType = type

            // Populate UI fields
            etTitle.setText(title)
            tvAmount.text = String.format("%.2f", amount)
            tvType.text = type.uppercase()
            tvSender.text = "From: $sender"
            tvCategory.text = "MPESA"

            // Format current date
            val dateFormat = SimpleDateFormat("MMM dd, yyyy", Locale.getDefault())
            tvDate.text = dateFormat.format(Date())

            // Pre-fill notes with transaction code
            etNotes.setText("Auto-detected from MPESA SMS\nCode: $transactionCode")

            // Update type badge and amount color
            if (type == "income") {
                tvType.setBackgroundColor(android.graphics.Color.parseColor("#E8F5E9"))
                tvType.setTextColor(android.graphics.Color.parseColor("#4CAF50"))
                tvAmount.setTextColor(android.graphics.Color.parseColor("#4CAF50"))
                viewCategoryColor.setBackgroundColor(android.graphics.Color.parseColor("#4CAF50"))
            } else {
                tvType.setBackgroundColor(android.graphics.Color.parseColor("#FFEBEE"))
                tvType.setTextColor(android.graphics.Color.parseColor("#F44336"))
                tvAmount.setTextColor(android.graphics.Color.parseColor("#F44336"))
                viewCategoryColor.setBackgroundColor(android.graphics.Color.parseColor("#F44336"))
            }

            Log.d(TAG, "Overlay displayed: $title - $amount ($type) - Code: $transactionCode")
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