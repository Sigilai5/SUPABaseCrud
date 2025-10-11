import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'mpesa_parser.dart';
import '../models/transaction.dart';
import '../models/category.dart';

class MpesaService {
  static const MethodChannel _channel = MethodChannel('com.example.crud/mpesa');
  static MpesaTransaction? _pendingTransaction;
  
  static Future<void> initialize() async {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  static Future<dynamic> _handleMethodCall(MethodCall call) async {
  switch (call.method) {
    case 'onMpesaSmsReceived':
      final data = Map<String, dynamic>.from(call.arguments);
      await _handleMpesaSms(
        data['sender'] as String,
        data['message'] as String,
      );
      break;
      
    case 'onTransactionConfirmed':
      // Handle both old boolean format and new map format
      if (call.arguments is bool) {
        final confirmed = call.arguments as bool;
        if (confirmed && _pendingTransaction != null) {
          await _saveTransaction(_pendingTransaction!);
        }
      } else if (call.arguments is Map) {
        final data = Map<String, dynamic>.from(call.arguments);
        final confirmed = data['confirmed'] as bool;
        
        if (confirmed && _pendingTransaction != null) {
          // Create updated transaction with edited data
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
          
          await _saveTransaction(
            updatedTransaction,
            customNotes: data['notes'] as String?,
          );
        }
      }
      _pendingTransaction = null;
      break;
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

    // Store pending transaction
    _pendingTransaction = mpesaTransaction;

    // Check overlay permission
    final hasPermission = await hasOverlayPermission();
    if (!hasPermission) {
      print('No overlay permission - saving transaction directly');
      await _saveTransaction(mpesaTransaction);
      return;
    }

    // Show overlay
    await _showTransactionOverlay(mpesaTransaction, sender);
  }

  static Future<void> _saveTransaction(
  MpesaTransaction mpesaTransaction, {
  String? customNotes,
}) async {
  try {
    print('Attempting to save transaction: ${mpesaTransaction.title}');
    
    // Find or create MPESA category
    final categories = await Category.watchUserCategories().first;
    Category? mpesaCategory;
    
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

    // Use custom notes if provided, otherwise use default
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

    print('Transaction saved successfully: ${transaction.id}');
  } catch (e, stackTrace) {
    print('Error saving transaction: $e');
    print('Stack trace: $stackTrace');
    rethrow;
  }
}

  static Future<void> _showTransactionOverlay(
    MpesaTransaction transaction,
    String sender,
  ) async {
    try {
      await _channel.invokeMethod('showTransactionOverlay', {
        'title': transaction.title,
        'amount': transaction.amount,
        'type': transaction.type,
        'sender': sender,
        'rawMessage': transaction.rawMessage,
      });
    } catch (e) {
      print('Error showing overlay: $e');
      // Fallback: save directly if overlay fails
      await _saveTransaction(transaction);
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
    print('Checking for pending transactions...');
    
    final List<dynamic>? pendingList = await _channel.invokeMethod('getPendingTransactions');
    
    if (pendingList == null || pendingList.isEmpty) {
      print('No pending transactions found');
      return;
    }
    
    print('Found ${pendingList.length} pending transactions to process');
    
    for (var item in pendingList) {
      try {
        final Map<String, dynamic> data = Map<String, dynamic>.from(item);
        
        final mpesaTransaction = MpesaTransaction(
          title: data['title'] as String,
          amount: (data['amount'] as num).toDouble(),
          type: data['type'] as String,
          transactionCode: data['transactionCode'] as String,
          date: DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int),
          rawMessage: '',
        );
        
        // Save with custom notes if available
        await _saveTransaction(
          mpesaTransaction,
          customNotes: data['notes'] as String?,
        );
        print('Processed pending transaction: ${mpesaTransaction.title}');
        
      } catch (e) {
        print('Error processing individual transaction: $e');
      }
    }
    
    await _channel.invokeMethod('clearPendingTransactions');
    print('Cleared all pending transactions from SharedPreferences');
    
  } catch (e) {
    print('Error processing pending transactions: $e');
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