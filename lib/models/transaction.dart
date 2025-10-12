// lib/models/transaction.dart
import 'package:powersync/sqlite3_common.dart' as sqlite;
import '../powersync.dart';
import 'schema.dart';

enum TransactionType { income, expense }

class Transaction {
  final String id;
  final String userId;
  final String title;
  final double amount;
  final TransactionType type;
  final String categoryId;
  final String? budgetId;
  final DateTime date;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  Transaction({
    required this.id,
    required this.userId,
    required this.title,
    required this.amount,
    required this.type,
    required this.categoryId,
    this.budgetId,
    required this.date,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Transaction.fromRow(sqlite.Row row) {
    return Transaction(
      id: row['id'],
      userId: row['user_id'],
      title: row['title'],
      amount: (row['amount'] as num).toDouble(),
      type: row['type'] == 'income' ? TransactionType.income : TransactionType.expense,
      categoryId: row['category_id'],
      budgetId: row['budget_id'],
      date: DateTime.parse(row['date']),
      notes: row['notes'],
      createdAt: DateTime.parse(row['created_at']),
      updatedAt: DateTime.parse(row['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'amount': amount,
      'type': type.name,
      'category_id': categoryId,
      'budget_id': budgetId,
      'date': date.toIso8601String(),
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // Watch all transactions for current user
  static Stream<List<Transaction>> watchUserTransactions() {
    final userId = getUserId();
    if (userId == null) return Stream.value([]);
    
    return db.watch('''
      SELECT * FROM $transactionsTable 
      WHERE user_id = ? 
      ORDER BY date DESC, created_at DESC
    ''', parameters: [userId]).map((results) {
      return results.map(Transaction.fromRow).toList(growable: false);
    });
  }

  // Watch transactions by type
  static Stream<List<Transaction>> watchTransactionsByType(TransactionType type) {
    final userId = getUserId();
    if (userId == null) return Stream.value([]);
    
    return db.watch('''
      SELECT * FROM $transactionsTable 
      WHERE user_id = ? AND type = ?
      ORDER BY date DESC, created_at DESC
    ''', parameters: [userId, type.name]).map((results) {
      return results.map(Transaction.fromRow).toList(growable: false);
    });
  }

  // Watch transactions by category
  static Stream<List<Transaction>> watchTransactionsByCategory(String categoryId) {
    final userId = getUserId();
    if (userId == null) return Stream.value([]);
    
    return db.watch('''
      SELECT * FROM $transactionsTable 
      WHERE user_id = ? AND category_id = ?
      ORDER BY date DESC, created_at DESC
    ''', parameters: [userId, categoryId]).map((results) {
      return results.map(Transaction.fromRow).toList(growable: false);
    });
  }

  // Watch transactions by date range
  static Stream<List<Transaction>> watchTransactionsByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) {
    final userId = getUserId();
    if (userId == null) return Stream.value([]);
    
    return db.watch('''
      SELECT * FROM $transactionsTable 
      WHERE user_id = ? 
        AND date >= ? 
        AND date < ?
      ORDER BY date DESC, created_at DESC
    ''', parameters: [
      userId,
      startDate.toIso8601String(),
      endDate.toIso8601String(),
    ]).map((results) {
      return results.map(Transaction.fromRow).toList(growable: false);
    });
  }

  // Create new transaction
  static Future<Transaction> create({
    required String title,
    required double amount,
    required TransactionType type,
    required String categoryId,
    String? budgetId,
    required DateTime date,
    String? notes,
  }) async {
    final userId = getUserId();
    if (userId == null) throw Exception('User not logged in');

    final now = DateTime.now().toIso8601String();
    final results = await db.execute('''
      INSERT INTO $transactionsTable(
        id, user_id, title, amount, type, category_id, budget_id, date, notes, created_at, updated_at
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      RETURNING *
    ''', [
      uuid.v4(),
      userId,
      title,
      amount,
      type.name,
      categoryId,
      budgetId,
      date.toIso8601String(),
      notes,
      now,
      now,
    ]);
    
    return Transaction.fromRow(results.first);
  }

  // Update transaction
  Future<void> update({
    String? title,
    double? amount,
    TransactionType? type,
    String? categoryId,
    String? budgetId,
    DateTime? date,
    String? notes,
  }) async {
    final now = DateTime.now().toIso8601String();
    await db.execute('''
      UPDATE $transactionsTable SET
        title = COALESCE(?, title),
        amount = COALESCE(?, amount),
        type = COALESCE(?, type),
        category_id = COALESCE(?, category_id),
        budget_id = COALESCE(?, budget_id),
        date = COALESCE(?, date),
        notes = COALESCE(?, notes),
        updated_at = ?
      WHERE id = ?
    ''', [
      title,
      amount,
      type?.name,
      categoryId,
      budgetId,
      date?.toIso8601String(),
      notes,
      now,
      id,
    ]);
  }

  // Delete transaction
  Future<void> delete() async {
    await db.execute('DELETE FROM $transactionsTable WHERE id = ?', [id]);
  }

  // Get transaction by ID
  static Future<Transaction?> getById(String transactionId) async {
    final result = await db.getOptional(
      'SELECT * FROM $transactionsTable WHERE id = ?',
      [transactionId],
    );
    
    if (result == null) return null;
    return Transaction.fromRow(result);
  }

  // Get total income
  static Future<double> getTotalIncome() async {
    final userId = getUserId();
    if (userId == null) return 0.0;
    
    final result = await db.getOptional('''
      SELECT SUM(amount) as total FROM $transactionsTable 
      WHERE user_id = ? AND type = 'income'
    ''', [userId]);
    
    return (result?['total'] as num?)?.toDouble() ?? 0.0;
  }

  // Get total expenses
  static Future<double> getTotalExpenses() async {
    final userId = getUserId();
    if (userId == null) return 0.0;
    
    final result = await db.getOptional('''
      SELECT SUM(amount) as total FROM $transactionsTable 
      WHERE user_id = ? AND type = 'expense'
    ''', [userId]);
    
    return (result?['total'] as num?)?.toDouble() ?? 0.0;
  }

  // Get balance (income - expenses)
  static Future<double> getBalance() async {
    final income = await getTotalIncome();
    final expenses = await getTotalExpenses();
    return income - expenses;
  }

  // Get total income for date range
  static Future<double> getTotalIncomeForDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final userId = getUserId();
    if (userId == null) return 0.0;
    
    final result = await db.getOptional('''
      SELECT SUM(amount) as total FROM $transactionsTable 
      WHERE user_id = ? 
        AND type = 'income'
        AND date >= ? 
        AND date < ?
    ''', [
      userId,
      startDate.toIso8601String(),
      endDate.toIso8601String(),
    ]);
    
    return (result?['total'] as num?)?.toDouble() ?? 0.0;
  }

  // Get total expenses for date range
  static Future<double> getTotalExpensesForDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final userId = getUserId();
    if (userId == null) return 0.0;
    
    final result = await db.getOptional('''
      SELECT SUM(amount) as total FROM $transactionsTable 
      WHERE user_id = ? 
        AND type = 'expense'
        AND date >= ? 
        AND date < ?
    ''', [
      userId,
      startDate.toIso8601String(),
      endDate.toIso8601String(),
    ]);
    
    return (result?['total'] as num?)?.toDouble() ?? 0.0;
  }

  // Get balance for date range
  static Future<double> getBalanceForDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final income = await getTotalIncomeForDateRange(startDate, endDate);
    final expenses = await getTotalExpensesForDateRange(startDate, endDate);
    return income - expenses;
  }

  // Get total amount by category
  static Future<double> getTotalByCategory(String categoryId) async {
    final userId = getUserId();
    if (userId == null) return 0.0;
    
    final result = await db.getOptional('''
      SELECT SUM(amount) as total FROM $transactionsTable 
      WHERE user_id = ? AND category_id = ?
    ''', [userId, categoryId]);
    
    return (result?['total'] as num?)?.toDouble() ?? 0.0;
  }

  // Get transaction count
  static Future<int> getTransactionCount() async {
    final userId = getUserId();
    if (userId == null) return 0;
    
    final result = await db.getOptional('''
      SELECT COUNT(*) as count FROM $transactionsTable 
      WHERE user_id = ?
    ''', [userId]);
    
    return (result?['count'] as int?) ?? 0;
  }

  // Get transaction count by type
  static Future<int> getTransactionCountByType(TransactionType type) async {
    final userId = getUserId();
    if (userId == null) return 0;
    
    final result = await db.getOptional('''
      SELECT COUNT(*) as count FROM $transactionsTable 
      WHERE user_id = ? AND type = ?
    ''', [userId, type.name]);
    
    return (result?['count'] as int?) ?? 0;
  }

  // Get transaction count for date range
  static Future<int> getTransactionCountForDateRange(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final userId = getUserId();
    if (userId == null) return 0;
    
    final result = await db.getOptional('''
      SELECT COUNT(*) as count FROM $transactionsTable 
      WHERE user_id = ? 
        AND date >= ? 
        AND date < ?
    ''', [
      userId,
      startDate.toIso8601String(),
      endDate.toIso8601String(),
    ]);
    
    return (result?['count'] as int?) ?? 0;
  }

  // Get recent transactions (limit)
  static Future<List<Transaction>> getRecentTransactions({int limit = 10}) async {
    final userId = getUserId();
    if (userId == null) return [];
    
    final results = await db.getAll('''
      SELECT * FROM $transactionsTable 
      WHERE user_id = ? 
      ORDER BY date DESC, created_at DESC
      LIMIT ?
    ''', [userId, limit]);
    
    return results.map(Transaction.fromRow).toList();
  }

  // Search transactions by title or notes
  static Future<List<Transaction>> searchTransactions(String query) async {
    final userId = getUserId();
    if (userId == null) return [];
    
    final searchQuery = '%${query.toLowerCase()}%';
    final results = await db.getAll('''
      SELECT * FROM $transactionsTable 
      WHERE user_id = ? 
        AND (LOWER(title) LIKE ? OR LOWER(notes) LIKE ?)
      ORDER BY date DESC, created_at DESC
    ''', [userId, searchQuery, searchQuery]);
    
    return results.map(Transaction.fromRow).toList();
  }

  // Get transactions grouped by category with totals
  static Future<Map<String, double>> getCategoryTotals({
    TransactionType? type,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final userId = getUserId();
    if (userId == null) return {};
    
    String query = '''
      SELECT category_id, SUM(amount) as total 
      FROM $transactionsTable 
      WHERE user_id = ?
    ''';
    
    final params = <dynamic>[userId];
    
    if (type != null) {
      query += ' AND type = ?';
      params.add(type.name);
    }
    
    if (startDate != null) {
      query += ' AND date >= ?';
      params.add(startDate.toIso8601String());
    }
    
    if (endDate != null) {
      query += ' AND date < ?';
      params.add(endDate.toIso8601String());
    }
    
    query += ' GROUP BY category_id';
    
    final results = await db.getAll(query, params);
    
    final Map<String, double> categoryTotals = {};
    for (var row in results) {
      categoryTotals[row['category_id']] = (row['total'] as num).toDouble();
    }
    
    return categoryTotals;
  }

  // Get average transaction amount
  static Future<double> getAverageAmount({
    TransactionType? type,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final userId = getUserId();
    if (userId == null) return 0.0;
    
    String query = '''
      SELECT AVG(amount) as average 
      FROM $transactionsTable 
      WHERE user_id = ?
    ''';
    
    final params = <dynamic>[userId];
    
    if (type != null) {
      query += ' AND type = ?';
      params.add(type.name);
    }
    
    if (startDate != null) {
      query += ' AND date >= ?';
      params.add(startDate.toIso8601String());
    }
    
    if (endDate != null) {
      query += ' AND date < ?';
      params.add(endDate.toIso8601String());
    }
    
    final result = await db.getOptional(query, params);
    
    return (result?['average'] as num?)?.toDouble() ?? 0.0;
  }

  // Get largest transaction
  static Future<Transaction?> getLargestTransaction({
    TransactionType? type,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final userId = getUserId();
    if (userId == null) return null;
    
    String query = '''
      SELECT * FROM $transactionsTable 
      WHERE user_id = ?
    ''';
    
    final params = <dynamic>[userId];
    
    if (type != null) {
      query += ' AND type = ?';
      params.add(type.name);
    }
    
    if (startDate != null) {
      query += ' AND date >= ?';
      params.add(startDate.toIso8601String());
    }
    
    if (endDate != null) {
      query += ' AND date < ?';
      params.add(endDate.toIso8601String());
    }
    
    query += ' ORDER BY amount DESC LIMIT 1';
    
    final result = await db.getOptional(query, params);
    
    if (result == null) return null;
    return Transaction.fromRow(result);
  }

  // Copy transaction (useful for recurring transactions)
  Future<Transaction> copy({
    DateTime? newDate,
    String? newNotes,
  }) async {
    return Transaction.create(
      title: title,
      amount: amount,
      type: type,
      categoryId: categoryId,
      budgetId: budgetId,
      date: newDate ?? DateTime.now(),
      notes: newNotes ?? notes,
    );
  }

  @override
  String toString() {
    return 'Transaction(id: $id, title: $title, amount: $amount, type: ${type.name}, date: $date)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Transaction && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}