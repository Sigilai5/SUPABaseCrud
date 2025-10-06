import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/transaction.dart';
import '../../models/category.dart';
import 'transaction_form.dart';

class TransactionList extends StatelessWidget {
  const TransactionList({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            onPressed: () => _showAddTransaction(context),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: Column(
        children: [
          // Summary Cards
          _buildSummaryCards(),
          const Divider(height: 1),
          // Transaction List
          Expanded(
            child: StreamBuilder<List<Transaction>>(
              stream: Transaction.watchUserTransactions(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                final transactions = snapshot.data ?? [];
                
                if (transactions.isEmpty) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No transactions yet'),
                        Text('Tap + to add your first transaction'),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: transactions.length,
                  itemBuilder: (context, index) {
                    final transaction = transactions[index];
                    return TransactionItem(
                      transaction: transaction,
                      onEdit: () => _editTransaction(context, transaction),
                      onDelete: () => _deleteTransaction(context, transaction),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: FutureBuilder<double>(
              future: Transaction.getTotalIncome(),
              builder: (context, snapshot) {
                final income = snapshot.data ?? 0.0;
                return _buildSummaryCard(
                  'Income',
                  income,
                  Colors.green,
                  Icons.trending_up,
                );
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: FutureBuilder<double>(
              future: Transaction.getTotalExpenses(),
              builder: (context, snapshot) {
                final expenses = snapshot.data ?? 0.0;
                return _buildSummaryCard(
                  'Expenses',
                  expenses,
                  Colors.red,
                  Icons.trending_down,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, double amount, Color color, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(title, style: TextStyle(color: Colors.grey[600])),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${NumberFormat('#,##0.00').format(amount)}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddTransaction(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const TransactionForm(),
      ),
    );
  }

  void _editTransaction(BuildContext context, Transaction transaction) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TransactionForm(transaction: transaction),
      ),
    );
  }

  void _deleteTransaction(BuildContext context, Transaction transaction) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: Text('Are you sure you want to delete "${transaction.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await transaction.delete();
              if (context.mounted) {
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Transaction deleted')),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class TransactionItem extends StatelessWidget {
  final Transaction transaction;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const TransactionItem({
    super.key,
    required this.transaction,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: transaction.type == TransactionType.income
              ? Colors.green.withOpacity(0.1)
              : Colors.red.withOpacity(0.1),
          child: Icon(
            transaction.type == TransactionType.income
                ? Icons.trending_up
                : Icons.trending_down,
            color: transaction.type == TransactionType.income
                ? Colors.green
                : Colors.red,
          ),
        ),
        title: Text(transaction.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat('MMM dd, yyyy').format(transaction.date)),
            if (transaction.notes != null)
              Text(
                transaction.notes!,
                style: TextStyle(color: Colors.grey[600]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${NumberFormat('#,##0.00').format(transaction.amount)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: transaction.type == TransactionType.income
                    ? Colors.green
                    : Colors.red,
              ),
            ),
            PopupMenuButton(
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Delete', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
              onSelected: (value) {
                if (value == 'edit') {
                  onEdit();
                } else if (value == 'delete') {
                  onDelete();
                }
              },
            ),
          ],
        ),
        isThreeLine: transaction.notes != null,
      ),
    );
  }
}