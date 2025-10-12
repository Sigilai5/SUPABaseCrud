// lib/widgets/reports/reports_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/transaction.dart';
import '../../models/category.dart';
import '../common/status_app_bar.dart';
import '../transactions/transaction_form.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  DateTime _selectedMonth = DateTime.now();
  String _selectedPeriod = 'today'; // 'today', 'yesterday', 'week', 'month', 'custom'
  
  // Custom date range
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const StatusAppBar(title: Text('Reports')),
      body: Column(
        children: [
          // Period Selector
          _buildPeriodSelector(),
          
          // Custom Date Range Display
          if (_selectedPeriod == 'custom' && _customStartDate != null && _customEndDate != null)
            _buildCustomDateDisplay(),
          
          // Scrollable Content
          Expanded(
            child: StreamBuilder<List<Transaction>>(
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

                final allTransactions = snapshot.data ?? [];
                final filteredTransactions = _filterTransactionsByPeriod(allTransactions);

                if (filteredTransactions.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.analytics_outlined, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No transactions for ${_getPeriodDisplayName()}',
                          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add some transactions to see reports',
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Period Info Card
                    _buildPeriodInfoCard(),
                    const SizedBox(height: 16),

                    // Summary Cards
                    _buildSummaryCards(filteredTransactions),
                    const SizedBox(height: 24),

                    // Income vs Expense Chart
                    _buildIncomeExpenseChart(filteredTransactions),
                    const SizedBox(height: 24),

                    // Category Breakdown
                    _buildCategoryBreakdown(filteredTransactions),
                    const SizedBox(height: 24),

                    // Recent Transactions
                    _buildRecentTransactions(filteredTransactions),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
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
      child: Column(
        children: [
          // Period Buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _buildPeriodChip('Today', 'today', icon: Icons.today),
              _buildPeriodChip('Yesterday', 'yesterday', icon: Icons.event),
              _buildPeriodChip('This Week', 'week', icon: Icons.date_range),
              _buildPeriodChip('This Month', 'month', icon: Icons.calendar_month),
              _buildPeriodChip('Custom', 'custom', icon: Icons.tune),
            ],
          ),
          
          // Month Selector (only show for month view)
          if (_selectedPeriod == 'month') ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(() {
                      _selectedMonth = DateTime(
                        _selectedMonth.year,
                        _selectedMonth.month - 1,
                      );
                    });
                  },
                ),
                Text(
                  DateFormat('MMMM yyyy').format(_selectedMonth),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    final now = DateTime.now();
                    final nextMonth = DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month + 1,
                    );
                    if (nextMonth.isBefore(now) || 
                        nextMonth.month == now.month) {
                      setState(() {
                        _selectedMonth = nextMonth;
                      });
                    }
                  },
                ),
              ],
            ),
          ],
          
          // Custom Date Picker (show when custom is selected)
          if (_selectedPeriod == 'custom') ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            _buildCustomDatePicker(),
          ],
        ],
      ),
    );
  }

  Widget _buildPeriodChip(String label, String value, {IconData? icon}) {
    final isSelected = _selectedPeriod == value;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.black87),
            const SizedBox(width: 6),
          ],
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedPeriod = value;
          if (value == 'custom' && (_customStartDate == null || _customEndDate == null)) {
            // Set default custom range to current week
            final now = DateTime.now();
            _customEndDate = now;
            _customStartDate = now.subtract(const Duration(days: 7));
          }
          if (value == 'month') {
            _selectedMonth = DateTime.now();
          }
        });
      },
      backgroundColor: Colors.grey[200],
      selectedColor: Colors.blue,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 13,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }

  Widget _buildPeriodInfoCard() {
    String periodText = '';
    IconData periodIcon = Icons.calendar_today;
    
    switch (_selectedPeriod) {
      case 'today':
        periodText = 'Today - ${DateFormat('EEEE, MMM dd, yyyy').format(DateTime.now())}';
        periodIcon = Icons.today;
        break;
      case 'yesterday':
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        periodText = 'Yesterday - ${DateFormat('EEEE, MMM dd, yyyy').format(yesterday)}';
        periodIcon = Icons.event;
        break;
      case 'week':
        final now = DateTime.now();
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        final weekEnd = now;
        periodText = 'This Week\n${DateFormat('MMM dd').format(weekStart)} - ${DateFormat('MMM dd, yyyy').format(weekEnd)}';
        periodIcon = Icons.date_range;
        break;
      case 'month':
        periodText = DateFormat('MMMM yyyy').format(_selectedMonth);
        periodIcon = Icons.calendar_month;
        break;
      case 'custom':
        if (_customStartDate != null && _customEndDate != null) {
          final days = _customEndDate!.difference(_customStartDate!).inDays + 1;
          periodText = '${DateFormat('MMM dd, yyyy').format(_customStartDate!)} - ${DateFormat('MMM dd, yyyy').format(_customEndDate!)}\n$days ${days == 1 ? 'day' : 'days'}';
          periodIcon = Icons.tune;
        }
        break;
    }

    return Card(
      elevation: 2,
      color: Colors.blue.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(periodIcon, color: Colors.blue, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                periodText,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomDatePicker() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          const Text(
            'Select Custom Date Range',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              // Start Date
              Expanded(
                child: _buildDateButton(
                  label: 'Start Date',
                  date: _customStartDate,
                  onTap: () => _selectStartDate(),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, size: 20, color: Colors.blue),
              ),
              // End Date
              Expanded(
                child: _buildDateButton(
                  label: 'End Date',
                  date: _customEndDate,
                  onTap: () => _selectEndDate(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Quick Select:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          // Quick Select Buttons
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _buildQuickSelectButton('Last 7 Days', () {
                setState(() {
                  _customEndDate = DateTime.now();
                  _customStartDate = _customEndDate!.subtract(const Duration(days: 6));
                });
              }),
              _buildQuickSelectButton('Last 30 Days', () {
                setState(() {
                  _customEndDate = DateTime.now();
                  _customStartDate = _customEndDate!.subtract(const Duration(days: 29));
                });
              }),
              _buildQuickSelectButton('Last 90 Days', () {
                setState(() {
                  _customEndDate = DateTime.now();
                  _customStartDate = _customEndDate!.subtract(const Duration(days: 89));
                });
              }),
              _buildQuickSelectButton('This Year', () {
                final now = DateTime.now();
                setState(() {
                  _customStartDate = DateTime(now.year, 1, 1);
                  _customEndDate = now;
                });
              }),
              _buildQuickSelectButton('Last Year', () {
                final now = DateTime.now();
                setState(() {
                  _customStartDate = DateTime(now.year - 1, 1, 1);
                  _customEndDate = DateTime(now.year - 1, 12, 31);
                });
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateButton({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 14, color: Colors.blue),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    date != null
                        ? DateFormat('MMM dd, yyyy').format(date)
                        : 'Select',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickSelectButton(String label, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(color: Colors.blue.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11),
      ),
    );
  }

  Widget _buildCustomDateDisplay() {
    final daysDifference = _customEndDate!.difference(_customStartDate!).inDays + 1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.blue.withOpacity(0.1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.date_range, size: 18, color: Colors.blue),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '${DateFormat('MMM dd, yyyy').format(_customStartDate!)} - ${DateFormat('MMM dd, yyyy').format(_customEndDate!)}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$daysDifference ${daysDifference == 1 ? 'day' : 'days'}',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectStartDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _customStartDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: _customEndDate ?? DateTime.now(),
      helpText: 'Select Start Date',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        _customStartDate = picked;
        if (_customEndDate != null && _customEndDate!.isBefore(picked)) {
          _customEndDate = picked;
        }
      });
    }
  }

  Future<void> _selectEndDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _customEndDate ?? DateTime.now(),
      firstDate: _customStartDate ?? DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Select End Date',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.blue,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        _customEndDate = picked;
        if (_customStartDate != null && _customStartDate!.isAfter(picked)) {
          _customStartDate = picked;
        }
      });
    }
  }

  String _getPeriodDisplayName() {
    switch (_selectedPeriod) {
      case 'today':
        return 'today';
      case 'yesterday':
        return 'yesterday';
      case 'week':
        return 'this week';
      case 'month':
        return DateFormat('MMMM yyyy').format(_selectedMonth);
      case 'custom':
        return 'the selected period';
      default:
        return 'this period';
    }
  }

  List<Transaction> _filterTransactionsByPeriod(List<Transaction> transactions) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    switch (_selectedPeriod) {
      case 'today':
        return transactions.where((t) {
          final transactionDate = DateTime(t.date.year, t.date.month, t.date.day);
          return transactionDate.isAtSameMomentAs(today);
        }).toList();
      
      case 'yesterday':
        final yesterday = today.subtract(const Duration(days: 1));
        return transactions.where((t) {
          final transactionDate = DateTime(t.date.year, t.date.month, t.date.day);
          return transactionDate.isAtSameMomentAs(yesterday);
        }).toList();
      
      case 'week':
        final weekStart = today.subtract(Duration(days: today.weekday - 1)); // Monday
        return transactions.where((t) {
          final transactionDate = DateTime(t.date.year, t.date.month, t.date.day);
          return (transactionDate.isAfter(weekStart) || transactionDate.isAtSameMomentAs(weekStart)) &&
                 (transactionDate.isBefore(today.add(const Duration(days: 1))));
        }).toList();
      
      case 'month':
        return transactions.where((t) =>
          t.date.year == _selectedMonth.year &&
          t.date.month == _selectedMonth.month
        ).toList();
      
      case 'custom':
        if (_customStartDate == null || _customEndDate == null) {
          return transactions;
        }
        final startDate = DateTime(_customStartDate!.year, _customStartDate!.month, _customStartDate!.day);
        final endDate = DateTime(_customEndDate!.year, _customEndDate!.month, _customEndDate!.day, 23, 59, 59);
        
        return transactions.where((t) {
          final transactionDate = DateTime(t.date.year, t.date.month, t.date.day);
          return (transactionDate.isAfter(startDate) || transactionDate.isAtSameMomentAs(startDate)) &&
                 (transactionDate.isBefore(endDate) || transactionDate.isAtSameMomentAs(endDate));
        }).toList();
      
      default:
        return transactions;
    }
  }

  Widget _buildSummaryCards(List<Transaction> transactions) {
    final income = transactions
        .where((t) => t.type == TransactionType.income)
        .fold(0.0, (sum, t) => sum + t.amount);
    
    final expenses = transactions
        .where((t) => t.type == TransactionType.expense)
        .fold(0.0, (sum, t) => sum + t.amount);
    
    final balance = income - expenses;
    final balanceColor = balance >= 0 ? Colors.green : Colors.red;

    return Column(
      children: [
        Card(
          elevation: 4,
          color: balanceColor,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text(
                  'Net Balance',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '\$${NumberFormat('#,##0.00').format(balance.abs())}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  balance >= 0 ? 'Surplus' : 'Deficit',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.trending_up, color: Colors.green, size: 32),
                      const SizedBox(height: 8),
                      const Text(
                        'Income',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '\$${NumberFormat('#,##0.00').format(income)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Icon(Icons.trending_down, color: Colors.red, size: 32),
                      const SizedBox(height: 8),
                      const Text(
                        'Expenses',
                        style: TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '\$${NumberFormat('#,##0.00').format(expenses)}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIncomeExpenseChart(List<Transaction> transactions) {
    final income = transactions
        .where((t) => t.type == TransactionType.income)
        .fold(0.0, (sum, t) => sum + t.amount);
    
    final expenses = transactions
        .where((t) => t.type == TransactionType.expense)
        .fold(0.0, (sum, t) => sum + t.amount);

    final total = income + expenses;
    final incomePercent = total > 0 ? (income / total * 100) : 0;
    final expensePercent = total > 0 ? (expenses / total * 100) : 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Income vs Expenses',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                height: 40,
                child: Row(
                  children: [
                    if (income > 0)
                      Expanded(
                        flex: income.toInt() > 0 ? income.toInt() : 1,
                        child: Container(
                          color: Colors.green,
                          alignment: Alignment.center,
                          child: income > total * 0.15
                              ? Text(
                                  '${incomePercent.toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    if (expenses > 0)
                      Expanded(
                        flex: expenses.toInt() > 0 ? expenses.toInt() : 1,
                        child: Container(
                          color: Colors.red,
                          alignment: Alignment.center,
                          child: expenses > total * 0.15
                              ? Text(
                                  '${expensePercent.toStringAsFixed(0)}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildLegendItem('Income', Colors.green, incomePercent.toDouble()),
                _buildLegendItem('Expenses', Colors.red, expensePercent.toDouble()),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color, double percent) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text('$label (${percent.toStringAsFixed(1)}%)'),
      ],
    );
  }

  Widget _buildCategoryBreakdown(List<Transaction> transactions) {
    return StreamBuilder<List<Category>>(
      stream: Category.watchUserCategories(),
      builder: (context, categorySnapshot) {
        if (!categorySnapshot.hasData) {
          return const SizedBox.shrink();
        }

        final categories = categorySnapshot.data!;
        final categoryTotals = <String, double>{};
        final categoryNames = <String, String>{};
        final categoryColors = <String, Color>{};
        
        for (var transaction in transactions.where((t) => t.type == TransactionType.expense)) {
          categoryTotals[transaction.categoryId] = 
              (categoryTotals[transaction.categoryId] ?? 0) + transaction.amount;
        }

        for (var category in categories) {
          if (categoryTotals.containsKey(category.id)) {
            categoryNames[category.id] = category.name;
            categoryColors[category.id] = _parseColor(category.color);
          }
        }

        if (categoryTotals.isEmpty) {
          return const SizedBox.shrink();
        }

        final sortedCategories = categoryTotals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        final totalExpenses = categoryTotals.values.fold(0.0, (sum, amount) => sum + amount);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Spending by Category',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                ...sortedCategories.take(5).map((entry) {
                  final categoryId = entry.key;
                  final amount = entry.value;
                  final name = categoryNames[categoryId] ?? 'Unknown';
                  final color = categoryColors[categoryId] ?? Colors.grey;
                  final percent = (amount / totalExpenses * 100);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            Text(
                              '\$${NumberFormat('#,##0.00').format(amount)}',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: percent / 100,
                            backgroundColor: Colors.grey[200],
                            valueColor: AlwaysStoppedAnimation<Color>(color),
                            minHeight: 8,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${percent.toStringAsFixed(1)}% of expenses',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }),
                if (sortedCategories.length > 5) ...[
                  const SizedBox(height: 8),
                  Text(
                    '+ ${sortedCategories.length - 5} more categories',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecentTransactions(List<Transaction> transactions) {
    final recentTransactions = transactions.take(5).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Transactions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (recentTransactions.isNotEmpty)
                  Text(
                    'Tap to edit',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            ...recentTransactions.map((transaction) => InkWell(
              onTap: () => _editTransaction(context, transaction),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: transaction.type == TransactionType.income
                            ? Colors.green.withOpacity(0.1)
                            : Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        transaction.type == TransactionType.income
                            ? Icons.trending_up
                            : Icons.trending_down,
                        color: transaction.type == TransactionType.income
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            transaction.title,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            DateFormat('EEE, MMM dd').format(transaction.date),
                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '\$${NumberFormat('#,##0.00').format(transaction.amount)}',                    
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: transaction.type == TransactionType.income
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: Colors.grey[400],
                    ),
                  ],
                ),
              ),
            )),
          ],
        ),
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

  Color _parseColor(String hexColor) {
    try {
      return Color(int.parse(hexColor.substring(1), radix: 16) + 0xFF000000);
    } catch (e) {
      return Colors.grey;
    }
  }
}