// lib/services/mpesa_service.dart - DOES NOT AUTO-SAVE - Only shows overlay/pending
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

    // Check if this transaction code already exists in TRANSACTIONS table (not mpesa_transactions)
    // We only check if user has already recorded this as a transaction
    final userId = getUserId();
    if (userId == null) {
      print('User not logged in');
      return;
    }

    final alreadyRecorded = await db.getOptional('''
      SELECT COUNT(*) as count FROM transactions 
      WHERE user_id = ? AND mpesa_code = ?
    ''', [userId, mpesaData.transactionCode]);
    
    final count = (alreadyRecorded?['count'] as int?) ?? 0;
    if (count > 0) {
      print('Transaction ${mpesaData.transactionCode} already recorded by user');
      return;
    }

    print('✓ New unrecorded MPESA transaction detected');

    // DO NOT auto-save to mpesa_transactions table
    // Just show overlay for user confirmation

    // Check overlay permission and show if granted
    final hasPermission = await hasOverlayPermission();
    if (!hasPermission) {
      print('No overlay permission - transaction will appear in pending SMS list');
      return;
    }

    // Show overlay with transaction data directly (no database storage yet)
    await _showTransactionOverlayFromData(mpesaData, sender, message);
  }

  static Future<void> _showTransactionOverlayFromData(
    MpesaTransactionData mpesaData,
    String sender,
    String message,
  ) async {
    try {
      print('=== Showing Transaction Overlay (from parsed data) ===');
      
      final displayName = EnhancedMpesaParser.getTransactionDescription(mpesaData);
      
      final overlayData = {
        'title': displayName,
        'amount': mpesaData.amount,
        'type': mpesaData.isDebit ? 'expense' : 'income',
        'sender': sender,
        'transactionCode': mpesaData.transactionCode,
        'rawMessage': message,
      };
      
      print('Overlay data prepared: ${overlayData.keys}');
      
      await _channel.invokeMethod('showTransactionOverlay', overlayData);

      print('✓ Overlay method invoked successfully');
    } catch (e, stackTrace) {
      print('✗ Error showing overlay: $e');
      print('Stack trace: $stackTrace');
    }
  }

  static Future<void> _closeApp() async {
    try {
      await _channel.invokeMethod('closeApp');
      print('✓ App close requested');
    } catch (e) {
      print('Error closing app: $e');
    }
  }

  static Future<void> _saveAsTransaction(
    String transactionCode,
    String title,
    double amount,
    String type,
    String rawMessage, {
    String? editedTitle,
    String? editedNotes,
    String? categoryId,
    double? latitude,
    double? longitude,
    bool fromOverlay = false,
  }) async {
    try {
      print('=== Saving MPESA transaction as regular transaction ===');
      print('Transaction Code: $transactionCode');
      print('Title: ${editedTitle ?? title}');
      print('Amount: $amount');
      print('Type: $type');
      print('Category ID: $categoryId');
      print('Location: $latitude, $longitude');
      print('From Overlay: $fromOverlay');
      
      // Get or create category if no category provided
      Category? category;
      
      if (categoryId != null) {
        category = await Category.getById(categoryId);
        print('Using provided category: ${category?.name ?? "Not found"}');
      }
      
      if (category == null) {
        print('No category provided or found, getting/creating Other category...');
        final categories = await Category.watchUserCategories().first;
        
        try {
          category = categories.firstWhere(
            (cat) => cat.name.toLowerCase() == 'other',
          );
          print('Found existing Other category: ${category.id}');
        } catch (e) {
          print('Other category not found, creating new one');
          category = await Category.create(
            name: 'Other',
            type: 'both',
            color: '#4CAF50',
            icon: 'payments',
          );
          print('Created Other category: ${category.id}');
        }
      }

      // Use ONLY user's notes
      final userNotes = (editedNotes != null && editedNotes.trim().isNotEmpty)
          ? editedNotes.trim()
          : null;

      // Create the regular transaction
      final transaction = await Transaction.create(
        title: editedTitle ?? title,
        amount: amount,
        type: type == 'income' ? TransactionType.income : TransactionType.expense,
        categoryId: category.id,
        date: DateTime.now(),
        notes: userNotes,
        latitude: latitude,
        longitude: longitude,
        mpesaCode: transactionCode,
      );

      print('✓ Regular transaction created with ID: ${transaction.id}');
      if (latitude != null && longitude != null) {
        print('✓ Location saved: $latitude, $longitude');
      }
      
      // Clear from any pending stores
      try {
        await _channel.invokeMethod('removePendingTransaction', {
          'transactionCode': transactionCode,
        });
        print('✓ Removed from SharedPreferences');
      } catch (e) {
        print('Note: Could not remove from SharedPreferences: $e');
      }
      
      // Close app if from overlay
      if (fromOverlay) {
        print('Transaction added from overlay - closing app...');
        await Future.delayed(const Duration(milliseconds: 500));
        await _closeApp();
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
          
          // Check if already recorded (check transactions table, not mpesa_transactions)
          final userId = getUserId();
          if (userId == null) {
            print('User not logged in, skipping');
            continue;
          }

          final alreadyRecorded = await db.getOptional('''
            SELECT COUNT(*) as count FROM transactions 
            WHERE user_id = ? AND mpesa_code = ?
          ''', [userId, transactionCode]);
          
          final count = (alreadyRecorded?['count'] as int?) ?? 0;
          if (count > 0) {
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
            Category? otherCategory;
            
            try {
              otherCategory = categories.firstWhere(
                (cat) => cat.name.toLowerCase() == 'other',
              );
            } catch (e) {
              otherCategory = await Category.create(
                name: 'Other',
                type: 'both',
                color: '#4CAF50',
                icon: 'payments',
              );
            }
            categoryId = otherCategory.id;
          }
          
          final type = data['type'] as String;
          
          String? notes = data['notes'] as String?;
          if (notes != null && notes.isEmpty) {
            notes = null;
          }
          
          final latitude = data['latitude'] as double?;
          final longitude = data['longitude'] as double?;
          
          await _saveAsTransaction(
            transactionCode,
            data['title'] as String,
            (data['amount'] as num).toDouble(),
            type,
            'Recovered from offline storage',
            editedTitle: data['title'] as String,
            editedNotes: notes,
            categoryId: categoryId,
            latitude: latitude,
            longitude: longitude,
            fromOverlay: false,
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
      
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => TransactionForm(
            initialTitle: title,
            initialAmount: amount,
            initialType: type == 'income' ? TransactionType.income : TransactionType.expense,
            initialNotes: 'Transaction Code: $transactionCode',
            initialMpesaCode: transactionCode,
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
      
      // Close app after returning from form
      print('Returned from transaction form - closing app...');
      await Future.delayed(const Duration(milliseconds: 300));
      await _closeApp();
      
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