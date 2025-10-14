// // lib/services/sms_reader_service.dart
// import 'package:flutter/services.dart';
// import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
// import 'package:permission_handler/permission_handler.dart';
// import '../models/pending_mpesa.dart';
// import '../services/mpesa_parser.dart';
// import '../powersync.dart';
// import 'user_preferences.dart';

// /// Service to read and process MPESA SMS messages from multiple sources:
// /// 1. SMS Inbox - Messages that arrived after tracking started
// /// 2. SharedPreferences - Messages received when app was closed/phone was off
// class SmsReaderService {
//   static const String _tag = 'SmsReaderService';
//   static const MethodChannel _channel = MethodChannel('com.example.crud/mpesa');
  
//   /// Fetches MPESA messages from ALL sources:
//   /// - SMS Inbox: Messages after first transaction
//   /// - SharedPreferences: Messages received when app was off
//   /// 
//   /// Returns a list of PendingMpesa objects that need user review
//   static Future<List<PendingMpesa>> fetchPendingMpesaMessages() async {
//     print('$_tag: ========================================');
//     print('$_tag: Starting comprehensive pending scan...');
//     print('$_tag: ========================================');
    
//     // First, process any pending transactions from SharedPreferences
//     // These are messages received when the app was closed
//     await _processSharedPreferencesTransactions();
    
//     // Check if user has started tracking
//     final hasStarted = await UserPreferences.hasRecordedFirstTransaction();
    
//     if (!hasStarted) {
//       print('$_tag: User has not started tracking yet');
//       print('$_tag: Only SharedPreferences messages will be processed');
      
//       // Return whatever is in the pending_mpesa table
//       final pending = await PendingMpesa.watchUserPendingMessages().first;
//       print('$_tag: Total pending messages: ${pending.length}');
//       return pending;
//     }

//     // Check SMS permission for inbox scanning
//     final hasSms = await Permission.sms.status;
//     if (!hasSms.isGranted) {
//       print('$_tag: ✗ SMS permission not granted');
//       print('$_tag: Can only process SharedPreferences messages');
      
//       // Return whatever is in the pending_mpesa table
//       final pending = await PendingMpesa.watchUserPendingMessages().first;
//       print('$_tag: Total pending messages: ${pending.length}');
//       return pending;
//     }

//     print('$_tag: ✓ SMS permission granted');
//     print('$_tag: ✓ User has started tracking');
    
//     // Get the timestamp of first transaction
//     final firstTransactionTime = await UserPreferences.getFirstTransactionTime();
//     print('$_tag: First transaction at: $firstTransactionTime');
//     print('$_tag: Scanning SMS inbox for messages AFTER this time...');

//     // Scan SMS inbox for messages after tracking started
//     await _readMpesaMessagesAfter(firstTransactionTime!);
    
//     // Return all pending messages from database
//     final allPending = await PendingMpesa.watchUserPendingMessages().first;
//     print('$_tag: ========================================');
//     print('$_tag: TOTAL PENDING MESSAGES: ${allPending.length}');
//     print('$_tag: ========================================');
    
//     return allPending;
//   }

//   /// Processes pending transactions from SharedPreferences
//   /// These are MPESA messages received when the app was closed/phone was off
//   static Future<void> _processSharedPreferencesTransactions() async {
//     print('$_tag: --- Checking SharedPreferences ---');
    
//     try {
//       // Get pending transactions from SharedPreferences
//       final List<dynamic>? pendingList = await _channel.invokeMethod('getPendingTransactions');
      
//       if (pendingList == null || pendingList.isEmpty) {
//         print('$_tag: No messages in SharedPreferences');
//         return;
//       }
      
//       print('$_tag: Found ${pendingList.length} messages in SharedPreferences');
      
//       int addedCount = 0;
//       int skippedCount = 0;
      
//       for (var item in pendingList) {
//         try {
//           final Map<String, dynamic> data = Map<String, dynamic>.from(item);
          
//           final transactionCode = data['transactionCode'] as String;
//           print('$_tag: Processing SharedPrefs transaction: $transactionCode');
          
//           // Check if already in transactions table
//           final alreadyRecorded = await _isTransactionRecorded(transactionCode);
//           if (alreadyRecorded) {
//             print('$_tag: ⊘ Already recorded: $transactionCode');
//             skippedCount++;
//             continue;
//           }
          
//           // Check if already in pending_mpesa table
//           final alreadyPending = await _isAlreadyInPendingTable(transactionCode);
//           if (alreadyPending) {
//             print('$_tag: ⊘ Already in pending: $transactionCode');
//             skippedCount++;
//             continue;
//           }
          
//           // Add to pending_mpesa table
//           await PendingMpesa.create(
//             rawMessage: 'Auto-detected from SMS when app was closed',
//             sender: 'MPESA',
//             transactionCode: transactionCode,
//             amount: (data['amount'] as num?)?.toDouble(),
//             type: data['type'] as String?,
//             parsedTitle: data['title'] as String?,
//             receivedAt: DateTime.fromMillisecondsSinceEpoch(data['timestamp'] as int),
//           );
          
