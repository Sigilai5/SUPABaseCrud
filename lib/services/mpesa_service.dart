// lib/services/mpesa_service.dart
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'mpesa_parser.dart';
import '../models/transaction.dart';
import '../models/category.dart';
import '../models/pending_mpesa.dart';

class MpesaService {
  static const MethodChannel _channel = MethodChannel('com.example.crud/mpesa');
  static MpesaTransaction? _pendingTransaction;
  
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
        
        if (call.arguments is bool) {
          print('Received boolean format');
          final confirmed = call.arguments as bool;
          if (confirmed && _pendingTransaction != null) {
            await _saveTransaction(_pendingTransaction!);
          }
        } else if (call.arguments is Map) {
          print('Received map format');
          final data = Map<String, dynamic>.from(call.arguments);
          print('Parsed data: $data');
          
          final confirmed = data['confirmed'] as bool;
          print('Confirmed: $confirmed');
          
          if (confirmed && _pendingTransaction != null) {
            print('Creating updated transaction');
            final updatedTransaction = MpesaTransaction(
              title: data['title'] as String? ?? _pendingTransaction!.title,
              amount: (data['amount'] as num?)?.toDouble() ?? _pendingTransaction!.amount,
              type: data['type'] as String? ?? _pendingTransaction!.type,
              transactionCode: data['transactionCode'] as String? ?? _pendingTransaction!.transactionCode,
              date: _pendingTransaction!.date,
              rawMessage: _pendingTransaction!.rawMessage,
              sender: _pendingTransaction!.sender,
              recipient: _pendingTransaction!.recipient,
            );
            
            print('Calling _saveTransaction with categoryId: ${data['categoryId']}');
            await _saveTransaction(
              updatedTransaction,
              customNotes: data['notes'] as String?,
              categoryId: data['categoryId'] as String?,
            );
            print('Transaction saved successfully');
          } else {
            print('Not saving - confirmed: $confirmed, pending: ${_pendingTransaction != null}');
          }
        }
        _pendingTransaction = null;
        break;
      
      case 'onTransactionDismissed':
        print('Handling transaction dismissal');
        final data = Map<String, dynamic>.from(call.arguments);
        await _handleTransactionDismissed(data);
        break;
        
