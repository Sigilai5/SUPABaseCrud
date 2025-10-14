// lib/widgets/transactions/transaction_list.dart
// COMPLETE FILE - Replace your entire transaction_list.dart with this

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/transaction.dart';
import '../../models/category.dart';
import '../../powersync.dart';
import 'transaction_form.dart';
import '../common/location_display_widget.dart'; // NEW: Location import

class TransactionList extends StatelessWidget {
  const TransactionList({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: StreamBuilder<List<Transaction>>(
        stream: Transaction.watchUserTransactions(),
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

          final transactions = snapshot.data ?? [];

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Column(
              children: [
                _buildProfileHeader(),
                const SizedBox(height: 16),
                
                Expanded(
                  child: transactions.isEmpty
                      ? _buildEmptyState(context)
                      : RefreshIndicator(
                          onRefresh: () async {
                            await Future.delayed(const Duration(milliseconds: 500));
                          },
                          child: ListView(
                            padding: EdgeInsets.zero,
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              _buildFinancialCard(
                                context,
                                title: 'Today',
                                transactions: transactions,
                                period: SpendingPeriod.today,
                                onTap: () => _showPeriodDetails(context, transactions, SpendingPeriod.today),
                              ),
                              const SizedBox(height: 16),
                              _buildFinancialCard(
                                context,
                                title: 'This Week',
                                transactions: transactions,
                                period: SpendingPeriod.week,
                                onTap: () => _showPeriodDetails(context, transactions, SpendingPeriod.week),
                              ),
                              const SizedBox(height: 16),
                              _buildFinancialCard(
                                context,
                                title: 'This Month',
                                transactions: transactions,
                                period: SpendingPeriod.month,
                                onTap: () => _showPeriodDetails(context, transactions, SpendingPeriod.month),
                              ),
                              const SizedBox(height: 80),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddTransaction(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Transaction'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 6,
        tooltip: 'Add new transaction',
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildProfileHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: Colors.blue.shade100,
            child: Icon(Icons.person, size: 36, color: Colors.blue.shade700),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FutureBuilder<String>(
                  future: _getDisplayName(),
                  builder: (context, snapshot) {
                    final displayName = snapshot.data ?? 'Expense Tracker User';
                    return Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
                Text(
                  'Expense Tracker',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<String> _getDisplayName() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session?.user.email != null) {
        final email = session!.user.email!;
        final name = email.split('@').first;
        return _capitalizeWords(name.replaceAll('.', ' ').replaceAll('_', ' '));
      }
    } catch (e) {
      print('Error getting user email: $e');
    }
    return 'Expense Tracker User';
  }

  String _capitalizeWords(String text) {
    return text.split(' ').map((word) => 
      word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1).toLowerCase()
    ).join(' ');
  }

  void _showPeriodDetails(BuildContext context, List<Transaction> transactions, SpendingPeriod period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    DateTime startDate;
    DateTime endDate;
    String title;

    switch (period) {
      case SpendingPeriod.today:
        startDate = today;
        endDate = today.add(const Duration(days: 1));
        title = 'Today\'s Transactions';
        break;
      
      case SpendingPeriod.week:
        startDate = today.subtract(Duration(days: today.weekday - 1));
        endDate = today.add(const Duration(days: 1));
        title = 'This Week\'s Transactions';
        break;
      
      case SpendingPeriod.month:
        startDate = DateTime(now.year, now.month, 1);
        endDate = DateTime(now.year, now.month + 1, 1);
        title = 'This Month\'s Transactions';
        break;
    }

    final periodTransactions = transactions
        .where((t) =>
          t.date.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
          t.date.isBefore(endDate))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PeriodDetailsPage(
          title: title,
          transactions: periodTransactions,
          period: period,
        ),
      ),
    );
  }

  Widget _buildFinancialCard(
    BuildContext context, {
    required String title,
    required List<Transaction> transactions,
    required SpendingPeriod period,
    VoidCallback? onTap,
  }) {
    final currentExpenses = _calculateAmount(transactions, period, TransactionType.expense, isCurrent: true);
    final currentIncome = _calculateAmount(transactions, period, TransactionType.income, isCurrent: true);
    final currentNet = currentIncome - currentExpenses;
    
    final previousExpenses = _calculateAmount(transactions, period, TransactionType.expense, isCurrent: false);
    final previousIncome = _calculateAmount(transactions, period, TransactionType.income, isCurrent: false);
    final previousNet = previousIncome - previousExpenses;
    
    final netPercentage = previousNet != 0 
        ? ((currentNet - previousNet) / previousNet.abs() * 100).abs()
        : 0.0;
    
    final isNetPositive = currentNet > previousNet;
    final netColor = isNetPositive ? Colors.green : Colors.red;
    final arrowIcon = isNetPositive ? Icons.arrow_upward : Icons.arrow_downward;
    final comparisonText = isNetPositive ? 'better' : 'worse';

    final cardContent = Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (previousNet != 0)
                  Row(
                    children: [
                      Icon(arrowIcon, size: 16, color: netColor),
                      const SizedBox(width: 4),
                      Text(
                        '${netPercentage.toStringAsFixed(0)}% $comparisonText',
                        style: TextStyle(
                          fontSize: 13,
                          color: netColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 16),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.arrow_downward,
                        color: Colors.green.shade700,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Income',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          'KES ${NumberFormat('#,##0').format(currentIncome)}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.arrow_upward,
                        color: Colors.red.shade700,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Expenses',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          'KES ${NumberFormat('#,##0').format(currentExpenses)}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            Divider(color: Colors.grey[300], thickness: 1),
            const SizedBox(height: 12),
            
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Net Balance',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                Text(
                  'KES ${NumberFormat('#,##0').format(currentNet)}',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: currentNet >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
              ],
            ),
            
            if (previousNet != 0) ...[
              const SizedBox(height: 8),
              Text(
                _getComparisonText(period, previousNet),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: cardContent,
      );
    }

    return cardContent;
  }

  String _getComparisonText(SpendingPeriod period, double previousNet) {
    switch (period) {
      case SpendingPeriod.today:
        return 'Yesterday: KES ${NumberFormat('#,##0').format(previousNet)}';
      case SpendingPeriod.week:
        return 'Last Week: KES ${NumberFormat('#,##0').format(previousNet)}';
      case SpendingPeriod.month:
        return 'Last Month: KES ${NumberFormat('#,##0').format(previousNet)}';
    }
  }

  double _calculateAmount(
    List<Transaction> transactions,
    SpendingPeriod period,
    TransactionType type, {
    required bool isCurrent,
  }) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    DateTime startDate;
    DateTime endDate;

    switch (period) {
      case SpendingPeriod.today:
        if (isCurrent) {
          startDate = today;
          endDate = today.add(const Duration(days: 1));
        } else {
          startDate = today.subtract(const Duration(days: 1));
          endDate = today;
        }
        break;
      
      case SpendingPeriod.week:
        final weekStart = today.subtract(Duration(days: today.weekday - 1));
        if (isCurrent) {
          startDate = weekStart;
          endDate = today.add(const Duration(days: 1));
        } else {
          startDate = weekStart.subtract(const Duration(days: 7));
          endDate = weekStart;
        }
        break;
      
      case SpendingPeriod.month:
        if (isCurrent) {
          startDate = DateTime(now.year, now.month, 1);
          endDate = DateTime(now.year, now.month + 1, 1);
        } else {
          startDate = DateTime(now.year, now.month - 1, 1);
          endDate = DateTime(now.year, now.month, 1);
        }
        break;
    }

    return transactions
        .where((t) => 
          t.type == type &&
          t.date.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
          t.date.isBefore(endDate)
        )
        .fold(0.0, (sum, t) => sum + t.amount);
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'No transactions yet',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          const Text('Tap + to add your first transaction'),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => _showAddTransaction(context),
            icon: const Icon(Icons.add),
            label: const Text('Add Transaction'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
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
}

enum SpendingPeriod { today, week, month }

// UPDATED PeriodDetailsPage with Location Support
class PeriodDetailsPage extends StatelessWidget {
  final String title;
  final List<Transaction> transactions;
  final SpendingPeriod period;

  const PeriodDetailsPage({
    super.key,
    required this.title,
    required this.transactions,
    required this.period,
  });

  @override
  Widget build(BuildContext context) {
    final totalIncome = transactions
        .where((t) => t.type == TransactionType.income)
        .fold(0.0, (sum, t) => sum + t.amount);
    
    final totalExpenses = transactions
        .where((t) => t.type == TransactionType.expense)
        .fold(0.0, (sum, t) => sum + t.amount);
    
    final netBalance = totalIncome - totalExpenses;

    final Map<String, List<Transaction>> groupedTransactions = {};
    for (var transaction in transactions) {
      final dateKey = DateFormat('EEEE, MMM dd, yyyy').format(transaction.date);
      if (!groupedTransactions.containsKey(dateKey)) {
        groupedTransactions[dateKey] = [];
      }
      groupedTransactions[dateKey]!.add(transaction);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.arrow_downward, color: Colors.green.shade700, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              'Income',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'KES ${NumberFormat('#,##0').format(totalIncome)}',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.arrow_upward, color: Colors.red.shade700, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              'Expenses',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        Text(
                          'KES ${NumberFormat('#,##0').format(totalExpenses)}',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Divider(color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Net Balance',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[700],
                      ),
                    ),
                    Text(
                      'KES ${NumberFormat('#,##0').format(netBalance)}',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: netBalance >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${transactions.length} ${transactions.length == 1 ? 'transaction' : 'transactions'}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: transactions.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle, size: 64, color: Colors.green[300]),
                        const SizedBox(height: 16),
                        Text(
                          'No transactions for this period!',
                          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: groupedTransactions.length,
                    itemBuilder: (context, index) {
                      final dateKey = groupedTransactions.keys.elementAt(index);
                      final dayTransactions = groupedTransactions[dateKey]!;
                      
                      final dayIncome = dayTransactions
                          .where((t) => t.type == TransactionType.income)
                          .fold(0.0, (sum, t) => sum + t.amount);
                      
                      final dayExpenses = dayTransactions
                          .where((t) => t.type == TransactionType.expense)
                          .fold(0.0, (sum, t) => sum + t.amount);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  dateKey,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                Row(
                                  children: [
                                    if (dayIncome > 0)
                                      Text(
                                        '+${NumberFormat('#,##0').format(dayIncome)}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.green.shade700,
                                        ),
                                      ),
                                    if (dayIncome > 0 && dayExpenses > 0)
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                        child: Text('•', style: TextStyle(color: Colors.grey[400])),
                                      ),
                                    if (dayExpenses > 0)
                                      Text(
                                        '-${NumberFormat('#,##0').format(dayExpenses)}',
                                        style: Text