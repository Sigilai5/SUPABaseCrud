// lib/widgets/sms/sms_messages_page.dart
// FIXED VERSION - Properly cross-checks with discarded_mpesa table

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import '../common/status_app_bar.dart';
import '../../powersync.dart';
import '../transactions/transaction_form.dart';
import '../../models/transaction.dart';
import '../../models/discarded_mpesa.dart';
import '../../services/user_preferences.dart';

// Supported MPESA transaction types
enum SupportedMpesaType {
  till,
  send,
  received,
  paybill,
}

class ParsedMpesaMessage {
  final String transactionCode;
  final SupportedMpesaType type;
  final double amount;
  final String counterpartyName;
  final String? counterpartyNumber;
  final DateTime transactionDate;
  final bool isDebit;
  final String rawMessage;

  ParsedMpesaMessage({
    required this.transactionCode,
    required this.type,
    required this.amount,
    required this.counterpartyName,
    this.counterpartyNumber,
    required this.transactionDate,
    required this.isDebit,
    required this.rawMessage,
  });

  String get displayName {
    switch (type) {
      case SupportedMpesaType.send:
        return 'Sent to $counterpartyName';
      case SupportedMpesaType.till:
        return 'Paid to $counterpartyName';
      case SupportedMpesaType.paybill:
        return 'Paybill: $counterpartyName';
      case SupportedMpesaType.received:
        return 'Received from $counterpartyName';
    }
  }

  String get typeLabel {
    switch (type) {
      case SupportedMpesaType.send:
        return 'SEND MONEY';
      case SupportedMpesaType.till:
        return 'TILL';
      case SupportedMpesaType.paybill:
        return 'PAYBILL';
      case SupportedMpesaType.received:
        return 'RECEIVED';
    }
  }

  Color get typeColor {
    switch (type) {
      case SupportedMpesaType.send:
        return Colors.blue;
      case SupportedMpesaType.till:
        return Colors.orange;
      case SupportedMpesaType.paybill:
        return Colors.teal;
      case SupportedMpesaType.received:
        return Colors.green;
    }
  }
}

class SmsMessagesPage extends StatefulWidget {
  const SmsMessagesPage({super.key});

  @override
  State<SmsMessagesPage> createState() => _SmsMessagesPageState();
}

class _SmsMessagesPageState extends State<SmsMessagesPage> {
  List<ParsedMpesaMessage> _allMessages = [];
  List<ParsedMpesaMessage> _pendingMessages = [];
  bool _isLoading = true;
  bool _hasPermission = false;
  String? _error;
  String _filterQuery = '';
  final TextEditingController _searchController = TextEditingController();
  DateTime? _userCreatedAt;

  @override
  void initState() {
    super.initState();
    _getStartAfreshTime();
  }

