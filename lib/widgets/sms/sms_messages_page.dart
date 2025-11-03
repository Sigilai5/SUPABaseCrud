// lib/widgets/sms/sms_messages_page.dart
// REORGANIZED VERSION - Focuses on MPESA Till, Send Money, Received, and Paybill only
// Checks against mpesa_code column in transactions table

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../common/status_app_bar.dart';
import '../../powersync.dart';
import '../transactions/transaction_form.dart';
import '../../models/transaction.dart';

// Supported MPESA transaction types only
enum SupportedMpesaType {
  till,      // Lipa Na MPESA Till
  send,      // Send Money to phone number
  received,  // Money Received
  paybill,   // Paybill payment
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
  List<ParsedMpesaMessage> _messages = [];
  Map<String, bool> _transactionExists = {}; // Track if mpesa_code exists in transactions table
  bool _isLoading = true;
  bool _hasPermission = false;
  String? _error;
  String _filterQuery = '';
  final TextEditingController _searchController = TextEditingController();
  DateTime? _userCreatedAt;

  @override
  void initState() {
    super.initState();
    _getUserCreationDate();
  }

  Future<void> _getUserCreationDate() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null && user.createdAt != null) {
        setState(() {
          _userCreatedAt = DateTime.parse(user.createdAt!);
        });
        print('User account created at: $_userCreatedAt');
      } else {
        setState(() {
          _userCreatedAt = DateTime.now();
        });
        print('User creation date not available, using current time');
      }
      await _checkPermissionAndLoadMessages();
    } catch (e) {
      print('Error getting user creation date: $e');
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
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SMS permission denied'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Parse MPESA SMS and filter for supported types only
  ParsedMpesaMessage? _parseMpesaMessage(String message) {
    try {
      final cleanMessage = message.replaceAll(RegExp(r'\s+'), ' ').trim();
      
      // Extract transaction code (always at start)
      final codeMatch = RegExp(r'^([A-Z0-9]{10})').firstMatch(cleanMessage);
      if (codeMatch == null) return null;
      final transactionCode = codeMatch.group(1)!;

      // Extract amount
      final amountMatch = RegExp(r'Ksh([\d,]+\.?\d*)').firstMatch(cleanMessage);
      if (amountMatch == null) return null;
      final amount = double.parse(amountMatch.group(1)!.replaceAll(',', ''));

      // Extract date and time
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

      // Determine transaction type - ONLY supported types
      SupportedMpesaType? type;
      String counterpartyName;
      String? counterpartyNumber;
      bool isDebit;

      if (cleanMessage.contains('You have received')) {
        // RECEIVED - INCOME
        type = SupportedMpesaType.received;
        final nameMatch = RegExp(r'from ([A-Z\s]+) (\d+)').firstMatch(cleanMessage);
        counterpartyName = nameMatch?.group(1)?.trim() ?? 'Unknown';
        counterpartyNumber = nameMatch?.group(2);
        isDebit = false;

      } else if (cleanMessage.contains('sent to') && !cleanMessage.contains('paid to')) {
        // Check if it's Pochi (skip it)
        if (cleanMessage.contains('Sign up for Lipa Na M-PESA Till')) {
          return null; // SKIP POCHI
        }
        
        // SEND MONEY
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
        // TILL
        type = SupportedMpesaType.till;
        final nameMatch = RegExp(r'paid to ([A-Z\s.&]+?)\.').firstMatch(cleanMessage);
        counterpartyName = nameMatch?.group(1)?.trim() ?? 'Unknown';
        counterpartyNumber = null;
        isDebit = true;

      } else if (cleanMessage.contains('for account')) {
        // PAYBILL
        type = SupportedMpesaType.paybill;
        final nameMatch = RegExp(r'sent to ([A-Za-z\s]+)\.?\s+for account').firstMatch(cleanMessage);
        counterpartyName = nameMatch?.group(1)?.trim() ?? 'Unknown';
        
        final accountMatch = RegExp(r'for account ([A-Z0-9]+)').firstMatch(cleanMessage);
        counterpartyNumber = accountMatch?.group(1);
        isDebit = true;

      } else {
        // Unsupported type - return null
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
      print('User creation date not available, cannot load messages');
      setState(() {
        _error = 'Could not determine account creation date';
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final SmsQuery query = SmsQuery();
      
      print('Loading SMS messages from ${_userCreatedAt!.toIso8601String()}');
      
      final allMessages = await query.querySms(
        kinds: [SmsQueryKind.inbox],
        count: 1000,
      );

      print('Total SMS messages found: ${allMessages.length}');

      // Filter for MPESA messages after user creation
      List<ParsedMpesaMessage> parsedMessages = [];
      
      for (var message in allMessages) {
        final sender = message.address?.toUpperCase() ?? '';
        final body = message.body ?? '';
        final messageDate = message.date;
        
        // Check if MPESA message
        final isMpesa = sender.contains('MPESA') || 
                        sender.contains('M-PESA') ||
                        body.toUpperCase().contains('MPESA') ||
                        body.toUpperCase().contains('M-PESA') ||
                        sender.startsWith('MPESA');
        
        if (!isMpesa) continue;
        
        // Check if after user creation
        final isAfterCreation = messageDate != null && 
                                messageDate.isAfter(_userCreatedAt!);
        
        if (!isAfterCreation) continue;
        
        // Parse and filter for supported types only
        final parsed = _parseMpesaMessage(body);
        if (parsed != null) {
          parsedMessages.add(parsed);
        }
      }

      // Sort by date (newest first)
      parsedMessages.sort((a, b) => b.transactionDate.compareTo(a.transactionDate));

      print('Filtered MPESA messages (supported types only): ${parsedMessages.length}');

      // Check which transactions already exist in database (by mpesa_code)
      await _checkTransactionExistence(parsedMessages);

      setState(() {
        _messages = parsedMessages;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading messages: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  /// Check if transaction codes exist in transactions table (mpesa_code column)
  Future<void> _checkTransactionExistence(List<ParsedMpesaMessage> messages) async {
    final Map<String, bool> existenceMap = {};
    final userId = getUserId();
    
    if (userId == null) {
      print('User not logged in');
      return;
    }
    
    for (var message in messages) {
      try {
        // Query transactions table for mpesa_code match
        final result = await db.getOptional('''
          SELECT COUNT(*) as count 
          FROM transactions 
          WHERE user_id = ? AND mpesa_code = ?
        ''', [userId, message.transactionCode]);
        
        final count = (result?['count'] as int?) ?? 0;
        final exists = count > 0;
        
        existenceMap[message.transactionCode] = exists;
        print('Transaction ${message.transactionCode}: ${exists ? "EXISTS" : "PENDING"}');
      } catch (e) {
        print('Error checking transaction ${message.transactionCode}: $e');
        existenceMap[message.transactionCode] = false;
      }
    }
    
    setState(() {
      _transactionExists = existenceMap;
    });
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
          'Please enable it in your device settings to view messages.\n\n'
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

  List<ParsedMpesaMessage> get _filteredMessages {
    if (_filterQuery.isEmpty) {
      return _messages;
    }

    return _messages.where((message) {
      final code = message.transactionCode.toLowerCase();
      final name = message.counterpartyName.toLowerCase();
      final type = message.typeLabel.toLowerCase();
      final query = _filterQuery.toLowerCase();
      
      return code.contains(query) || name.contains(query) || type.contains(query);
    }).toList();
  }

  int get _pendingCount {
    return _messages.where((msg) => 
      !(_transactionExists[msg.transactionCode] ?? false)
    ).length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const StatusAppBar(title: Text('MPESA Messages')),
      body: Column(
        children: [
          // Info banner
          if (_hasPermission && _userCreatedAt != null && !_isLoading) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.blue.shade50,
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: Colors.blue.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Showing: Till, Send Money, Received & Paybill',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Since ${DateFormat('MMM dd, yyyy').format(_userCreatedAt!)} • ${_messages.length} messages',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Pending count banner
          if (_hasPermission && !_isLoading && _pendingCount > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.orange.shade50,
              child: Row(
                children: [
                  Icon(Icons.pending_actions, size: 20, color: Colors.orange.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$_pendingCount pending ${_pendingCount == 1 ? 'transaction' : 'transactions'} not recorded',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _loadMessages,
                    child: const Text('Refresh'),
                  ),
                ],
              ),
            ),
          ],

          // Search bar
          if (_hasPermission && _messages.isNotEmpty) ...[
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
                  hintText: 'Search by code, name, or type...',
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

          // Content
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
            Text('Loading MPESA messages...'),
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
              onPressed: _getUserCreationDate,
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
                'This app needs permission to read SMS messages to display MPESA transactions.',
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

    if (_filteredMessages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _filterQuery.isEmpty ? Icons.inbox : Icons.search_off,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _filterQuery.isEmpty
                  ? 'No MPESA messages found'
                  : 'No messages match your search',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            if (_filterQuery.isEmpty && _userCreatedAt != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  'No supported MPESA messages (Till, Send, Received, Paybill) since ${DateFormat('MMM dd, yyyy').format(_userCreatedAt!)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[500],
                  ),
                ),
              ),
            ],
            if (_filterQuery.isNotEmpty) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _filterQuery = '');
                },
                child: const Text('Clear search'),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadMessages,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredMessages.length,
        itemBuilder: (context, index) {
          final message = _filteredMessages[index];
          final isPending = !(_transactionExists[message.transactionCode] ?? false);
          return _buildMessageCard(message, isPending);
        },
      ),
    );
  }

  Widget _buildMessageCard(ParsedMpesaMessage message, bool isPending) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isPending ? 3 : 1,
      color: isPending ? Colors.orange.shade50 : Colors.green.shade50,
      child: InkWell(
        onTap: () {
          if (isPending) {
            _navigateToAddTransaction(message);
          } else {
            _showMessageDetails(message, isPending);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
                        Row(
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
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isPending ? Colors.orange : Colors.green,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isPending ? 'PENDING' : 'RECORDED',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
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
                        isPending ? Icons.add_circle : Icons.check_circle,
                        size: 18,
                        color: isPending ? Colors.orange.shade700 : Colors.green.shade700,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
      // Refresh messages after adding transaction
      _loadMessages();
    });
  }

  void _showMessageDetails(ParsedMpesaMessage message, bool isPending) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isPending ? Colors.orange.shade100 : Colors.green.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPending ? Icons.pending_actions : Icons.check_circle,
                        size: 16,
                        color: isPending ? Colors.orange.shade700 : Colors.green.shade700,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isPending ? 'PENDING TRANSACTION' : 'ALREADY RECORDED',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isPending ? Colors.orange.shade900 : Colors.green.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Type Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: message.typeColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    message.typeLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Transaction Details
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Transaction Details',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildDetailRow('Code', message.transactionCode),
                      _buildDetailRow('Amount', 'KES ${NumberFormat('#,##0.00').format(message.amount)}'),
                      _buildDetailRow('Type', message.typeLabel),
                      _buildDetailRow('Counterparty', message.counterpartyName),
                      if (message.counterpartyNumber != null)
                        _buildDetailRow('Number', message.counterpartyNumber!),
                      _buildDetailRow(
                        'Date & Time',
                        DateFormat('EEEE, MMM dd, yyyy • h:mm a').format(message.transactionDate),
                      ),
                      _buildDetailRow(
                        'Direction',
                        message.isDebit ? 'Money Out (Expense)' : 'Money In (Income)',
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Original SMS
                const Text(
                  'Original SMS',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: SelectableText(
                    message.rawMessage,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: message.rawMessage));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Message copied to clipboard'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copy'),
                      ),
                    ),
                    if (isPending) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _navigateToAddTransaction(message);
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Transaction'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Close'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}