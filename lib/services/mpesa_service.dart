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
        final confirmed = call.arguments as bool;
        if (confirmed && _pendingTransaction != null) {
          await _saveTransaction(_pendingTransaction!);
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

  static Future<void> _saveTransaction(MpesaTransaction mpesaTransaction) async {
    try {
      // Find or create MPESA category
      final categories = await Category.watchUserCategories().first;
      Category? mpesaCategory = categories.firstWhere(
        (cat) => cat.name.toLowerCase() == 'mpesa',
        orElse: () => categories.first, // Use first category as fallback
      );

      // If no MPESA category exists, create one
      if (mpesaCategory.name.toLowerCase() != 'mpesa') {
        mpesaCategory = await Category.create(
          name: 'MPESA',
          type: 'both',
          color: '#4CAF50',
          icon: 'payments',
        );
      }

      // Create the transaction
      await Transaction.create(
        title: mpesaTransaction.title,
        amount: mpesaTransaction.amount,
        type: mpesaTransaction.type == 'income' 
            ? TransactionType.income 
            : TransactionType.expense,
        categoryId: mpesaCategory.id,
        date: mpesaTransaction.date,
        notes: 'Auto-detected from MPESA SMS\nCode: ${mpesaTransaction.transactionCode}',
      );

      print('Transaction saved successfully: ${mpesaTransaction.title}');
    } catch (e) {
      print('Error saving transaction: $e');
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
    // This would need a method channel to read SharedPreferences
    // For simplicity, we'll handle it when the overlay confirms
    print('Checking for pending transactions...');
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