  Future<void> _getStartAfreshTime() async {
    try {
      print('=== Getting Tracking Start Time ===');
      
      final startTime = await UserPreferences.getFirstTransactionTime();
      
      if (startTime != null) {
        setState(() {
          _userCreatedAt = startTime;
        });
        print('✓ Tracking start time: $_userCreatedAt');
      } else {
        setState(() {
          _userCreatedAt = DateTime.now();
        });
        await UserPreferences.setFirstTransactionTime(_userCreatedAt!);
        print('✓ Set initial tracking time: $_userCreatedAt');
      }
      
      await _checkPermissionAndLoadMessages();
    } catch (e, stackTrace) {
      print('✗ Error getting tracking start time: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _userCreatedAt = DateTime.now();
      });
      await _checkPermissionAndLoadMessages();
    }
  }

  Future<void> _checkPermissionAndLoadMessages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final status = await Permission.sms.status;
      
      if (status.isGranted) {
        setState(() => _hasPermission = true);
        await _loadMessages();
      } else {
        setState(() {
          _hasPermission = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _requestPermission() async {
    final status = await Permission.sms.request();
    
    if (status.isGranted) {
      setState(() => _hasPermission = true);
      await _loadMessages();
    } else if (status.isPermanentlyDenied) {
      if (mounted) {
        _showOpenSettingsDialog();
      }
    }
  }

  ParsedMpesaMessage? _parseMpesaMessage(String message) {
    try {
      final cleanMessage = message.replaceAll(RegExp(r'\s+'), ' ').trim();
      
      final codeMatch = RegExp(r'^([A-Z0-9]{10})').firstMatch(cleanMessage);
      if (codeMatch == null) return null;
      final transactionCode = codeMatch.group(1)!;

      final amountMatch = RegExp(r'Ksh([\d,]+\.?\d*)').firstMatch(cleanMessage);
      if (amountMatch == null) return null;
      final amount = double.parse(amountMatch.group(1)!.replaceAll(',', ''));

      final dateMatch = RegExp(r'on (\d{1,2}/\d{1,2}/\d{2}) at (\d{1,2}:\d{2} [AP]M)').firstMatch(cleanMessage);
      DateTime transactionDate = DateTime.now();
      
      if (dateMatch != null) {
        try {
          final dateStr = dateMatch.group(1)!;
          final timeStr = dateMatch.group(2)!;
          
          final dateParts = dateStr.split('/');
          final day = int.parse(dateParts[0]);
          final month = int.parse(dateParts[1]);
          final year = 2000 + int.parse(dateParts[2]);
          
          final timeParts = timeStr.split(' ');
          final hourMinute = timeParts[0].split(':');
          int hour = int.parse(hourMinute[0]);
          final minute = int.parse(hourMinute[1]);
          final isPM = timeParts[1] == 'PM';
          
          if (isPM && hour != 12) hour += 12;
          else if (!isPM && hour == 12) hour = 0;
          
          transactionDate = DateTime(year, month, day, hour, minute);
        } catch (e) {
          print('Error parsing date/time: $e');
        }
      }

      SupportedMpesaType? type;
      String counterpartyName;
      String? counterpartyNumber;
      bool isDebit;

      if (cleanMessage.contains('You have received')) {
        type = SupportedMpesaType.received;
        final nameMatch = RegExp(r'from ([A-Z\s]+) (\d+)').firstMatch(cleanMessage);
        counterpartyName = nameMatch?.group(1)?.trim() ?? 'Unknown';
        counterpartyNumber = nameMatch?.group(2);
        isDebit = false;

      } else if (cleanMessage.contains('sent to') && !cleanMessage.contains('paid to')) {
        if (cleanMessage.contains('Sign up for Lipa Na M-PESA Till')) {
          return null;
        }
        
        type = SupportedMpesaType.send;
        final nameMatch = RegExp(r'sent to ([A-Za-z\s]+) (\d+)').firstMatch(cleanMessage);
        if (nameMatch != null) {
          counterpartyName = nameMatch.group(1)?.trim() ?? 'Unknown';
          counterpartyNumber = nameMatch.group(2);
        } else {
          final altMatch = RegExp(r'sent to ([A-Z\s]+)').firstMatch(cleanMessage);
          counterpartyName = altMatch?.group(1)?.trim() ?? 'Unknown';
          counterpartyNumber = null;
        }
        isDebit = true;

      } else if (cleanMessage.contains('paid to')) {
        type = SupportedMpesaType.till;
        final nameMatch = RegExp(r'paid to ([A-Z\s.&]+?)\.').firstMatch(cleanMessage);
        counterpartyName = nameMatch?.group(1)?.trim() ?? 'Unknown';
        counterpartyNumber = null;
        isDebit = true;

      } else if (cleanMessage.contains('for account')) {
        type = SupportedMpesaType.paybill;
        final nameMatch = RegExp(r'sent to ([A-Za-z\s]+)\.?\s+for account').firstMatch(cleanMessage);
        counterpartyName = nameMatch?.group(1)?.trim() ?? 'Unknown';
        
        final accountMatch = RegExp(r'for account ([A-Z0-9]+)').firstMatch(cleanMessage);
        counterpartyNumber = accountMatch?.group(1);
        isDebit = true;

      } else {
        return null;
      }

      return ParsedMpesaMessage(
        transactionCode: transactionCode,
        type: type,
        amount: amount,
        counterpartyName: counterpartyName,
        counterpartyNumber: counterpartyNumber,
        transactionDate: transactionDate,
        isDebit: isDebit,
        rawMessage: message,
      );

    } catch (e) {
      print('Error parsing MPESA message: $e');
      return null;
    }
  }

  Future<void> _loadMessages() async {
    if (_userCreatedAt == null) {
      setState(() {
        _error = 'Could not determine tracking start time';
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final SmsQuery query = SmsQuery();
      
      print('=== Loading SMS Messages ===');
      print('Tracking started: ${DateFormat('MMM dd, yyyy h:mm:ss a').format(_userCreatedAt!)}');
      
      final allMessages = await query.querySms(
        kinds: [SmsQueryKind.inbox],
        count: 1000,
      );

      print('Total SMS: ${allMessages.length}');

      List<ParsedMpesaMessage> parsedMessages = [];
      int mpesaCount = 0;
      
      final normalizedStartTime = _userCreatedAt!.toLocal();
      
      for (var message in allMessages) {
        final sender = message.address?.toUpperCase() ?? '';
        final body = message.body ?? '';
        final messageDate = message.date;
        
        final isMpesa = sender.contains('MPESA') || 
                        sender.contains('M-PESA') ||
                        body.toUpperCase().contains('MPESA') ||
                        body.toUpperCase().contains('M-PESA') ||
                        sender.startsWith('MPESA');
        
        if (!isMpesa) continue;
        mpesaCount++;
        
        if (messageDate == null) continue;
        
        final normalizedMessageDate = messageDate.toLocal();
        if (!normalizedMessageDate.isAfter(normalizedStartTime)) continue;
        
        final parsed = _parseMpesaMessage(body);
        if (parsed != null) {
          parsedMessages.add(parsed);
        }
      }

      parsedMessages.sort((a, b) => b.transactionDate.compareTo(a.transactionDate));

      print('MPESA messages: $mpesaCount');
      print('Parsed: ${parsedMessages.length}');

      // ✅ CRITICAL FIX: Filter out recorded and discarded transactions
      final pending = await _filterPendingTransactions(parsedMessages);

      setState(() {
        _allMessages = parsedMessages;
        _pendingMessages = pending;
        _isLoading = false;
      });

      print('=== Summary ===');
      print('Total MPESA: ${parsedMessages.length}');
      print('Pending: ${pending.length}');
      print('Filtered out: ${parsedMessages.length - pending.length}');

    } catch (e, stackTrace) {
      print('✗ Error loading messages: $e');
      print('Stack trace: $stackTrace');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// ✅ CRITICAL FIX: Properly cross-check with discarded_mpesa table using transaction_code
  Future<List<ParsedMpesaMessage>> _filterPendingTransactions(
    List<ParsedMpesaMessage> messages,
  ) async {
    final userId = getUserId();
    if (userId == null) {
      print('⚠ User not logged in - cannot filter transactions');
      return messages;
    }

    final List<ParsedMpesaMessage> pending = [];
    
    print('=== Filtering ${messages.length} messages ===');
    print('User ID: $userId');
    
    for (var message in messages) {
      try {
        final code = message.transactionCode;
        
        // ✅ STEP 1: Check if recorded in transactions table
        final recordedResult = await db.getOptional('''
          SELECT COUNT(*) as count 
          FROM transactions 
          WHERE user_id = ? AND mpesa_code = ?
        ''', [userId, code]);
        
        final recordedCount = (recordedResult?['count'] as int? ?? 0);
        
        if (recordedCount > 0) {
          print('$code: ✓ RECORDED in transactions table (count: $recordedCount) - SKIPPING');
          continue;
        }

        // ✅ STEP 2: Check if discarded in discarded_mpesa table
        final discardedResult = await db.getOptional('''
          SELECT COUNT(*) as count 
          FROM discarded_mpesa 
          WHERE user_id = ? AND transaction_code = ?
        ''', [userId, code]);
        
        final discardedCount = (discardedResult?['count'] as int? ?? 0);
        
        if (discardedCount > 0) {
          print('$code: ✓ DISCARDED in discarded_mpesa table (count: $discardedCount) - SKIPPING');
          continue;
        }

        // ✅ STEP 3: Not recorded and not discarded = pending
        print('$code: ⏳ PENDING - adding to list');
        pending.add(message);
        
      } catch (e, stackTrace) {
        print('✗ Error checking ${message.transactionCode}: $e');
        print('Stack trace: $stackTrace');
        // On error, skip this transaction to be safe
        print('${message.transactionCode}: ERROR - skipping for safety');
      }
    }
    
    print('=== Filtering Complete ===');
    print('Total messages scanned: ${messages.length}');
    print('Pending transactions: ${pending.length}');
    print('Filtered out (recorded + discarded): ${messages.length - pending.length}');
    
    return pending;
  }

  void _showOpenSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.settings, color: Colors.orange),
            SizedBox(width: 8),
            Text('Permission Required'),
          ],
        ),
        content: const Text(
          'SMS permission was permanently denied. '
          'Please enable it in your device settings.\n\n'
          'Settings > Apps > Expense Tracker > Permissions > SMS',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  List<ParsedMpesaMessage> get _filteredPendingMessages {
    if (_filterQuery.isEmpty) {
      return _pendingMessages;
    }

    return _pendingMessages.where((message) {
      final code = message.transactionCode.toLowerCase();
      final name = message.counterpartyName.toLowerCase();
      final type = message.typeLabel.toLowerCase();
      final query = _filterQuery.toLowerCase();
      
      return code.contains(query) || name.contains(query) || type.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const StatusAppBar(title: Text('Pending MPESA Transactions')),
      body: Column(
        children: [
          if (_hasPermission && !_isLoading && _pendingMessages.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                border: Border(
                  bottom: BorderSide(color: Colors.orange.shade200),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.pending_actions, 
                      size: 24, 
                      color: Colors.orange.shade700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_pendingMessages.length} Pending ${_pendingMessages.length == 1 ? 'Transaction' : 'Transactions'}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap any transaction to add it',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    color: Colors.orange.shade700,
                    onPressed: _getStartAfreshTime,
                    tooltip: 'Refresh',
                  ),
                ],
              ),
            ),
          ],

          if (_hasPermission && !_isLoading && _userCreatedAt != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.blue.shade50,
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Showing MPESA since ${DateFormat('MMM dd, yyyy h:mm a').format(_userCreatedAt!)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (_hasPermission && _pendingMessages.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search pending transactions...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _filterQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _filterQuery = '');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
                onChanged: (value) {
                  setState(() => _filterQuery = value);
                },
              ),
            ),
          ],

          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading pending transactions...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Error: $_error',
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _getStartAfreshTime,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (!_hasPermission) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.message,
                size: 80,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 24),
              Text(
                'SMS Permission Required',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'To detect pending MPESA transactions, please grant SMS permission.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _requestPermission,
                icon: const Icon(Icons.security),
                label: const Text('Grant Permission'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredPendingMessages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _filterQuery.isEmpty ? Icons.check_circle : Icons.search_off,
              size: 64,
              color: _filterQuery.isEmpty ? Colors.green[300] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _filterQuery.isEmpty
                  ? 'All Caught Up!'
                  : 'No Results Found',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _filterQuery.isEmpty
                    ? 'All MPESA transactions recorded or discarded'
                    : 'No pending transactions match your search',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ),
            if (_filterQuery.isNotEmpty) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _filterQuery = '');
                },
                child: const Text('Clear Search'),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _getStartAfreshTime(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredPendingMessages.length,
        itemBuilder: (context, index) {
          final message = _filteredPendingMessages[index];
          return _buildPendingCard(message);
        },
      ),
    );
  }

  Widget _buildPendingCard(ParsedMpesaMessage message) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 3,
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => _navigateToAddTransaction(message),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: message.typeColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getIconForType(message.type),
                      color: message.typeColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: message.typeColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            message.typeLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          message.displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${message.transactionCode} • ${DateFormat('MMM dd, h:mm a').format(message.transactionDate)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'KES ${NumberFormat('#,##0.00').format(message.amount)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: message.isDebit ? Colors.red.shade700 : Colors.green.shade700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Icon(
                        Icons.add_circle,
                        size: 18,
                        color: Colors.orange.shade700,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _showDiscardConfirmation(message),
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('Discard'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () => _navigateToAddTransaction(message),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Transaction'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showDiscardConfirmation(ParsedMpesaMessage message) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
            const SizedBox(width: 12),
            const Text('Discard Transaction?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Are you sure you want to discard this transaction?',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: message.typeColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          message.typeLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          message.displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        message.transactionCode,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[700],
                          fontFamily: 'monospace',
                        ),
                      ),
                      Text(
                        'KES ${NumberFormat('#,##0.00').format(message.amount)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: message.isDebit ? Colors.red : Colors.green,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'This will be permanently marked as discarded and won\'t appear again.',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _discardTransaction(message);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes, Discard'),
          ),
        ],
      ),
    );
  }

  /// ✅ Debug helper: Check if transaction is in discarded_mpesa table
  Future<void> _debugCheckDiscardedStatus(String transactionCode) async {
    try {
      final userId = getUserId();
      if (userId == null) {
        print('DEBUG: User not logged in');
        return;
      }
      
      print('=== DEBUG: Checking Discarded Status ===');
      print('Transaction Code: $transactionCode');
      print('User ID: $userId');
      
      final result = await db.getOptional('''
        SELECT * FROM discarded_mpesa 
        WHERE user_id = ? AND transaction_code = ?
      ''', [userId, transactionCode]);
      
      if (result != null) {
        print('✓ FOUND in discarded_mpesa table:');
        print('  - ID: ${result['id']}');
        print('  - Amount: ${result['amount']}');
        print('  - Discarded At: ${result['discarded_at']}');
        print('  - Reason: ${result['discard_reason']}');
      } else {
        print('✗ NOT FOUND in discarded_mpesa table');
      }
      
      // Also check transactions table
      final txResult = await db.getOptional('''
        SELECT * FROM transactions 
        WHERE user_id = ? AND mpesa_code = ?
      ''', [userId, transactionCode]);
      
      if (txResult != null) {
        print('✓ FOUND in transactions table:');
        print('  - ID: ${txResult['id']}');
        print('  - Title: ${txResult['title']}');
        print('  - Amount: ${txResult['amount']}');
      } else {
        print('✗ NOT FOUND in transactions table');
      }
      
      print('=== DEBUG: Check Complete ===');
    } catch (e) {
      print('DEBUG ERROR: $e');
    }
  }

  /// ✅ FIXED: Properly discard and immediately refresh with better error handling
