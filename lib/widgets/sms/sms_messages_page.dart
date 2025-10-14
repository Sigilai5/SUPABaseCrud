// lib/widgets/sms/sms_messages_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../common/status_app_bar.dart';
import '../../models/mpesa_transaction.dart';
import '../../services/mpesa_parser.dart';
import '../../models/category.dart';
import '../../models/transaction.dart';

class SmsMessagesPage extends StatefulWidget {
  const SmsMessagesPage({super.key});

  @override
  State<SmsMessagesPage> createState() => _SmsMessagesPageState();
}

class _SmsMessagesPageState extends State<SmsMessagesPage> {
  List<SmsMessage> _messages = [];
  Map<String, bool> _transactionExists = {}; // Track if transaction code exists
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
      final filteredMessages = allMessages.where((message) {
        final sender = message.address?.toUpperCase() ?? '';
        final body = message.body?.toUpperCase() ?? '';
        final isMpesa = sender.contains('MPESA') || 
                        sender.contains('M-PESA') ||
                        body.contains('MPESA') ||
                        body.contains('M-PESA') ||
                        sender.startsWith('MPESA');
        
        final messageDate = message.date;
        final isAfterCreation = messageDate != null && 
                                messageDate.isAfter(_userCreatedAt!);
        
        return isMpesa && isAfterCreation;
      }).toList();

      filteredMessages.sort((a, b) {
        final dateA = a.date ?? DateTime.now();
        final dateB = b.date ?? DateTime.now();
        return dateB.compareTo(dateA);
      });

      print('Filtered MPESA messages: ${filteredMessages.length}');

      // Check which transactions already exist in database
      await _checkTransactionExistence(filteredMessages);

      setState(() {
        _messages = filteredMessages;
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

  Future<void> _checkTransactionExistence(List<SmsMessage> messages) async {
    final Map<String, bool> existenceMap = {};
    
    for (var message in messages) {
      final body = message.body ?? '';
      final parsedData = EnhancedMpesaParser.parse(body);
      
      if (parsedData != null) {
        final exists = await MpesaTransaction.exists(parsedData.transactionCode);
        existenceMap[parsedData.transactionCode] = exists;
        print('Transaction ${parsedData.transactionCode}: ${exists ? "EXISTS" : "PENDING"}');
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

  List<SmsMessage> get _filteredMessages {
    if (_filterQuery.isEmpty) {
      return _messages;
    }

    return _messages.where((message) {
      final sender = message.address?.toLowerCase() ?? '';
      final body = message.body?.toLowerCase() ?? '';
      final query = _filterQuery.toLowerCase();
      
      return sender.contains(query) || body.contains(query);
    }).toList();
  }

  int get _pendingCount {
    int count = 0;
    for (var message in _messages) {
      final body = message.body ?? '';
      final parsedData = EnhancedMpesaParser.parse(body);
      
      if (parsedData != null) {
        final exists = _transactionExists[parsedData.transactionCode] ?? false;
        if (!exists) count++;
      }
    }
    return count;
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
              color: Colors.green.shade50,
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: Colors.green.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Showing MPESA messages since ${DateFormat('MMM dd, yyyy').format(_userCreatedAt!)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade900,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (_pendingCount > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            '$_pendingCount pending ${_pendingCount == 1 ? 'transaction' : 'transactions'} not yet recorded',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.orange.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Search bar
          if (_hasPermission) ...[
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
                  hintText: 'Search MPESA messages...',
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

          // Summary bar
          if (_hasPermission && !_isLoading) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.blue.shade50,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_filteredMessages.length} MPESA ${_filteredMessages.length == 1 ? 'message' : 'messages'}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _loadMessages,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue.shade700,
                    ),
                  ),
                ],
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
                  'No MPESA messages received since ${DateFormat('MMM dd, yyyy').format(_userCreatedAt!)}',
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
          return _buildMessageCard(message);
        },
      ),
    );
  }

  Widget _buildMessageCard(SmsMessage message) {
    final sender = message.address ?? 'Unknown';
    final body = message.body ?? '';
    final date = message.date ?? DateTime.now();
    
    // Parse the message to get transaction code
    final parsedData = EnhancedMpesaParser.parse(body);
    final isPending = parsedData != null && 
                      !(_transactionExists[parsedData.transactionCode] ?? false);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isPending ? 3 : 1,
      color: isPending ? Colors.orange.shade50 : Colors.green.shade50,
      child: InkWell(
        onTap: () => _showMessageDetails(message, parsedData, isPending),
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
                      color: isPending 
                          ? Colors.orange.withOpacity(0.2)
                          : Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isPending ? Icons.pending_actions : Icons.check_circle,
                      color: isPending ? Colors.orange : Colors.green,
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
                            Expanded(
                              child: Text(
                                sender,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('MMM dd, yyyy • h:mm a').format(date),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (parsedData != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '${parsedData.transactionCode} • KES ${NumberFormat('#,##0.00').format(parsedData.amount)}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isPending ? Colors.orange.shade900 : Colors.green.shade900,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[800],
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessageDetails(SmsMessage message, MpesaTransactionData? parsedData, bool isPending) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          final sender = message.address ?? 'Unknown';
          final body = message.body ?? '';
          final date = message.date ?? DateTime.now();

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
                
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.call_received,
                        color: Colors.green,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MPESA Message',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            sender,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                
                if (parsedData != null) ...[
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
                        _buildDetailRow('Code', parsedData.transactionCode),
                        _buildDetailRow('Amount', 'KES ${NumberFormat('#,##0.00').format(parsedData.amount)}'),
                        _buildDetailRow('Type', parsedData.transactionType.name.toUpperCase()),
                        _buildDetailRow('Counterparty', parsedData.counterpartyName),
                        if (parsedData.counterpartyNumber != null)
                          _buildDetailRow('Number', parsedData.counterpartyNumber!),
                        _buildDetailRow('New Balance', 'KES ${NumberFormat('#,##0.00').format(parsedData.newBalance)}'),
                        if (parsedData.transactionCost > 0)
                          _buildDetailRow('Fee', 'KES ${NumberFormat('#,##0.00').format(parsedData.transactionCost)}'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          DateFormat('EEEE, MMMM dd, yyyy • h:mm:ss a').format(date),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                const Text(
                  'Original Message',
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
                    body,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: body));
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
                    if (isPending && parsedData != null) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            Navigator.pop(context);
                            await _addPendingTransaction(parsedData);
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

  Future<void> _addPendingTransaction(MpesaTransactionData parsedData) async {
    try {
      // Show loading
      if (!mounted) return;
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Adding transaction...'),
                ],
              ),
            ),
          ),
        ),
      );

      // Create MPESA transaction
      final mpesaTx = await MpesaTransaction.create(
        transactionCode: parsedData.transactionCode,
        transactionType: parsedData.transactionType,
        amount: parsedData.amount,
        counterpartyName: parsedData.counterpartyName,
        counterpartyNumber: parsedData.counterpartyNumber,
        transactionDate: parsedData
            .transactionDate,
        newBalance: parsedData.newBalance,
        transactionCost: parsedData.transactionCost,
        isDebit: parsedData.isDebit,
        rawMessage: parsedData.rawMessage,
        notes: 'Added from SMS import',
      );  
      print('MPESA transaction added: ${mpesaTx.id}');
      // Refresh messages to update status
      await _loadMessages();
      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaction added successfully'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('Error adding transaction: $e');
      if (!mounted) return;
      Navigator.pop(context); // Dismiss loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error adding transaction: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