//           addedCount++;
//           print('$_tag: ✓ Added to pending: $transactionCode');
          
//         } catch (e) {
//           print('$_tag: ✗ Error processing SharedPrefs transaction: $e');
//         }
//       }
      
//       print('$_tag: SharedPreferences Summary:');
//       print('$_tag:   - Added to pending: $addedCount');
//       print('$_tag:   - Skipped (duplicate): $skippedCount');
      
//       // Clear SharedPreferences after processing
//       if (addedCount > 0) {
//         await _channel.invokeMethod('clearPendingTransactions');
//         print('$_tag: ✓ Cleared SharedPreferences');
//       }
      
//     } catch (e) {
//       print('$_tag: ✗ Error processing SharedPreferences: $e');
//     }
//   }

//   /// Reads all SMS messages that arrived after the given start time
//   /// and filters for MPESA messages
//   static Future<void> _readMpesaMessagesAfter(DateTime startTime) async {
//     print('$_tag: --- Scanning SMS Inbox ---');
    
//     try {
//       final SmsQuery query = SmsQuery();
      
//       print('$_tag: Querying SMS inbox...');
//       final messages = await query.querySms(
//         kinds: [SmsQueryKind.inbox],
//         count: 1000, // Adjust as needed - reads last 1000 messages
//       );

//       print('$_tag: Found ${messages.length} total SMS messages');

//       // Filter messages AFTER the start time
//       final filteredMessages = messages.where((msg) {
//         final messageDate = msg.date ?? DateTime.now();
//         return messageDate.isAfter(startTime);
//       }).toList();

//       print('$_tag: Found ${filteredMessages.length} messages AFTER tracking started');

//       await _filterAndParseMpesaMessages(filteredMessages);
//     } catch (e) {
//       print('$_tag: ✗ Error reading SMS inbox: $e');
//     }
//   }

//   /// Filters SMS messages to find MPESA transactions and creates PendingMpesa entries
//   static Future<void> _filterAndParseMpesaMessages(
//     List<SmsMessage> messages,
//   ) async {
//     int mpesaCount = 0;
//     int parsedCount = 0;
//     int alreadyRecordedCount = 0;
//     int alreadyPendingCount = 0;
//     int newPendingCount = 0;

//     for (var message in messages) {
//       final sender = message.address ?? 'Unknown';
//       final body = message.body ?? '';

//       // Check if it's an MPESA message
//       if (!_isMpesaMessage(sender, body)) continue;
      
//       mpesaCount++;

//       // Parse the message
//       final parsed = MpesaParser.parse(body);
//       if (parsed == null) {
//         print('$_tag: Could not parse MPESA message from $sender');
//         continue;
//       }
      
//       parsedCount++;

//       // Check if already recorded in transactions table
//       final alreadyRecorded = await _isTransactionRecorded(parsed.transactionCode);
//       if (alreadyRecorded) {
//         alreadyRecordedCount++;
//         continue;
//       }

//       // Check if already in pending_mpesa table
//       final alreadyPending = await _isAlreadyInPendingTable(parsed.transactionCode);
//       if (alreadyPending) {
//         alreadyPendingCount++;
//         continue;
//       }

//       // Create pending MPESA entry
//       try {
//         await PendingMpesa.create(
//           rawMessage: body,
//           sender: sender,
//           transactionCode: parsed.transactionCode,
//           amount: parsed.amount,
//           type: parsed.type,
//           parsedTitle: parsed.title,
//           receivedAt: message.date ?? DateTime.now(),
//         );
        
//         newPendingCount++;
//         print('$_tag: ✓ Added to pending: ${parsed.transactionCode}');
//       } catch (e) {
//         print('$_tag: ✗ Error creating pending MPESA: $e');
//       }
//     }

//     // Print SMS Inbox summary
//     print('$_tag: SMS Inbox Summary:');
//     print('$_tag:   - MPESA messages found: $mpesaCount');
//     print('$_tag:   - Successfully parsed: $parsedCount');
//     print('$_tag:   - Already recorded: $alreadyRecordedCount');
//     print('$_tag:   - Already pending: $alreadyPendingCount');
//     print('$_tag:   - NEW pending added: $newPendingCount');
//   }

//   /// Checks if a message is from MPESA based on sender and content
//   static bool _isMpesaMessage(String sender, String body) {
//     final senderUpper = sender.toUpperCase();
//     final bodyUpper = body.toUpperCase();
    
//     // Check various MPESA sender formats
//     if (senderUpper.contains('MPESA') || 
//         senderUpper.contains('M-PESA') ||
//         senderUpper.startsWith('MPESA')) {
//       return true;
//     }
    
