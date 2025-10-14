// lib/widgets/mpesa/comprehensive_pending_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/mpesa_transaction.dart';
import '../../models/transaction.dart';
import '../../models/category.dart';
import '../../services/mpesa_parser.dart';
import '../common/status_app_bar.dart';
import '../transactions/transaction_form.dart';

class ComprehensivePendingPage extends StatefulWidget {
  const ComprehensivePendingPage({super.key});

  @override
  State<ComprehensivePendingPage> createState() => _ComprehensivePendingPageState();
}

class _ComprehensivePendingPageState extends State<ComprehensivePendingPage> {
  List<PendingTransactionItem> _pendingTransactions = [];
  bool _isLoading = true;
  bool _hasPermission = false;
  String? _error;
  String _filterQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPendingTransactions();
  }

  Future<void> _loadPendingTransactions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Check SMS permission
      final status = await Permission.sms.status;
      if (!status.isGranted) {
        setState(() {
          _hasPermission = false;
          _isLoading = false;
        });
        return;
      }

      setState(() => _hasPermission = true);

      // Get all SMS messages
      final SmsQuery query = SmsQuery();
      final allMessages = await query.querySms(
        kinds: [SmsQueryKind.inbox],
        count: 1000,
      );

      // Filter for MPESA messages
      final mpesaMessages = allMessages.where((message) {
        final sender = message.address?.toUpperCase() ?? '';
        final body = message.body?.toUpperCase() ?? '';
        return sender.contains('MPESA') || 
               sender.contains('M-PESA') ||
               body.contains('MPESA') ||
               body.contains('M-PESA');
      }).toList();

      // Process each message and check if it exists in database
      List<PendingTransactionItem> pending = [];
      
      for (var message in mpesaMessages) {
        final body = message.body ?? '';
        final parsedData = EnhancedMpesaParser.parse(body);
        
        if (parsedData == null) continue;

        // Check if exists in mpesa_transactions table
        final existsInMpesa = await MpesaTransaction.exists(parsedData.transactionCode);
        
        // Check if exists in transactions table (by searching notes for transaction code)
        final existsInTransactions = await _existsInTransactionsTable(parsedData.transactionCode);

        // If doesn't exist in either table, it's pending
        if (!existsInMpesa && !existsInTransactions) {
          pending.add(PendingTransactionItem(
            message: message,
            parsedData: parsedData,
          ));
        }
      }

      // Sort by date (newest first)
      pending.sort((a, b) {
        final dateA = a.message.date ?? DateTime.now();
        final dateB = b.message.date ?? DateTime.now();
        return dateB.compareTo(dateA);
      });

      setState(() {
        _pendingTransactions = pending;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<bool> _existsInTransactionsTable(String transactionCode) async {
    try {
      final transactions = await Transaction.watchUserTransactions().first;
      return transactions.any((t) => 
        t.notes != null && t.notes!.contains(transactionCode)
      );
    } catch (e) {
      return false;
    }
  }

  Future<void> _requestPermission() async {
    final status = await Permission.sms.request();
    if (status.isGranted) {
      await _loadPendingTransactions();
    } else if (status.isPermanentlyDenied) {
      _showOpenSettingsDialog();
    }
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
          'SMS permission is required to detect pending MPESA transactions. '
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

  List<PendingTransactionItem> get _filteredTransactions {
    if (_filterQuery.isEmpty) {
      return _pendingTransactions;
    }

    return _pendingTransactions.where((item) {
      final sender = item.message.address?.toLowerCase() ?? '';
      final body = item.message.body?.toLowerCase() ?? '';
      final code = item.parsedData.transactionCode.toLowerCase();
      final query = _filterQuery.toLowerCase();
      
      return sender.contains(query) || 
             body.contains(query) || 
             code.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const StatusAppBar(title: Text('Pending Transactions')),
      body: Column(
        children: [
          // Info Banner
          if (_hasPermission && !_isLoading) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: _pendingTransactions.isEmpty 
                  ? Colors.green.shade50 
                  : Colors.orange.shade50,
              child: Row(
                children: [
                  Icon(
                    _pendingTransactions.isEmpty 
                        ? Icons.check_circle 
                        : Icons.pending_actions,
                    color: _pendingTransactions.isEmpty 
                        ? Colors.green.shade700 
                        : Colors.orange.shade700,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _pendingTransactions.isEmpty
                              ? 'All Caught Up!'
                              : '${_pendingTransactions.length} Pending ${_pendingTransactions.length == 1 ? 'Transaction' : 'Transactions'}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _pendingTransactions.isEmpty 
                                ? Colors.green.shade900 
                                : Colors.orange.shade900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _pendingTransactions.isEmpty
                              ? 'No unrecorded MPESA transactions found'
                              : 'These SMS messages haven\'t been recorded yet',
                          style: TextStyle(
                            fontSize: 12,
                            color: _pendingTransactions.isEmpty 
                                ? Colors.green.shade700 
                                : Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Search Bar
          if (_hasPermission && _pendingTransactions.isNotEmpty) ...[
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
                  hintText: 'Search transactions...',
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
            Text('Scanning SMS for pending transactions...'),
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
              onPressed: _loadPendingTransactions,
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
                'To detect pending MPESA transactions from SMS, please grant SMS permission.',
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

    if (_filteredTransactions.isEmpty) {
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
                    ? 'All your MPESA transactions have been recorded'
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
      onRefresh: _loadPendingTransactions,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _filteredTransactions.length,
        itemBuilder: (context, index) {
          final item = _filteredTransactions[index];
          return _PendingTransactionCard(
            item: item,
            onProcess: () => _processTransaction(item),
            onDismiss: () => _dismissTransaction(item),
          );
        },
      ),
    );
  }

  Future<void> _processTransaction(PendingTransactionItem item) async {
    try {
      // Show loading
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
                  Text('Processing transaction...'),
                ],
              ),
            ),
          ),
        ),
      );

      // Create MPESA transaction
      final mpesaTx = await MpesaTransaction.create(
        transactionCode: item.parsedData.transactionCode,
        transactionType: item.parsedData.transactionType,
        amount: item.parsedData.amount,
        counterpartyName: item.parsedData.counterpartyName,
        counterpartyNumber: item.parsedData.counterpartyNumber,
        transactionDate: item.parsedData.transactionDate,
        newBalance: item.parsedData.newBalance,
        transactionCost: item.parsedData.transactionCost,
        isDebit: item.parsedData.isDebit,
        rawMessage: item.parsedData.rawMessage,
        notes: EnhancedMpesaParser.generateNotes(item.parsedData),
      );

      // Get or create MPESA category
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

      // Create regular transaction
      await Transaction.create(
        title: item.parsedData.counterpartyName,
        amount: item.parsedData.amount,
        type: item.parsedData.isDebit ? TransactionType.expense : TransactionType.income,
        categoryId: mpesaCategory.id,
        date: item.parsedData.transactionDate,
        notes: EnhancedMpesaParser.generateNotes(item.parsedData),
      );

      // Link them
      // Note: You'll need to implement the linking mechanism

      // Reload pending transactions
      await _loadPendingTransactions();

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transaction processed successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _dismissTransaction(PendingTransactionItem item) async {
    // You could implement a dismiss mechanism here if needed
    // For now, just show a message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Transaction dismissed'),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

class PendingTransactionItem {
  final SmsMessage message;
  final MpesaTransactionData parsedData;

  PendingTransactionItem({
    required this.message,
    required this.parsedData,
  });
}

class _PendingTransactionCard extends StatelessWidget {
  final PendingTransactionItem item;
  final VoidCallback onProcess;
  final VoidCallback onDismiss;

  const _PendingTransactionCard({
    required this.item,
    required this.onProcess,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isIncome = !item.parsedData.isDebit;
    final color = isIncome ? Colors.green : Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: InkWell(
        onTap: () => _showDetails(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isIncome ? Icons.arrow_downward : Icons.arrow_upward,
                      color: color,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          EnhancedMpesaParser.getTransactionDescription(item.parsedData),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.parsedData.transactionCode,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    'KES ${NumberFormat('#,##0.00').format(item.parsedData.amount)}',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('MMM dd, yyyy • h:mm a').format(
                      item.message.date ?? DateTime.now(),
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: onDismiss,
                    child: const Text('Dismiss'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: onProcess,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDetails(BuildContext context) {
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
                const Text(
                  'Transaction Details',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                _buildDetailRow('Code', item.parsedData.transactionCode),
                _buildDetailRow('Type', item.parsedData.transactionType.name.toUpperCase()),
                _buildDetailRow('Amount', 'KES ${NumberFormat('#,##0.00').format(item.parsedData.amount)}'),
                _buildDetailRow('Counterparty', item.parsedData.counterpartyName),
                if (item.parsedData.counterpartyNumber != null)
                  _buildDetailRow('Number', item.parsedData.counterpartyNumber!),
                _buildDetailRow('New Balance', 'KES ${NumberFormat('#,##0.00').format(item.parsedData.newBalance)}'),
                if (item.parsedData.transactionCost > 0)
                  _buildDetailRow('Fee', 'KES ${NumberFormat('#,##0.00').format(item.parsedData.transactionCost)}'),
                const SizedBox(height: 24),
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
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    item.parsedData.rawMessage,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          onDismiss();
                        },
                        child: const Text('Dismiss'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          onProcess();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Add Transaction'),
                      ),
                    ),
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
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}