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

  static Future<void> _saveTransaction(
    MpesaTransaction mpesaTransaction, {
    String? customNotes,
    String? categoryId,
  }) async {
    try {
      print('Attempting to save transaction: ${mpesaTransaction.title}');
      
      Category? mpesaCategory;
      
      if (categoryId != null) {
        mpesaCategory = await Category.getById(categoryId);
        print('Using selected category: ${mpesaCategory?.name}');
      }
      
      if (mpesaCategory == null) {
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

      print('Transaction saved successfully: ${transaction.id}');
      
      // IMPORTANT: Remove from pending messages after successful save
      if (mpesaTransaction.transactionCode.isNotEmpty) {
        await PendingMpesa.deleteByTransactionCode(
          mpesaTransaction.transactionCode,
        );
        print('Removed from pending messages');
      }
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
          
          await _saveTransaction(
            mpesaTransaction,
            customNotes: data['notes'] as String?,
            categoryId: data['categoryId'] as String?,
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