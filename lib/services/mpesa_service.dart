// lib/services/mpesa_service.dart - COMPLETE FIXED VERSION
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../main.dart'; // Import to access navigatorKey
import 'mpesa_parser.dart';
import '../models/transaction.dart';
import '../models/category.dart';
import '../models/mpesa_transaction.dart';
import '../powersync.dart';
import '../widgets/transactions/transaction_form.dart';
import 'package:flutter/material.dart';

class MpesaService {
  static const MethodChannel _channel = MethodChannel('com.example.crud/mpesa');
  static MpesaTransaction? _pendingMpesaTransaction;
  
  static Future<void> initialize() async {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  // Update the _handleMethodCall method to include this new case:
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
        
      case 'openTransactionForm':
        print('Opening transaction form from overlay');
        final data = Map<String, dynamic>.from(call.arguments);
        await _openTransactionFormFromOverlay(data);
        break;
        
      case 'onNotificationAction':
        print('Handling notification action');
        final data = Map<String, dynamic>.from(call.arguments);
        await _handleNotificationAction(data);
        break;
        
      case 'onTransactionConfirmed':
        // This is no longer needed with the simplified overlay
        print('Legacy transaction confirmation - ignored');
        break;
      
      case 'onTransactionDismissed':
        print('Transaction dismissed by user');
        _pendingMpesaTransaction = null;
        break;
        
      default:
        print('Unknown method: ${call.method}');
    }
  }

  static Future<void> _handleNotificationAction(Map<String, dynamic> data) async {
    final action = data['action'] as String;
    
    if (action == 'add_from_notification') {
      print('=== Opening transaction form from notification ===');
      
      // Get the navigator context
      final context = navigatorKey.currentContext;
      if (context == null) {
        print('⚠ No context available, cannot navigate');
        return;
      }
      
      // Parse MPESA data
      final title = data['title'] as String? ?? 'Unknown';
      final amount = data['amount'] as double? ?? 0.0;
      final type = data['type'] as String? ?? 'expense';
      final transactionCode = data['transactionCode'] as String? ?? '';
      final rawMessage = data['rawMessage'] as String? ?? '';
      
      print('Transaction details from notification:');
      print('  Title: $title');
      print('  Amount: $amount');
      print('  Type: $type');
      print('  Code: $transactionCode');
      
      // Parse the full message to get all details
      final mpesaData = EnhancedMpesaParser.parse(rawMessage);
      if (mpesaData == null) {
        print('✗ Could not parse MPESA message');
        return;
      }
      
      print('✓ Parsed MPESA data successfully');
      
      try {
        // Check if transaction already exists
        final exists = await MpesaTransaction.exists(transactionCode);
        if (exists) {
          print('⚠ Transaction already exists: $transactionCode');
          // Still open the form but show a warning
        }
        
        // Create MPESA transaction record
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
          rawMessage: rawMessage,
          notes: EnhancedMpesaParser.generateNotes(mpesaData),
        );
        
        print('✓ MPESA transaction created from notification: ${mpesaTx.id}');
        
        // ✓ FIXED: Pass mpesaCode to the form
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TransactionForm(
              initialTitle: mpesaTx.getDisplayName(),
              initialAmount: mpesaTx.amount,
              initialType: mpesaTx.isDebit ? TransactionType.expense : TransactionType.income,
              initialNotes: mpesaTx.notes,
              initialMpesaCode: mpesaTx.transactionCode,  // ✓ FIXED: Added this line
            ),
          ),
        );
        
        print('✓ Navigated to transaction form');
        
      } catch (e, stackTrace) {
        print('✗ Error handling notification action: $e');
        print('Stack trace: $stackTrace');
      }
      
    } else if (action == 'dismiss_from_notification') {
      print('=== Transaction dismissed from notification ===');
      final transactionCode = data['transactionCode'] as String?;
      if (transactionCode != null) {
        print('Dismissed transaction: $transactionCode');
        // Optionally: You can delete from pending list if needed
      }
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

  // Update the _showTransactionOverlay method to use simplified overlay
  static Future<void> _showTransactionOverlay(MpesaTransaction mpesaTx) async {
    try {
      print('=== Showing Transaction Overlay ===');
      
      // No need to send categories anymore for simplified overlay
      final overlayData = {
        'title': mpesaTx.getDisplayName(),
        'amount': mpesaTx.amount,
        'type': mpesaTx.isDebit ? 'expense' : 'income',
        'sender': 'MPESA',
        'transactionCode': mpesaTx.transactionCode,
        'rawMessage': mpesaTx.rawMessage,
      };
      
      print('Overlay data prepared: ${overlayData.keys}');
      
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
        mpesaCode: mpesaTx.transactionCode,  // ✓ This was already correct
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

  // Request notification permission (Android 13+)
  static Future<bool> requestNotificationPermission() async {
    final status = await Permission.notification.request();
    return status.isGranted;
  }

  static Future<bool> hasNotificationPermission() async {
    final status = await Permission.notification.status;
    return status.isGranted;
  }

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
          
          final userNotes = data['notes'] as String?;
          final mpesaAutoNotes = 'Auto-recovered from offline storage\nTransaction Code: $transactionCode';
          
          final finalNotes = (userNotes != null && userNotes.isNotEmpty && !userNotes.contains('Auto-detected'))
              ? '$mpesaAutoNotes\n\nUser Notes:\n$userNotes'
              : mpesaAutoNotes;
          
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
            notes: finalNotes,
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
            editedNotes: notes,
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

  // ✓ FIXED: Updated _openTransactionFormFromOverlay method
  static Future<void> _openTransactionFormFromOverlay(Map<String, dynamic> data) async {
    print('=== Opening transaction form from overlay ===');
    
    // Get the navigator context
    final context = navigatorKey.currentContext;
    if (context == null) {
      print('⚠ No context available, cannot navigate');
      return;
    }
    
    try {
      final title = data['title'] as String? ?? 'Unknown';
      final amount = data['amount'] as double? ?? 0.0;
      final type = data['type'] as String? ?? 'expense';
      final transactionCode = data['transactionCode'] as String? ?? '';
      final rawMessage = data['rawMessage'] as String? ?? '';
      
      print('Transaction details from overlay:');
      print('  Title: $title');
      print('  Amount: $amount');
      print('  Type: $type');
      print('  Code: $transactionCode');
      
      // ✓ FIXED: Pass mpesaCode to the form
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => TransactionForm(
            initialTitle: title,
            initialAmount: amount,
            initialType: type == 'income' ? TransactionType.income : TransactionType.expense,
            initialNotes: 'Transaction Code: $transactionCode',
            initialMpesaCode: transactionCode,  // ✓ FIXED: Added this line
          ),
        ),
      );
      
      print('✓ Navigated to transaction form');
      
      // Remove from pending transactions after adding
      if (transactionCode.isNotEmpty) {
        try {
          await _channel.invokeMethod('removePendingTransaction', {
            'transactionCode': transactionCode,
          });
          print('✓ Removed from pending transactions');
        } catch (e) {
          print('Error removing from pending: $e');
        }
      }
      
    } catch (e, stackTrace) {
      print('✗ Error opening transaction form: $e');
      print('Stack trace: $stackTrace');
      
      // Show error to user
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error opening transaction form: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}