      default:
        print('Unknown method: ${call.method}');
    }
  }

  static Future<void> _handleMpesaSms(String sender, String message) async {
    print('Processing MPESA SMS: $message');
    
    // Parse the message
    final mpesaTransaction = MpesaParser.parse(message);
    if (mpesaTransaction == null) {
      print('Could not parse MPESA message');
      return;
    }

    // Save as pending message FIRST (before anything else)
    await _savePendingMessage(sender, message, mpesaTransaction);

    // Store pending transaction for overlay
    _pendingTransaction = mpesaTransaction;

    // Check overlay permission
    final hasPermission = await hasOverlayPermission();
    if (!hasPermission) {
      print('No overlay permission - transaction saved as pending');
      return; // Don't auto-save, just keep as pending
    }

    // Show overlay
    await _showTransactionOverlay(mpesaTransaction, sender);
  }

  static Future<void> _savePendingMessage(
    String sender,
    String message,
    MpesaTransaction mpesaTransaction,
  ) async {
    try {
      // Save to pending_mpesa table
      await PendingMpesa.create(
        rawMessage: message,
        sender: sender,
        transactionCode: mpesaTransaction.transactionCode,
        amount: mpesaTransaction.amount,
        type: mpesaTransaction.type,
        parsedTitle: mpesaTransaction.title,
        receivedAt: mpesaTransaction.date,
      );
      
      print('Saved pending MPESA message: ${mpesaTransaction.transactionCode}');
    } catch (e) {
      print('Error saving pending MPESA message: $e');
    }
  }

  static Future<void> _handleTransactionDismissed(Map<String, dynamic> data) async {
    try {
      print('=== Saving Dismissed Transaction to Pending ===');
      print('Data: $data');
      
      // Extract transaction details from dismiss data
      final title = data['title'] as String? ?? 'Unknown Transaction';
      final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
      final type = data['type'] as String? ?? 'expense';
      final transactionCode = data['transactionCode'] as String? ?? 'UNKNOWN';
      final sender = data['sender'] as String? ?? 'MPESA';
      final rawMessage = data['rawMessage'] as String? ?? '';
      
      // Save to pending_mpesa table so user can review it later
      await PendingMpesa.create(
        rawMessage: rawMessage,
        sender: sender,
        transactionCode: transactionCode,
        amount: amount,
        type: type,
        parsedTitle: title,
        receivedAt: DateTime.now(),
      );
      
      print('✓ Dismissed transaction saved to pending_mpesa table');
      
      // Now remove from SharedPreferences
      try {
        if (transactionCode.isNotEmpty && transactionCode != 'UNKNOWN') {
          await _channel.invokeMethod('removePendingTransaction', {
            'transactionCode': transactionCode,
          });
          print('✓ Removed from SharedPreferences');
        }
      } catch (e) {
        print('Note: Could not remove from SharedPreferences: $e');
      }
      
      _pendingTransaction = null;
      
    } catch (e, stackTrace) {
      print('✗ Error handling dismissed transaction: $e');
      print('Stack trace: $stackTrace');
    }
  }

  static Future<void> _saveTransaction(
    MpesaTransaction mpesaTransaction, {
    String? customNotes,
    String? categoryId,
  }) async {
    try {
      print('=== Saving Transaction ===');
      print('Title: ${mpesaTransaction.title}');
      print('Amount: ${mpesaTransaction.amount}');
      print('Type: ${mpesaTransaction.type}');
      print('Category ID: $categoryId');
      
      Category? mpesaCategory;
      
      if (categoryId != null) {
        mpesaCategory = await Category.getById(categoryId);
        print('Using category: ${mpesaCategory?.name ?? "Not found"}');
      }
      
      if (mpesaCategory == null) {
        print('Category not found or not provided, getting MPESA category...');
        final categories = await Category.watchUserCategories().first;
        
        try {
          mpesaCategory = categories.firstWhere(
            (cat) => cat.name.toLowerCase() == 'mpesa',
          );
          print('Found existing MPESA category: ${mpesaCategory.id}');
        } catch (e) {
          print('MPESA category not found, creating new one');
          mpesaCategory = await Category.create(
            name: 'MPESA',
            type: 'both',
            color: '#4CAF50',
            icon: 'payments',
          );
          print('Created MPESA category: ${mpesaCategory.id}');
        }
      }

      final notes = customNotes ?? 
          'Auto-detected from MPESA SMS\nCode: ${mpesaTransaction.transactionCode}';

      // Create the transaction
      final transaction = await Transaction.create(
        title: mpesaTransaction.title,
        amount: mpesaTransaction.amount,
        type: mpesaTransaction.type == 'income' 
            ? TransactionType.income 
            : TransactionType.expense,
        categoryId: mpesaCategory.id,
        date: mpesaTransaction.date,
        notes: notes,
      );

      print('✓ Transaction saved successfully with ID: ${transaction.id}');
      
      // Remove from pending_mpesa table (if exists)
      if (mpesaTransaction.transactionCode.isNotEmpty) {
        try {
          await PendingMpesa.deleteByTransactionCode(
            mpesaTransaction.transactionCode,
          );
          print('✓ Removed from pending_mpesa table');
        } catch (e) {
          print('Note: Could not remove from pending_mpesa table: $e');
          // This is OK - might not exist in the table
        }
      }
      
      // Remove from SharedPreferences
      try {
        if (mpesaTransaction.transactionCode.isNotEmpty) {
          await _channel.invokeMethod('removePendingTransaction', {
            'transactionCode': mpesaTransaction.transactionCode,
          });
          print('✓ Removed from SharedPreferences');
        }
      } catch (e) {
        print('Note: Could not remove from SharedPreferences: $e');
      }
      
    } catch (e, stackTrace) {
      print('✗ Error saving transaction: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  static Future<void> _showTransactionOverlay(
    MpesaTransaction transaction,
    String sender,
  ) async {
    try {
      final categories = await Category.watchUserCategories().first;
      
      final filteredCategories = categories.where((cat) => 
        cat.type == transaction.type || cat.type == 'both'
      ).toList();
      
      print('Sending ${filteredCategories.length} categories to overlay');
      
      final categoriesData = filteredCategories.map((cat) => {
        'id': cat.id,
        'name': cat.name,
        'type': cat.type,
        'color': cat.color,
        'icon': cat.icon,
      }).toList();
      
      await _channel.invokeMethod('showTransactionOverlay', {
        'title': transaction.title,
        'amount': transaction.amount,
        'type': transaction.type,
        'sender': sender,
        'transactionCode': transaction.transactionCode,
        'rawMessage': transaction.rawMessage,
        'categories': categoriesData,
      });
    } catch (e) {
      print('Error showing overlay: $e');
      // If overlay fails, message is already saved as pending
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

  static Future<void> processPendingTransactions() async {
    try {
      print('=== Processing Pending Transactions ===');
      
      final List<dynamic>? pendingList = await _channel.invokeMethod('getPendingTransactions');
      
      if (pendingList == null || pendingList.isEmpty) {
        print('No pending transactions found in SharedPreferences');
        return;
      }
      
      print('Found ${pendingList.length} pending transactions to process');
      
      // Track successful and failed transactions
      int successCount = 0;
      int failCount = 0;
      
      // Save each to the database
      for (var item in pendingList) {
        try {
          final Map<String, dynamic> data = Map<String, dynamic>.from(item);
          
          print('Processing transaction: ${data['title']}');
          
          // Check if it has categoryId (from overlay) or needs default
          String? categoryId = data['categoryId'] as String?;
          
          // Handle empty string as null
          if (categoryId != null && categoryId.isEmpty) {
            categoryId = null;
          }
          
          if (categoryId == null) {
            print('No categoryId provided, getting MPESA category...');
            
            // Get or create MPESA category
            final categories = await Category.watchUserCategories().first;
            Category? mpesaCategory;
            
            try {
              mpesaCategory = categories.firstWhere(
                (cat) => cat.name.toLowerCase() == 'mpesa',
              );
              print('Found existing MPESA category: ${mpesaCategory.id}');
            } catch (e) {
              print('MPESA category not found, creating new one...');
              mpesaCategory = await Category.create(
                name: 'MPESA',
                type: 'both',
                color: '#4CAF50',
                icon: 'payments',
              );
              print('Created MPESA category: ${mpesaCategory.id}');
            }
            categoryId = mpesaCategory.id;
          } else {
            print('Using provided categoryId: $categoryId');
          }
          
          // Create MpesaTransaction object
          final mpesaTransaction = MpesaTransaction(
            title: data['title'] as String,
            amount: (data['amount'] as num).toDouble(),
            type: data['type'] as String,
            transactionCode: data['transactionCode'] as String,
            date: DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int),
            rawMessage: '',
          );
          
          // Get notes if available
          String? notes = data['notes'] as String?;
          if (notes != null && notes.isEmpty) {
            notes = null;
          }
          
          // Save to database
          await _saveTransaction(
            mpesaTransaction,
            customNotes: notes,
            categoryId: categoryId,
          );
          
          successCount++;
          print('✓ Successfully processed: ${mpesaTransaction.title}');
          
        } catch (e, stackTrace) {
          failCount++;
          print('✗ Error processing transaction: $e');
          print('Stack trace: $stackTrace');
        }
      }
      
      print('=== Processing Complete ===');
      print('Success: $successCount, Failed: $failCount');
      
      // Only clear after processing (successful or not)
      if (successCount > 0 || failCount > 0) {
        await _channel.invokeMethod('clearPendingTransactions');
        print('✓ Cleared all pending transactions from SharedPreferences');
      }
      
    } catch (e, stackTrace) {
      print('✗ Error in processPendingTransactions: $e');
      print('Stack trace: $stackTrace');
    }
  }

  // Debug method to view SharedPreferences content
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