Future<void> _discardTransaction(ParsedMpesaMessage message) async {
  try {
    print('=== Discarding Transaction ===');
    print('Code: ${message.transactionCode}');
    print('User ID: ${getUserId()}');
    
    // Get user ID first
    final userId = getUserId();
    if (userId == null) {
      throw Exception('User not logged in');
    }
    
    // ✅ CRITICAL: First check if already discarded (prevent duplicates)
    final alreadyDiscarded = await db.getOptional('''
      SELECT COUNT(*) as count 
      FROM discarded_mpesa 
      WHERE user_id = ? AND transaction_code = ?
    ''', [userId, message.transactionCode]);
    
    final existingCount = (alreadyDiscarded?['count'] as int? ?? 0);
    if (existingCount > 0) {
      print('⚠ Transaction ${message.transactionCode} already discarded');
      
      // Just remove from UI and reload
      if (mounted) {
        setState(() {
          _pendingMessages.removeWhere((m) => m.transactionCode == message.transactionCode);
        });
        await _loadMessages();
      }
      return;
    }
    
    // Save to discarded_mpesa table
    final discarded = await DiscardedMpesa.create(
      transactionCode: message.transactionCode,
      transactionType: message.type.name.toUpperCase(),
      amount: message.amount,
      counterpartyName: message.counterpartyName,
      counterpartyNumber: message.counterpartyNumber,
      transactionDate: message.transactionDate,
      isDebit: message.isDebit,
      rawMessage: message.rawMessage,
      discardReason: 'User discarded from pending list',
    );

    print('✓ Transaction saved to discarded_mpesa table with ID: ${discarded.id}');

    // ✅ CRITICAL: Wait longer for database commit
    await Future.delayed(const Duration(milliseconds: 500));
    
    // ✅ Verify it was actually saved with retry logic
    int retries = 0;
    const maxRetries = 5;
    bool verified = false;
    
    while (retries < maxRetries && !verified) {
      final verifyResult = await db.getOptional('''
        SELECT COUNT(*) as count 
        FROM discarded_mpesa 
        WHERE user_id = ? AND transaction_code = ?
      ''', [userId, message.transactionCode]);
      
      final count = (verifyResult?['count'] as int? ?? 0);
      print('Verification attempt ${retries + 1}: Found $count entry');
      
      if (count > 0) {
        verified = true;
        print('✓ Verification successful!');
        break;
      }
      
      retries++;
      if (retries < maxRetries) {
        await Future.delayed(Duration(milliseconds: 100 * retries));
      }
    }
    
    if (!verified) {
      throw Exception('Transaction was not saved to discarded_mpesa table after $maxRetries attempts');
    }

    if (!mounted) return;
    
    // ✅ Remove from current pending list immediately (optimistic update)
    setState(() {
      _pendingMessages.removeWhere((m) => m.transactionCode == message.transactionCode);
    });
    
    print('✓ Removed from UI pending list');

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Transaction discarded: ${message.transactionCode}',
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );

    // ✅ CRITICAL: Force a complete reload to ensure UI is in sync
    print('Forcing complete reload after discard...');
    await _getStartAfreshTime(); // This will reload everything from scratch
    print('✓ Complete reload finished');
    
  } catch (e, stackTrace) {
    print('✗ Error discarding transaction: $e');
    print('Stack trace: $stackTrace');
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Error discarding transaction',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                e.toString(),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () => _discardTransaction(message),
          ),
        ),
      );
      
      // Force reload to restore correct UI state
      await _getStartAfreshTime();
    }
  }
}

  IconData _getIconForType(SupportedMpesaType type) {
    switch (type) {
      case SupportedMpesaType.send:
        return Icons.send;
      case SupportedMpesaType.till:
        return Icons.store;
      case SupportedMpesaType.paybill:
        return Icons.account_balance;
      case SupportedMpesaType.received:
        return Icons.call_received;
    }
  }

  void _navigateToAddTransaction(ParsedMpesaMessage message) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TransactionForm(
          initialTitle: message.displayName,
          initialAmount: message.amount,
          initialType: message.isDebit ? TransactionType.expense : TransactionType.income,
          initialNotes: 'MPESA ${message.typeLabel}\nCode: ${message.transactionCode}\nDate: ${DateFormat('MMM dd, yyyy h:mm a').format(message.transactionDate)}',
          initialMpesaCode: message.transactionCode,
        ),
      ),
    ).then((_) {
      _loadMessages();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}