// lib/widgets/mpesa/pending_mpesa_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/pending_mpesa.dart';
import '../../models/transaction.dart';
import '../../models/category.dart';
import '../common/status_app_bar.dart';
import '../transactions/transaction_form.dart';

class PendingMpesaPage extends StatelessWidget {
  const PendingMpesaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const StatusAppBar(title: Text('Pending MPESA Messages')),
      body: StreamBuilder<List<PendingMpesa>>(
        stream: PendingMpesa.watchUserPendingMessages(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                ],
              ),
            );
          }

          final pendingMessages = snapshot.data ?? [];

          if (pendingMessages.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, 
                    size: 80, 
                    color: Colors.green[300],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'All caught up!',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No pending MPESA messages',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            );
          }

          return Column(
            children: [
              // Summary Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  border: Border(
                    bottom: BorderSide(color: Colors.orange.shade200),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.pending_actions, 
                      color: Colors.orange.shade700,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${pendingMessages.length} Pending ${pendingMessages.length == 1 ? 'Message' : 'Messages'}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade900,
                            ),
                          ),
                          Text(
                            'Tap to add as transaction or dismiss',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (pendingMessages.length > 1)
                      TextButton(
                        onPressed: () => _showClearAllDialog(context),
                        child: Text(
                          'Clear All',
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                  ],
                ),
              ),

              // Pending Messages List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: pendingMessages.length,
                  itemBuilder: (context, index) {
                    final message = pendingMessages[index];
                    return PendingMpesaCard(
                      message: message,
                      onAddTransaction: () => _addAsTransaction(context, message),
                      onDismiss: () => _dismissMessage(context, message),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addAsTransaction(BuildContext context, PendingMpesa message) async {
    // Get MPESA category
    final categories = await Category.watchUserCategories().first;
    Category? mpesaCategory;
    
    try {
      mpesaCategory = categories.firstWhere(
        (cat) => cat.name.toLowerCase() == 'mpesa',
      );
    } catch (e) {
      // Create MPESA category if it doesn't exist
      mpesaCategory = await Category.create(
        name: 'MPESA',
        type: 'both',
        color: '#4CAF50',
        icon: 'payments',
      );
    }

    if (!context.mounted) return;

    // Navigate to transaction form with pre-filled data
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TransactionForm(
          initialTitle: message.parsedTitle,
          initialAmount: message.amount,
          initialType: message.type == 'income' 
            ? TransactionType.income 
            : TransactionType.expense,
          initialCategoryId: mpesaCategory?.id,
          initialNotes: 'From MPESA SMS (${message.transactionCode})',
        ),
      ),
    );

    // If transaction was created, delete the pending message
    if (result == true && context.mounted) {
      await message.delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _dismissMessage(BuildContext context, PendingMpesa message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dismiss Message'),
        content: const Text(
          'Are you sure you want to dismiss this message? '
          'It will be permanently removed from pending messages.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await message.delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message dismissed'),
          ),
        );
      }
    }
  }

  Future<void> _showClearAllDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Messages'),
        content: const Text(
          'Are you sure you want to dismiss all pending messages? '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await PendingMpesa.deleteAll();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All pending messages cleared'),
          ),
        );
      }
    }
  }
}

class PendingMpesaCard extends StatelessWidget {
  final PendingMpesa message;
  final VoidCallback onAddTransaction;
  final VoidCallback onDismiss;

  const PendingMpesaCard({
    super.key,
    required this.message,
    required this.onAddTransaction,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isIncome = message.type == 'income';
    final color = isIncome ? Colors.green : Colors.red;
    final icon = isIncome ? Icons.arrow_downward : Icons.arrow_upward;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with amount and type
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withOpacity(0.2),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message.parsedTitle ?? 'MPESA Transaction',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('EEE, MMM dd, yyyy • h:mm a')
                            .format(message.receivedAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                if (message.amount != null)
                  Text(
                    'KES ${NumberFormat('#,##0').format(message.amount)}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
              ],
            ),
          ),

          // Message content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.sms, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Text(
                      'From: ${message.sender}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                if (message.transactionCode != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.tag, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Text(
                        'Code: ${message.transactionCode}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    message.rawMessage,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Action buttons
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Dismiss'),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: onAddTransaction,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Transaction'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}