//     // Check message content
//     if (bodyUpper.contains('MPESA') || 
//         bodyUpper.contains('M-PESA') ||
//         bodyUpper.contains('SAFARICOM')) {
//       return true;
//     }
    
//     return false;
//   }

//   /// Checks if a transaction with the given code has already been recorded
//   /// in the transactions table
//   static Future<bool> _isTransactionRecorded(String transactionCode) async {
//     final userId = getUserId();
//     if (userId == null) return false;

//     try {
//       final result = await db.getOptional('''
//         SELECT COUNT(*) as count FROM transactions 
//         WHERE user_id = ? AND notes LIKE ?
//       ''', [userId, '%$transactionCode%']);
      
//       final count = (result?['count'] as int?) ?? 0;
//       return count > 0;
//     } catch (e) {
//       print('$_tag: Error checking if transaction recorded: $e');
//       return false;
//     }
//   }

//   /// Checks if a transaction with the given code is already in the
//   /// pending_mpesa table
//   static Future<bool> _isAlreadyInPendingTable(String transactionCode) async {
//     final userId = getUserId();
//     if (userId == null) return false;

//     try {
//       final result = await db.getOptional('''
//         SELECT COUNT(*) as count FROM pending_mpesa 
//         WHERE user_id = ? AND transaction_code = ?
//       ''', [userId, transactionCode]);
      
//       final count = (result?['count'] as int?) ?? 0;
//       return count > 0;
//     } catch (e) {
//       print('$_tag: Error checking if already in pending table: $e');
//       return false;
//     }
//   }

//   /// Gets the count of pending MPESA messages for the current user
//   static Future<int> getPendingCount() async {
//     final userId = getUserId();
//     if (userId == null) return 0;

//     try {
//       final result = await db.getOptional('''
//         SELECT COUNT(*) as count FROM pending_mpesa 
//         WHERE user_id = ?
//       ''', [userId]);
      
//       final count = (result?['count'] as int?) ?? 0;
//       return count;
//     } catch (e) {
//       print('$_tag: Error getting pending count: $e');
//       return 0;
//     }
//   }

//   /// Clears all pending MPESA messages for the current user
//   /// Useful for testing or resetting the pending list
//   static Future<void> clearAllPending() async {
//     final userId = getUserId();
//     if (userId == null) return;

//     try {
//       await db.execute('''
//         DELETE FROM pending_mpesa WHERE user_id = ?
//       ''', [userId]);
      
//       print('$_tag: ✓ Cleared all pending MPESA messages');
//     } catch (e) {
//       print('$_tag: ✗ Error clearing pending messages: $e');
//       rethrow;
//     }
//   }

//   /// Checks if SMS permission is granted
//   static Future<bool> hasSmsPermission() async {
//     final status = await Permission.sms.status;
//     return status.isGranted;
//   }

//   /// Requests SMS permission from the user
//   static Future<bool> requestSmsPermission() async {
//     final status = await Permission.sms.request();
//     return status.isGranted;
//   }

//   /// Gets a user-friendly status message about pending messages
//   static Future<String> getPendingStatusMessage() async {
//     final hasStarted = await UserPreferences.hasRecordedFirstTransaction();
    
//     if (!hasStarted) {
//       return 'Not tracking yet. Record your first transaction to start.';
//     }
    
//     final count = await getPendingCount();
    
//     if (count == 0) {
//       return 'All caught up! No pending MPESA messages.';
//     }
    
//     return '$count pending MPESA ${count == 1 ? 'message' : 'messages'} to review';
//   }

//   /// Validates that all required permissions are granted
//   static Future<Map<String, bool>> checkAllPermissions() async {
//     final smsStatus = await Permission.sms.status;
    
//     return {
//       'sms': smsStatus.isGranted,
//     };
//   }

//   /// Gets detailed information about the SMS scanning capability
//   static Future<Map<String, dynamic>> getScanInfo() async {
//     final hasStarted = await UserPreferences.hasRecordedFirstTransaction();
//     final firstTransactionTime = await UserPreferences.getFirstTransactionTime();
//     final pendingCount = await getPendingCount();
//     final hasSms = await hasSmsPermission();
    
//     // Check SharedPreferences count
//     int sharedPrefsCount = 0;
//     try {
//       final List<dynamic>? pendingList = await _channel.invokeMethod('getPendingTransactions');
//       sharedPrefsCount = pendingList?.length ?? 0;
//     } catch (e) {
//       print('$_tag: Error getting SharedPrefs count: $e');
//     }
    
//     return {
//       'has_started_tracking': hasStarted,
//       'first_transaction_time': firstTransactionTime?.toIso8601String(),
//       'pending_count': pendingCount,
//       'shared_prefs_count': sharedPrefsCount,
//       'has_sms_permission': hasSms,
//       'can_scan': hasStarted && hasSms,
//     };
//   }
// }