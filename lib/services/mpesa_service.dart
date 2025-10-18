// lib/services/mpesa_service.dart
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'mpesa_parser.dart';
import '../models/transaction.dart';
import '../models/category.dart';
import '../models/mpesa_transaction.dart';
import '../powersync.dart';

class MpesaService {
  static const MethodChannel _channel = MethodChannel('com.example.crud/mpesa');
  static MpesaTransaction? _pendingMpesaTransaction;
  
  static Future<void> initialize() async {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
    print('=== Received method call: ${call.method} ===');
    
    switch (call.method) {
      case 'onMpesaSmsReceived':
        print('Handling MPESA SMS');
        final data = Map<String, dynamic>.from(call.arguments);
        await _handleMpesaSms(
          data['sender'] as String,
          data['message'] as String,
        );
        break;
        
      case 'onTransactionConfirmed':
        print('Handling transaction confirmation');
        print('Arguments type: ${call.arguments.runtimeType}');
        print('Arguments: ${call.arguments}');
        
        if (call.arguments is Map) {
          final data = Map<String, dynamic>.from(call.arguments);
          print('Parsed data: $data');
          
          final confirmed = data['confirmed'] as bool;
          print('Confirmed: $confirmed');
          
          if (confirmed && _pendingMpesaTransaction != null) {
            print('Creating transaction from MPESA data');
            
            // Extract edited data from overlay
            final editedTitle = data['title'] as String? ?? _pendingMpesaTransaction!.getDisplayName();
            final editedNotes = data['notes'] as String?;
            final categoryId = data['categoryId'] as String?;
            final latitude = data['latitude'] as double?;
            final longitude = data['longitude'] as double?;
            
            print('Calling _saveAsTransaction with categoryId: $categoryId');
            print('Location: $latitude, $longitude');
            
            await _saveAsTransaction(
              _pendingMpesaTransaction!,
              editedTitle: editedTitle,
              editedNotes: editedNotes,
              categoryId: categoryId,
              latitude: latitude,
              longitude: longitude,
            );
            print('Transaction saved successfully');
          }
        }
        _pendingMpesaTransaction = null;
        break;
      
      case 'onTransactionDismissed':
        print('Transaction dismissed by user');
        _pendingMpesaTransaction = null;
        break;
        
      default:
        print('Unknown method: ${call.method}');
    }
  }

  static Future<void> _handleMpesaSms(String sender, String message) async {
    print('Processing MPESA SMS from $sender: $message');
    
    // Parse the MPESA message
    final mpesaData = EnhancedMpesaParser.parse(message);
    if (mpesaData == null) {
      print('Could not parse MPESA message');
      return;
    }

    print('✓ Parsed MPESA transaction: ${mpesaData.transactionCode}');
    print('  Type: ${mpesaData.transactionType.name}');
    print('  Amount: ${mpesaData.amount}');
    print('  Counterparty: ${mpesaData.counterpartyName}');

    // Check if this transaction code already exists
    final exists = await MpesaTransaction.exists(mpesaData.transactionCode);
    if (exists) {
      print('Transaction ${mpesaData.transactionCode} already recorded');
      return;
    }

    // Save to mpesa_transactions table with auto-generated notes
    final mpesaTx = await MpesaTransaction.create(
      transactionCode: mpesaData.transactionCode,
      transactionType: mpesaData.transactionType,
      amount: mpesaData.amount,
      counterpartyName: mpesaData.counterpartyName,
      counterpartyNumber: mpesaData.counterpartyNumber,
      transactionDate: mpesaData.transactionDate,
      newBalance: mpesaData.newBalance,
      transactionCost: mpesaData.transactionCost,
      isDebit: mpesaData.isDebit,
      rawMessage: message,
      notes: EnhancedMpesaParser.generateNotes(mpesaData),
    );

    print('✓ MPESA transaction saved to database: ${mpesaTx.id}');

    // Store for potential overlay confirmation
    _pendingMpesaTransaction = mpesaTx;

    // Check overlay permission and show if granted
    final hasPermission = await hasOverlayPermission();
    if (!hasPermission) {
      print('No overlay permission - transaction saved to pending');
      return;
    }

    await _showTransactionOverlay(mpesaTx);
  }

