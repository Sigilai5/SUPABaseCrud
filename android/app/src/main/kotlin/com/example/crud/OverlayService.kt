package com.example.crud

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.PixelFormat
import android.location.Location
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.WindowManager
import android.widget.*
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
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

    // Location
    private lateinit var fusedLocationClient: FusedLocationProviderClient
    private var currentLatitude: Double? = null
    private var currentLongitude: Double? = null
    private var isCapturingLocation = false
    private var locationCaptureAttempted = false

    // Store original transaction data
    private var originalAmount: Double = 0.0
    private var originalType: String = "expense"
    private var selectedCategoryId: String? = null
    private var originalSender: String = ""
    private var originalRawMessage: String = ""
    private var originalTitle: String = ""

    // UI Elements
    private lateinit var etTitle: EditText
    private lateinit var etNotes: EditText
    private lateinit var tvAmount: TextView
    private lateinit var tvType: TextView
    private lateinit var tvSender: TextView
    private lateinit var spinnerCategory: Spinner
    private lateinit var tvDate: TextView
    private lateinit var tvLocationStatus: TextView

    // Categories received from Flutter
    private var categories = mutableListOf<Category>()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()

        // Initialize location client immediately
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)

        // Start logging early
        Log.d(TAG, "=== OverlayService Created ===")
        Log.d(TAG, "Attempting early location capture...")

        // Try capturing location even before UI setup
        captureLocationInBackground()

        // Now set up notification and overlay
        createNotificationChannel()
        startForeground(1, createNotification())

        val inflater = getSystemService(Context.LAYOUT_INFLATER_SERVICE) as LayoutInflater
        overlayView = inflater.inflate(R.layout.transaction_overlay, null)

        // Initialize UI elements AFTER starting location capture
        etTitle = overlayView.findViewById(R.id.etTitle)
        etNotes = overlayView.findViewById(R.id.etNotes)
        tvAmount = overlayView.findViewById(R.id.tvAmount)
        tvType = overlayView.findViewById(R.id.tvType)
        tvSender = overlayView.findViewById(R.id.tvSender)
        spinnerCategory = overlayView.findViewById(R.id.spinnerCategory)
        tvDate = overlayView.findViewById(R.id.tvDate)
        tvLocationStatus = overlayView.findViewById(R.id.tvLocationStatus)

        setupWindowManager()
        setupClickListeners()

        // Log that setup finished
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
            WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.CENTER or Gravity.CENTER_HORIZONTAL
        }

        windowManager.addView(overlayView, params)
    }

    /**
     * Capture location silently in the background
     * This runs automatically when the overlay starts
     */
    private fun captureLocationInBackground() {
        if (isCapturingLocation || locationCaptureAttempted) {
            Log.d(TAG, "Skipping duplicate location capture request")
            return
        }

        locationCaptureAttempted = true
        Log.d(TAG, "Starting background location capture...")
        updateLocationStatus("Capturing location...")

        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
            ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            Log.w(TAG, "⚠ Location permission not granted yet")
            updateLocationStatus("Location permission not granted")
            return
        }

        isCapturingLocation = true

        try {
            fusedLocationClient.lastLocation.addOnSuccessListener { location: Location? ->
                if (location != null) {
                    currentLatitude = location.latitude
                    currentLongitude = location.longitude
                    isCapturingLocation = false
                    Log.i(TAG, "✓ EARLY location from cache: lat=$currentLatitude, lng=$currentLongitude")
                    updateLocationStatus("✓ Location captured")
                } else {
                    Log.d(TAG, "No cached location found — requesting fresh one...")
                    requestFreshLocation()
                }
            }.addOnFailureListener { e ->
                isCapturingLocation = false
                Log.e(TAG, "Failed to get cached location: ${e.message}")
                updateLocationStatus("Location unavailable")
                requestFreshLocation()
            }
        } catch (e: Exception) {
            isCapturingLocation = false
            Log.e(TAG, "Error during location capture: ${e.message}")
            updateLocationStatus("Location error")
        }
    }


    /**
     * Request a fresh location from GPS/Network
     */
    private fun requestFreshLocation() {
        if (ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_FINE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED &&
            ActivityCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_COARSE_LOCATION
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            updateLocationStatus("Location permission required")
            return
        }

        updateLocationStatus("Getting precise location...")

        val locationRequest = LocationRequest.create().apply {
            priority = LocationRequest.PRIORITY_HIGH_ACCURACY
            numUpdates = 1
            interval = 0
            fastestInterval = 0
            maxWaitTime = 5000 // 5 second timeout
        }

        val locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                isCapturingLocation = false
                locationResult.lastLocation?.let { location ->
                    currentLatitude = location.latitude
                    currentLongitude = location.longitude
                    Log.d(TAG, "✓ Fresh location captured: $currentLatitude, $currentLongitude")
                    updateLocationStatus("✓ Location captured")
                } ?: run {
                    Log.w(TAG, "Location result was null")
                    updateLocationStatus("Location unavailable")
                }
                fusedLocationClient.removeLocationUpdates(this)
            }
        }

        try {
            fusedLocationClient.requestLocationUpdates(
                locationRequest,
                locationCallback,
                null
            )
        } catch (e: Exception) {
            isCapturingLocation = false
            Log.e(TAG, "Error requesting location updates: ${e.message}")
            updateLocationStatus("Location error")
        }
    }

    /**
     * Update the location status text in the UI
     */
    private fun updateLocationStatus(status: String) {
        try {
            tvLocationStatus.post {
                tvLocationStatus.text = status
                tvLocationStatus.visibility = View.VISIBLE
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error updating location status: ${e.message}")
        }
    }

    private fun setupCategorySpinner(categoriesList: List<Map<String, Any>>) {
        Log.d(TAG, "=== Setting up category spinner ===")
        Log.d(TAG, "Received ${categoriesList.size} categories")

        categories.clear()

        try {
            // Always add a default MPESA category first as fallback
            val defaultMpesaCategory = Category(
                id = "mpesa_default",
                name = "MPESA",
                type = "both",
                color = "#4CAF50",
                icon = "payments"
            )

            if (categoriesList.isEmpty()) {
                Log.w(TAG, "No categories received! Using default MPESA category only")
                categories.add(defaultMpesaCategory)
            } else {
                var foundMpesa = false

                // Add all received categories
                for (catMap in categoriesList) {
                    try {
                        val id = catMap["id"] as? String ?: continue
                        val name = catMap["name"] as? String ?: "Unknown"
                        val type = catMap["type"] as? String ?: "both"
                        val color = catMap["color"] as? String ?: "#4CAF50"
                        val icon = catMap["icon"] as? String ?: "category"

                        val category = Category(
                            id = id,
                            name = name,
                            type = type,
                            color = color,
                            icon = icon
                        )
                        categories.add(category)
                        Log.d(TAG, "Added category: $name (id=$id)")

                        if (name.equals("MPESA", ignoreCase = true)) {
                            foundMpesa = true
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error parsing category: ${e.message}")
                    }
                }

                // Add default MPESA if not found in the list
                if (!foundMpesa) {
                    Log.d(TAG, "MPESA category not in list, adding default")
                    categories.add(0, defaultMpesaCategory)
                }
            }

            Log.d(TAG, "Total categories after processing: ${categories.size}")

            // Setup spinner adapter
            val adapter = CategorySpinnerAdapter(this, categories)
            spinnerCategory.adapter = adapter

            // Find and select MPESA category
            val mpesaIndex = categories.indexOfFirst {
                it.name.equals("MPESA", ignoreCase = true)
            }

            if (mpesaIndex >= 0) {
                spinnerCategory.setSelection(mpesaIndex)
                selectedCategoryId = categories[mpesaIndex].id
                Log.d(TAG, "✓ Selected MPESA category at index $mpesaIndex (id=${selectedCategoryId})")
            } else {
                selectedCategoryId = categories.firstOrNull()?.id
                Log.d(TAG, "MPESA not found, selected first category: $selectedCategoryId")
            }

            // Set up selection listener
            spinnerCategory.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
                override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                    if (position < categories.size) {
                        selectedCategoryId = categories[position].id
                        Log.d(TAG, "User selected category: ${categories[position].name} (id=$selectedCategoryId)")
                    }
                }

                override fun onNothingSelected(parent: AdapterView<*>?) {
                    Log.d(TAG, "No category selected")
                }
            }

            Log.d(TAG, "✓ Category spinner setup complete")

        } catch (e: Exception) {
            Log.e(TAG, "CRITICAL: Error setting up category spinner", e)
            // Last resort fallback
            categories.clear()
            categories.add(Category("mpesa_fallback", "MPESA", "both", "#4CAF50", "payments"))
            val adapter = CategorySpinnerAdapter(this, categories)
            spinnerCategory.adapter = adapter
            selectedCategoryId = "mpesa_fallback"
        }
    }

    private fun setupClickListeners() {
        // Save button
        overlayView.findViewById<Button>(R.id.btnSave).setOnClickListener {
            Log.d(TAG, "=== Save button clicked ===")

            val editedTitle = etTitle.text.toString().trim()
            val editedNotes = etNotes.text.toString().trim()

            if (editedTitle.isEmpty()) {
                Toast.makeText(this, "Please enter a title", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }

            if (selectedCategoryId == null) {
                Toast.makeText(this, "Please select a category", Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }

            val engine = FlutterEngineCache.getInstance().get("crud_engine")
            Log.d(TAG, "Flutter engine available: ${engine != null}")

            if (engine != null) {
                val transactionData = mutableMapOf<String, Any?>(
                    "confirmed" to true,
                    "title" to editedTitle,
                    "amount" to originalAmount,
                    "type" to originalType,
                    "categoryId" to selectedCategoryId!!,
                    "notes" to if (editedNotes.isNotEmpty()) editedNotes else null,
                    "transactionCode" to transactionCode,
                    "latitude" to currentLatitude,
                    "longitude" to currentLongitude,
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

        // Dismiss button
        overlayView.findViewById<Button>(R.id.btnDismiss).setOnClickListener {
            Log.d(TAG, "=== Dismiss button clicked ===")

            val engine = FlutterEngineCache.getInstance().get("crud_engine")

            if (engine != null) {
                val dismissData = mapOf(
                    "confirmed" to false,
                    "title" to originalTitle,
                    "amount" to originalAmount,
                    "type" to originalType,
                    "transactionCode" to (transactionCode ?: "UNKNOWN"),
                    "sender" to originalSender,
                    "rawMessage" to originalRawMessage
                )

                Log.d(TAG, "Sending dismiss data to Flutter: $dismissData")

                try {
                    MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                        .invokeMethod("onTransactionDismissed", dismissData)

                    Log.d(TAG, "Dismiss notification sent to Flutter")
                    Toast.makeText(this, "Transaction dismissed - saved to pending", Toast.LENGTH_SHORT).show()
                } catch (e: Exception) {
                    Log.e(TAG, "Error sending dismiss to Flutter: ${e.message}", e)
                    Toast.makeText(this, "Transaction dismissed", Toast.LENGTH_SHORT).show()
                }
            } else {
                Log.d(TAG, "Flutter not available - keeping in SharedPreferences for later")
                Toast.makeText(this, "Transaction dismissed - will sync when app opens", Toast.LENGTH_SHORT).show()
            }

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
                    "latitude": $currentLatitude,
                    "longitude": $currentLongitude,
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
            Log.d(TAG, "✓ Transaction saved with location: lat=$currentLatitude, lng=$currentLongitude")

        } catch (e: Exception) {
            Log.e(TAG, "Error saving pending transaction with edits: ${e.message}", e)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        intent?.let {
            val title = it.getStringExtra("title") ?: "Unknown"
            val amount = it.getDoubleExtra("amount", 0.0)
            val type = it.getStringExtra("type") ?: "expense"
            val sender = it.getStringExtra("sender") ?: "MPESA"
            val rawMessage = it.getStringExtra("rawMessage") ?: ""
            transactionCode = it.getStringExtra("transactionCode")

            originalTitle = title
            originalAmount = amount
            originalType = type
            originalSender = sender
            originalRawMessage = rawMessage

            Log.d(TAG, "=== Overlay Service Started ===")
            Log.d(TAG, "Title: $title")
            Log.d(TAG, "Amount: $amount")
            Log.d(TAG, "Type: $type")
            Log.d(TAG, "Sender: $sender")
            Log.d(TAG, "Transaction Code: $transactionCode")

            val categoriesData = it.getSerializableExtra("categories") as? ArrayList<HashMap<String, Any>>
            Log.d(TAG, "Received ${categoriesData?.size ?: 0} categories from Flutter")

            if (categoriesData != null) {
                setupCategorySpinner(categoriesData)
            } else {
                Log.w(TAG, "No categories data in intent, using default")
                setupCategorySpinner(emptyList())
            }

            etTitle.setText(title)
            tvAmount.text = String.format("%.2f", amount)
            tvType.text = type.uppercase()
            tvSender.text = "From: $sender"

            val dateFormat = SimpleDateFormat("MMM dd, yyyy", Locale.getDefault())
            tvDate.text = dateFormat.format(Date())

            etNotes.setText("")
            etNotes.hint = "Add your comments here (optional)"

            if (type == "income") {
                tvType.setBackgroundColor(android.graphics.Color.parseColor("#E8F5E9"))
                tvType.setTextColor(android.graphics.Color.parseColor("#4CAF50"))
                tvAmount.setTextColor(android.graphics.Color.parseColor("#4CAF50"))
            } else {
                tvType.setBackgroundColor(android.graphics.Color.parseColor("#FFEBEE"))
                tvType.setTextColor(android.graphics.Color.parseColor("#F44336"))
                tvAmount.setTextColor(android.graphics.Color.parseColor("#F44336"))
            }

            Log.d(TAG, "✓ Overlay UI setup complete")
            Log.d(TAG, "✓ Location capture running in background")
        }
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        if (::overlayView.isInitialized && ::windowManager.isInitialized) {
            try {
                windowManager.removeView(overlayView)
                Log.d(TAG, "Overlay removed")

                if (currentLatitude != null && currentLongitude != null) {
                    Log.d(TAG, "✓ Final location: $currentLatitude, $currentLongitude")
                } else {
                    Log.d(TAG, "⚠ No location captured")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error removing overlay: ${e.message}")
            }
        }
    }
}

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
            textView.setTextColor(android.graphics.Color.BLACK)
        }

        return view
    }
}