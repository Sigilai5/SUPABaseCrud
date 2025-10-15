// lib/widgets/debug/database_records_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../models/transaction.dart';
import '../../models/mpesa_transaction.dart';
import '../../models/category.dart';
import '../../powersync.dart';

import '../widgets/common/status_app_bar.dart';

class DatabaseRecordsPage extends StatefulWidget {
  const DatabaseRecordsPage({super.key});

  @override
  State<DatabaseRecordsPage> createState() => _DatabaseRecordsPageState();
}

class _DatabaseRecordsPageState extends State<DatabaseRecordsPage> {
  int _selectedIndex = 0;
  bool _isLoading = true;
  String? _error;
  
  List<Transaction> _transactions = [];
  List<MpesaTransaction> _mpesaTransactions = [];
  Map<String, Category> _categoryMap = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Load transactions
      final transactions = await Transaction.watchUserTransactions().first;
      
      // Load MPESA transactions
      final mpesaTransactions = await MpesaTransaction.watchUserTransactions().first;
      
      // Load categories
      final categories = await Category.watchUserCategories().first;
      final categoryMap = <String, Category>{};
      for (var cat in categories) {
        categoryMap[cat.id] = cat;
      }

      setState(() {
        _transactions = transactions;
        _mpesaTransactions = mpesaTransactions;
        _categoryMap = categoryMap;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const StatusAppBar(title: Text('Database Records')),
      body: Column(
        children: [
          // Tab selector
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
            child: Row(
              children: [
                Expanded(
                  child: _buildTabButton(
                    'Transactions',
                    _transactions.length,
                    0,
                    Icons.receipt_long,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildTabButton(
                    'MPESA',
                    _mpesaTransactions.length,
                    1,
                    Icons.phone_android,
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, size: 64, color: Colors.red),
                            const SizedBox(height: 16),
                            Text('Error: $_error'),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadData,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _selectedIndex == 0
                        ? _buildTransactionsView()
                        : _buildMpesaView(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadData,
        tooltip: 'Refresh',
        child: const Icon(Icons.refresh),
      ),
    );
  }

  Widget _buildTabButton(String label, int count, int index, IconData icon) {
    final isSelected = _selectedIndex == index;
    return InkWell(
      onTap: () => setState(() => _selectedIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : Colors.grey[700],
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? Colors.white.withOpacity(0.2) : Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey[700],
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsView() {
    if (_transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('No transactions found'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _transactions.length,
      itemBuilder: (context, index) {
        final transaction = _transactions[index];
        return _buildTransactionCard(transaction);
      },
    );
  }

  Widget _buildTransactionCard(Transaction transaction) {
    final category = _categoryMap[transaction.categoryId];
    final isIncome = transaction.type == TransactionType.income;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isIncome ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            isIncome ? Icons.arrow_downward : Icons.arrow_upward,
            color: isIncome ? Colors.green : Colors.red,
            size: 20,
          ),
        ),
        title: Text(
          transaction.title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'KES ${NumberFormat('#,##0.00').format(transaction.amount)}',
          style: TextStyle(
            color: isIncome ? Colors.green : Colors.red,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: FutureBuilder<bool>(
          future: transaction.hasLinkedMpesaTransaction(),
          builder: (context, snapshot) {
            if (snapshot.data == true) {
              return const Icon(
                Icons.link,
                color: Colors.green,
                size: 20,
              );
            }
            return const Icon(Icons.chevron_right);
          },
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('ID', transaction.id, canCopy: true),
                _buildDetailRow('User ID', transaction.userId, canCopy: true),
                _buildDetailRow('Amount', 'KES ${NumberFormat('#,##0.00').format(transaction.amount)}'),
                _buildDetailRow('Type', transaction.type.name.toUpperCase()),
                _buildDetailRow('Category', category?.name ?? 'Unknown'),
                _buildDetailRow('Category ID', transaction.categoryId, canCopy: true),
                if (transaction.budgetId != null)
                  _buildDetailRow('Budget ID', transaction.budgetId!, canCopy: true),
                _buildDetailRow(
                  'Date',
                  DateFormat('yyyy-MM-dd HH:mm:ss').format(transaction.date),
                ),
                if (transaction.notes != null)
                  _buildDetailRow('Notes', transaction.notes!),
                if (transaction.latitude != null && transaction.longitude != null)
                  _buildDetailRow(
                    'Location',
                    '${transaction.latitude}, ${transaction.longitude}',
                  ),
                _buildDetailRow(
                  'Created At',
                  DateFormat('yyyy-MM-dd HH:mm:ss').format(transaction.createdAt),
                ),
                _buildDetailRow(
                  'Updated At',
                  DateFormat('yyyy-MM-dd HH:mm:ss').format(transaction.updatedAt),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                FutureBuilder<List<MpesaTransaction>>(
                  future: transaction.getLinkedMpesaTransactions(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Linked MPESA Transactions:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...snapshot.data!.map((mpesa) => Container(
                            padding: const EdgeInsets.all(8),
                            margin: const EdgeInsets.only(bottom: 4),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.link, size: 16, color: Colors.green),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    mpesa.transactionCode,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )),
                        ],
                      );
                    }
                    return const Text(
                      'No linked MPESA transactions',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMpesaView() {
    if (_mpesaTransactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            const Text('No MPESA transactions found'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _mpesaTransactions.length,
      itemBuilder: (context, index) {
        final mpesa = _mpesaTransactions[index];
        return _buildMpesaCard(mpesa);
      },
    );
  }

  Widget _buildMpesaCard(MpesaTransaction mpesa) {
    final isIncome = !mpesa.isDebit;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: mpesa.isLinked() ? Colors.green.shade50 : Colors.orange.shade50,
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isIncome ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.phone_android,
            color: isIncome ? Colors.green : Colors.red,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                mpesa.transactionCode,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            if (mpesa.isLinked())
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.link, size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'LINKED',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'PENDING',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(
          'KES ${NumberFormat('#,##0.00').format(mpesa.amount)} • ${mpesa.counterpartyName}',
          style: TextStyle(
            color: isIncome ? Colors.green : Colors.red,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('ID', mpesa.id, canCopy: true),
                _buildDetailRow('User ID', mpesa.userId, canCopy: true),
                _buildDetailRow('Transaction Code', mpesa.transactionCode, canCopy: true),
                _buildDetailRow('Type', mpesa.transactionTypeString),
                _buildDetailRow('Amount', 'KES ${NumberFormat('#,##0.00').format(mpesa.amount)}'),
                _buildDetailRow('Counterparty Name', mpesa.counterpartyName),
                if (mpesa.counterpartyNumber != null)
                  _buildDetailRow('Counterparty Number', mpesa.counterpartyNumber!),
                _buildDetailRow(
                  'Transaction Date',
                  DateFormat('yyyy-MM-dd HH:mm:ss').format(mpesa.transactionDate),
                ),
                _buildDetailRow('New Balance', 'KES ${NumberFormat('#,##0.00').format(mpesa.newBalance)}'),
                _buildDetailRow('Transaction Cost', 'KES ${NumberFormat('#,##0.00').format(mpesa.transactionCost)}'),
                _buildDetailRow('Is Debit', mpesa.isDebit ? 'Yes (Money Out)' : 'No (Money In)'),
                if (mpesa.notes != null)
                  _buildDetailRow('Notes', mpesa.notes!),
                _buildDetailRow(
                  'Created At',
                  DateFormat('yyyy-MM-dd HH:mm:ss').format(mpesa.createdAt),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                
                // Linked Transaction ID
                if (mpesa.linkedTransactionId != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.link, size: 16, color: Colors.green),
                            SizedBox(width: 8),
                            Text(
                              'Linked Transaction ID:',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                mpesa.linkedTransactionId!,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 16),
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: mpesa.linkedTransactionId!),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Linked transaction ID copied'),
                                    duration: Duration(seconds: 1),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        FutureBuilder<Transaction?>(
                          future: mpesa.getLinkedTransaction(),
                          builder: (context, snapshot) {
                            if (snapshot.hasData && snapshot.data != null) {
                              final transaction = snapshot.data!;
                              return Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      transaction.title,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'KES ${NumberFormat('#,##0.00').format(transaction.amount)}',
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                              );
                            }
                            return const Text(
                              'Transaction not found',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.red,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade300),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.pending_actions, size: 16, color: Colors.orange),
                        SizedBox(width: 8),
                        Text(
                          'No linked transaction (PENDING)',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 12),
                
                // Raw Message
                const Text(
                  'Raw SMS Message:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    mpesa.rawMessage,
                    style: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool canCopy = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (canCopy)
                  IconButton(
                    icon: const Icon(Icons.copy, size: 14),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$label copied'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}