  // In mpesa_service.dart - Update the _showTransactionOverlay method

static Future<void> _showTransactionOverlay(MpesaTransaction mpesaTx) async {
  try {
    print('=== Showing Transaction Overlay ===');
    
    // Get categories for the overlay
    final categories = await Category.watchUserCategories().first;
    print('Total categories available: ${categories.length}');
    
    // Filter categories based on transaction type (debit = expense, credit = income)
    final transactionType = mpesaTx.isDebit ? 'expense' : 'income';
    final filteredCategories = categories.where((cat) => 
      cat.type == transactionType || cat.type == 'both'
    ).toList();
    
    print('Filtered categories for $transactionType: ${filteredCategories.length}');
    
    // Convert to simple maps - CRITICAL: Ensure all values are primitives
    final categoriesData = filteredCategories.map((cat) {
      final data = {
        'id': cat.id,
        'name': cat.name,
        'type': cat.type,
        'color': cat.color,
        'icon': cat.icon,
      };
      print('Category data: ${cat.name} -> $data');
      return data;
    }).toList();
    
    print('Sending ${categoriesData.length} categories to Android');
    
    // Validate that we have at least one category
    if (categoriesData.isEmpty) {
      print('WARNING: No categories to send! This should not happen.');
    }
    
    final overlayData = {
      'title': mpesaTx.getDisplayName(),
      'amount': mpesaTx.amount,
      'type': mpesaTx.isDebit ? 'expense' : 'income',
      'sender': 'MPESA',
      'transactionCode': mpesaTx.transactionCode,
      'rawMessage': mpesaTx.rawMessage,
      'categories': categoriesData,
    };
    
    print('Overlay data prepared: ${overlayData.keys}');
    print('Categories data type: ${categoriesData.runtimeType}');
    print('First category type: ${categoriesData.isNotEmpty ? categoriesData[0].runtimeType : "none"}');
    
    await _channel.invokeMethod('showTransactionOverlay', overlayData);

    print('✓ Overlay method invoked successfully');
  } catch (e, stackTrace) {
    print('✗ Error showing overlay: $e');
    print('Stack trace: $stackTrace');
  }
}

