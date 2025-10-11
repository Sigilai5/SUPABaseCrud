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
import android.widget.*
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
    private var selectedCategoryId: String? = null

    // UI Elements
    private lateinit var etTitle: EditText
    private lateinit var etNotes: EditText
    private lateinit var tvAmount: TextView
    private lateinit var tvType: TextView
    private lateinit var tvSender: TextView
    private lateinit var spinnerCategory: Spinner
    private lateinit var tvDate: TextView

    // Categories received from Flutter
    private var categories = mutableListOf<Category>()

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
        spinnerCategory = overlayView.findViewById(R.id.spinnerCategory)
        tvDate = overlayView.findViewById(R.id.tvDate)

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

    private fun setupCategorySpinner(categoriesList: List<Map<String, Any>>) {
        Log.d(TAG, "Setting up spinner with ${categoriesList.size} categories")

        categories.clear()

        if (categoriesList.isEmpty()) {
            // Add default MPESA category if no categories provided
            Log.w(TAG, "No categories received, using default MPESA category")
            categories.add(Category("mpesa", "MPESA", "both", "#4CAF50", "payments"))
        } else {
            for (catMap in categoriesList) {
                try {
                    val category = Category(
                        id = catMap["id"] as? String ?: "unknown",
                        name = catMap["name"] as? String ?: "Unknown",
                        type = catMap["type"] as? String ?: "both",
                        color = catMap["color"] as? String ?: "#4CAF50",
                        icon = catMap["icon"] as? String ?: "category"
                    )
                    categories.add(category)
                    Log.d(TAG, "Added category: ${category.name}")
                } catch (e: Exception) {
                    Log.e(TAG, "Error parsing category: ${e.message}")
                }
            }
        }

        val adapter = CategorySpinnerAdapter(this, categories)
        spinnerCategory.adapter = adapter

        // Find and select MPESA category by default
        val mpesaIndex = categories.indexOfFirst { it.name.equals("MPESA", ignoreCase = true) }
        if (mpesaIndex >= 0) {
            spinnerCategory.setSelection(mpesaIndex)
            selectedCategoryId = categories[mpesaIndex].id
            Log.d(TAG, "Selected MPESA category at index $mpesaIndex")
        } else {
            // Select first category as fallback
            selectedCategoryId = categories.firstOrNull()?.id
            Log.d(TAG, "MPESA not found, selected first category: $selectedCategoryId")
        }

        spinnerCategory.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                selectedCategoryId = categories[position].id
                Log.d(TAG, "User selected category: ${categories[position].name} ($selectedCategoryId)")
            }

            override fun onNothingSelected(parent: AdapterView<*>?) {
                Log.d(TAG, "No category selected")
            }
        }
    }

    private fun setupClickListeners() {
        overlayView.findViewById<Button>(R.id.btnSave).setOnClickListener {
            Log.d(TAG, "=== Save button clicked ===")

            val editedTitle = etTitle.text.toString().trim()
            val editedNotes = etNotes.text.toString().trim()

            Log.d(TAG, "Title: $editedTitle")
            Log.d(TAG, "Notes: $editedNotes")
            Log.d(TAG, "Amount: $originalAmount")
            Log.d(TAG, "Type: $originalType")
            Log.d(TAG, "Selected Category ID: $selectedCategoryId")

            if (editedTitle.isEmpty()) {
                Toast.makeText(this, "Please enter a title", Toast.LENGTH_SHORT).show()
                etTitle.requestFocus()
                return@setOnClickListener
            }

            if (selectedCategoryId == null) {
                Toast.makeText(this, "Please select a category", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }

            val engine = FlutterEngineCache.getInstance().get("crud_engine")
            Log.d(TAG, "Flutter engine available: ${engine != null}")

            if (engine != null) {
                val transactionData = mapOf(
                    "confirmed" to true,
                    "title" to editedTitle,
                    "amount" to originalAmount,
                    "type" to originalType,
                    "categoryId" to selectedCategoryId!!,
                    "notes" to if (editedNotes.isNotEmpty()) editedNotes else null,
                    "transactionCode" to transactionCode
                )

                Log.d(TAG, "Sending transaction data to Flutter: $transactionData")

                try {
                    MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                        .invokeMethod("onTransactionConfirmed", transactionData)

                    Log.d(TAG, "Transaction confirmed successfully")
                    Toast.makeText(this, "Transaction saved successfully!", Toast.LENGTH_SHORT).show()
                } catch (e: Exception) {
                    Log.e(TAG, "Error sending to Flutter: ${e.message}", e)
                    Toast.makeText(this, "Error saving transaction", Toast.LENGTH_SHORT).show()
                }
            } else {
                Log.d(TAG, "Flutter not available - saving to SharedPreferences")
                savePendingTransactionWithEdits(editedTitle, editedNotes, selectedCategoryId!!)
                Toast.makeText(this, "Transaction saved! Open app to view.", Toast.LENGTH_SHORT).show()
            }

            stopSelf()
        }

        overlayView.findViewById<Button>(R.id.btnDismiss).setOnClickListener {
            Log.d(TAG, "Dismiss button clicked")
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

    private fun savePendingTransactionWithEdits(title: String, notes: String, categoryId: String) {
        try {
            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

            val escapedTitle = title.replace("\"", "\\\"").replace("\n", "\\n")
            val escapedNotes = notes.replace("\"", "\\\"").replace("\n", "\\n")

            val jsonString = """
                {
                    "title": "$escapedTitle",
                    "amount": $originalAmount,
                    "type": "$originalType",
                    "categoryId": "$categoryId",
                    "transactionCode": "$transactionCode",
                    "notes": "$escapedNotes",
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
            Log.d(TAG, "Transaction with edits saved to SharedPreferences")

        } catch (e: Exception) {
            Log.e(TAG, "Error saving pending transaction with edits: ${e.message}", e)
        }
    }

    private fun removeFromPendingTransactions() {
        try {
            if (transactionCode != null) {
                val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val existingJson = prefs.getString(PENDING_TRANSACTIONS, "[]") ?: "[]"

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

            Log.d(TAG, "=== Overlay Service Started ===")
            Log.d(TAG, "Title: $title")
            Log.d(TAG, "Amount: $amount")
            Log.d(TAG, "Type: $type")

            // Store original data
            originalAmount = amount
            originalType = type

            // Get categories from intent
            val categoriesData = it.getSerializableExtra("categories") as? ArrayList<HashMap<String, Any>>
            Log.d(TAG, "Received ${categoriesData?.size ?: 0} categories from Flutter")

            if (categoriesData != null) {
                setupCategorySpinner(categoriesData)
            } else {
                Log.w(TAG, "No categories data in intent, using default")
                setupCategorySpinner(emptyList())
            }

            // Populate UI fields
            etTitle.setText(title)
            tvAmount.text = String.format("%.2f", amount)
            tvType.text = type.uppercase()
            tvSender.text = "From: $sender"

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
            } else {
                tvType.setBackgroundColor(android.graphics.Color.parseColor("#FFEBEE"))
                tvType.setTextColor(android.graphics.Color.parseColor("#F44336"))
                tvAmount.setTextColor(android.graphics.Color.parseColor("#F44336"))
            }

            Log.d(TAG, "Overlay setup complete")
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

// Custom Spinner Adapter
class CategorySpinnerAdapter(
    context: Context,
    private val categories: List<Category>
) : ArrayAdapter<Category>(context, android.R.layout.simple_spinner_item, categories) {

    init {
        setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
    }

    override fun getView(position: Int, convertView: View?, parent: android.view.ViewGroup): View {
        val view = super.getView(position, convertView, parent)
        val textView = view.findViewById<TextView>(android.R.id.text1)
        val category = categories[position]

        textView.text = category.name
        textView.textSize = 16f
        try {
            val color = android.graphics.Color.parseColor(category.color)
            textView.setTextColor(color)
        } catch (e: Exception) {
            // Use default color if parsing fails
            textView.setTextColor(android.graphics.Color.BLACK)
        }

        return view
    }

    override fun getDropDownView(position: Int, convertView: View?, parent: android.view.ViewGroup): View {
        val view = super.getDropDownView(position, convertView, parent)
        val textView = view.findViewById<TextView>(android.R.id.text1)
        val category = categories[position]

        textView.text = category.name
        textView.setPadding(24, 24, 24, 24)
        textView.textSize = 16f

        try {
            val color = android.graphics.Color.parseColor(category.color)
            textView.setTextColor(color)
        } catch (e: Exception) {
            // Use default color if parsing fails
            textView.setTextColor(android.graphics.Color.BLACK)
        }

        return view
    }
}