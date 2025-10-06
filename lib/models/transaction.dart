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
      amount: row['amount'].toDouble(),
      type: row['type'] == 'income' ? TransactionType.income : TransactionType.expense,
      categoryId: row['category_id'],
      budgetId: row['budget_id'],
      date: DateTime.parse(row['date']),
      notes: row['notes'],
      createdAt: DateTime.parse(row['created_at']),
      updatedAt: DateTime.parse(row['updated_at']),
    );
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
        id, user_id, title, amount, type, category_id, date, notes, created_at, updated_at
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      RETURNING *
    ''', [
      uuid.v4(),
      userId,
      title,
      amount,
      type.name,
      categoryId,
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
        date = COALESCE(?, date),
        notes = COALESCE(?, notes),
        updated_at = ?
      WHERE id = ?
    ''', [
      title,
      amount,
      type?.name,
      categoryId,
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
}