  static Future<void> _saveAsTransaction(
    MpesaTransaction mpesaTx, {
    String? editedTitle,
    String? editedNotes,
    String? categoryId,
    double? latitude,
    double? longitude,
  }) async {
    try {
      print('=== Saving MPESA transaction as regular transaction ===');
      print('MPESA ID: ${mpesaTx.id}');
      print('Transaction Code: ${mpesaTx.transactionCode}');
      print('Title: $editedTitle');
      print('Amount: ${mpesaTx.amount}');
      print('Type: ${mpesaTx.isDebit ? 'expense' : 'income'}');
      print('Category ID: $categoryId');
      print('Location: $latitude, $longitude');
      
      // Get or create MPESA category if no category provided
      Category? category;
      
      if (categoryId != null) {
        category = await Category.getById(categoryId);
        print('Using provided category: ${category?.name ?? "Not found"}');
      }
      
      if (category == null) {
        print('No category provided or found, getting/creating MPESA category...');
        final categories = await Category.watchUserCategories().first;
        
        try {
          category = categories.firstWhere(
            (cat) => cat.name.toLowerCase() == 'mpesa',
          );
          print('Found existing MPESA category: ${category.id}');
        } catch (e) {
          print('MPESA category not found, creating new one');
          category = await Category.create(
            name: 'Other',
            type: 'both',
            color: '#4CAF50',
            icon: 'payments',
          );
          print('Created MPESA category: ${category.id}');
        }
      }

      // Use ONLY user's notes - nothing auto-generated
      final userNotes = (editedNotes != null && editedNotes.trim().isNotEmpty)
          ? editedNotes.trim()
          : null;

      // Create the regular transaction
      final transaction = await Transaction.create(
        title: editedTitle ?? mpesaTx.getDisplayName(),
        amount: mpesaTx.amount,
        type: mpesaTx.isDebit ? TransactionType.expense : TransactionType.income,
        categoryId: category.id,
        date: mpesaTx.transactionDate,
        notes: userNotes,
        latitude: latitude,
        longitude: longitude,
        mpesaCode: mpesaTx.transactionCode,
      );

      print('✓ Regular transaction created with ID: ${transaction.id}');
      if (latitude != null && longitude != null) {
        print('✓ Location saved: $latitude, $longitude');
      }
      
      // CRITICAL FIX: Get fresh MPESA transaction from database using transaction code
      print('Fetching fresh MPESA transaction from database...');
      
      MpesaTransaction? mpesaFromDb;
      int retryCount = 0;
      const maxRetries = 5;
      
      while (mpesaFromDb == null && retryCount < maxRetries) {
        // Progressive delay: 100ms, 200ms, 300ms, 400ms, 500ms
        await Future.delayed(Duration(milliseconds: 100 * (retryCount + 1)));
        print('Attempt ${retryCount + 1}: Fetching MPESA transaction by code...');
        mpesaFromDb = await MpesaTransaction.getByCode(mpesaTx.transactionCode);
        retryCount++;
      }
      
      if (mpesaFromDb == null) {
        print('⚠ ERROR: Could not find MPESA transaction in database after $maxRetries retries');
        print('Transaction code: ${mpesaTx.transactionCode}');
        throw Exception('MPESA transaction not found in database after $maxRetries retries');
      }
      
      print('✓ Found MPESA transaction in database: ${mpesaFromDb.id}');
      print('Current linked_transaction_id: ${mpesaFromDb.linkedTransactionId}');
      
      // Now link using the database-fetched instance
      print('Linking MPESA transaction ${mpesaFromDb.id} to transaction ${transaction.id}');
      
      try {
        await mpesaFromDb.linkToTransaction(transaction.id);
        print('✓ linkToTransaction method executed');
      } catch (e) {
        print('✗ ERROR in linkToTransaction: $e');
        // Continue to verification - we'll use fallback if needed
      }
      
      // Wait for the link to be committed
      await Future.delayed(const Duration(milliseconds: 200));
      
      // VERIFY the link was created
      final verifyMpesa = await MpesaTransaction.getByCode(mpesaTx.transactionCode);
      if (verifyMpesa?.linkedTransactionId == transaction.id) {
        print('✓ VERIFIED: Link successfully created');
        print('  linked_transaction_id: ${verifyMpesa?.linkedTransactionId}');
      } else {
        print('⚠ WARNING: Link verification failed');
        print('  Expected linked_transaction_id: ${transaction.id}');
        print('  Actual linked_transaction_id: ${verifyMpesa?.linkedTransactionId}');
        
        // FALLBACK: Direct SQL update
        if (verifyMpesa != null && verifyMpesa.linkedTransactionId == null) {
          print('Attempting direct SQL update as fallback...');
          try {
            final userId = getUserId();
            if (userId == null) {
              throw Exception('User ID is null');
            }
            
            await db.execute('''
              UPDATE mpesa_transactions 
              SET linked_transaction_id = ?
              WHERE transaction_code = ? AND user_id = ?
            ''', [transaction.id, mpesaTx.transactionCode, userId]);
            
            print('✓ Direct SQL update executed');
            
            await Future.delayed(const Duration(milliseconds: 200));
            
            // Final verification
            final finalCheck = await MpesaTransaction.getByCode(mpesaTx.transactionCode);
            if (finalCheck?.linkedTransactionId == transaction.id) {
              print('✓ VERIFIED: Link created via direct SQL update');
            } else {
              print('✗ ERROR: Link still failed after direct SQL update');
              print('  Final linked_transaction_id: ${finalCheck?.linkedTransactionId}');
            }
          } catch (e) {
            print('✗ ERROR: Direct SQL update failed: $e');
          }
        }
      }
      
      // Clear from any pending stores
      try {
        await _channel.invokeMethod('removePendingTransaction', {
          'transactionCode': mpesaTx.transactionCode,
        });
        print('✓ Removed from SharedPreferences');
      } catch (e) {
        print('Note: Could not remove from SharedPreferences: $e');
      }
      
    } catch (e, stackTrace) {
      print('✗ Error saving transaction: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  static Future<bool> hasOverlayPermission() async {
    try {
      final result = await _channel.invokeMethod('hasOverlayPermission');
      return result as bool;
    } catch (e) {
      print('Error checking overlay permission: $e');
      return false;
    }
  }

  static Future<bool> requestOverlayPermission() async {
    try {
      final result = await _channel.invokeMethod('requestOverlayPermission');
      return result as bool;
    } catch (e) {
      print('Error requesting overlay permission: $e');
      return false;
    }
  }

  static Future<bool> requestSmsPermission() async {
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  static Future<bool> hasSmsPermission() async {
    final status = await Permission.sms.status;
    return status.isGranted;
  }

  // lib/services/mpesa_service.dart
// CRITICAL FIX: Line 397 - Don't override user notes with "Auto-recovered"

// Find this section around line 360-420:
static Future<void> processPendingTransactions() async {
    try {
      print('=== Processing Pending Transactions ===');
      
      final List<dynamic>? pendingList = await _channel.invokeMethod('getPendingTransactions');
      
      if (pendingList == null || pendingList.isEmpty) {
        print('No pending transactions found in SharedPreferences');
        return;
      }
      
      print('Found ${pendingList.length} pending transactions to process');
      
      int successCount = 0;
      int failCount = 0;
      
      for (var item in pendingList) {
        try {
          final Map<String, dynamic> data = Map<String, dynamic>.from(item);
          
          print('Processing transaction: ${data['title']}');
          
          final transactionCode = data['transactionCode'] as String;
          
          final exists = await MpesaTransaction.exists(transactionCode);
          if (exists) {
            print('Transaction $transactionCode already exists, skipping');
            successCount++;
            continue;
          }
          
          String? categoryId = data['categoryId'] as String?;
          if (categoryId != null && categoryId.isEmpty) {
            categoryId = null;
          }
          
          if (categoryId == null) {
            final categories = await Category.watchUserCategories().first;
            Category? mpesaCategory;
            
            try {
              mpesaCategory = categories.firstWhere(
                (cat) => cat.name.toLowerCase() == 'mpesa',
              );
            } catch (e) {
              mpesaCategory = await Category.create(
                name: 'MPESA',
                type: 'both',
                color: '#4CAF50',
                icon: 'payments',
              );
            }
            categoryId = mpesaCategory.id;
          }
          
          final type = data['type'] as String;
          final isDebit = type == 'expense';
          
          // ========================================
          // 🔧 FIX: Preserve user notes from SharedPreferences
          // ========================================
          final userNotes = data['notes'] as String?;
          final mpesaAutoNotes = 'Auto-recovered from offline storage\nTransaction Code: $transactionCode';
          
          final finalNotes = (userNotes != null && userNotes.isNotEmpty && !userNotes.contains('Auto-detected'))
              ? '$mpesaAutoNotes\n\nUser Notes:\n$userNotes'
              : mpesaAutoNotes;
          // ========================================
          
          final mpesaTx = await MpesaTransaction.create(
            transactionCode: transactionCode,
            transactionType: isDebit ? MpesaTransactionType.send : MpesaTransactionType.received,
            amount: (data['amount'] as num).toDouble(),
            counterpartyName: 'Unknown',
            transactionDate: DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int),
            newBalance: 0.0,
            transactionCost: 0.0,
            isDebit: isDebit,
            rawMessage: 'Recovered from offline storage',
            notes: finalNotes,  // 🔧 Use the combined notes here
          );
          
          print('✓ Created MPESA transaction: ${mpesaTx.id}');
          
          String? notes = data['notes'] as String?;
          if (notes != null && notes.isEmpty) {
            notes = null;
          }
          
          final latitude = data['latitude'] as double?;
          final longitude = data['longitude'] as double?;
          
          await _saveAsTransaction(
            mpesaTx,
            editedTitle: data['title'] as String,
            editedNotes: notes,  // 🔧 Pass the user's original notes
            categoryId: categoryId,
            latitude: latitude,
            longitude: longitude,
          );
          
          successCount++;
          print('✓ Successfully processed: ${data['title']}');
          
        } catch (e, stackTrace) {
          failCount++;
          print('✗ Error processing transaction: $e');
          print('Stack trace: $stackTrace');
        }
      }
      
      print('=== Processing Complete ===');
      print('Success: $successCount, Failed: $failCount');
      
      if (successCount > 0 || failCount > 0) {
        await _channel.invokeMethod('clearPendingTransactions');
        print('✓ Cleared all pending transactions from SharedPreferences');
      }
      
    } catch (e, stackTrace) {
      print('✗ Error in processPendingTransactions: $e');
      print('Stack trace: $stackTrace');
    }
  }

  static Future<List<Map<String, dynamic>>> getPendingTransactionsFromSharedPrefs() async {
    try {
      final List<dynamic>? result = await _channel.invokeMethod('getPendingTransactions');
      if (result == null) return [];
      return result.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      print('Error getting pending transactions: $e');
      return [];
    }
  }

  static Future<void> requestBatteryOptimizationExemption() async {
    try {
      final platform = MethodChannel('com.example.crud/mpesa');
      await platform.invokeMethod('disableBatteryOptimization');
    } catch (e) {
      print('Error requesting battery optimization exemption: $e');
    }
  }
}