// lib/models/transaction.dart
import 'package:powersync/sqlite3_common.dart' as sqlite;
import '../powersync.dart';
import '../services/user_preferences.dart';
import 'schema.dart';
import 'mpesa_transaction.dart';

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
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? mpesaCode; // New field for MPESA code

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
    this.latitude,
    this.longitude,
    required this.createdAt,
    required this.updatedAt,
    this.mpesaCode,
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
      latitude: row['latitude'] != null ? (row['latitude'] as num).toDouble() : null,
      longitude: row['longitude'] != null ? (row['longitude'] as num).toDouble() : null,
      createdAt: DateTime.parse(row['created_at']),
      updatedAt: DateTime.parse(row['updated_at']),
      mpesaCode: row.containsKey('mpesa_code') ? row['mpesa_code'] : null,
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
      'latitude': latitude,
      'longitude': longitude,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'mpesa_code': mpesaCode,
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

  // Watch transactions with MPESA link information (JOIN query)
  static Stream<List<Map<String, dynamic>>> watchTransactionsWithMpesaInfo() {
    final userId = getUserId();
    if (userId == null) return Stream.value([]);
    
    return db.watch('''
      SELECT 
        t.*,
        COUNT(m.id) as mpesa_count,
        MIN(m.transaction_code) as mpesa_code
      FROM $transactionsTable t
      LEFT JOIN $mpesaTransactionsTable m ON t.id = m.linked_transaction_id
      WHERE t.user_id = ?
      GROUP BY t.id
      ORDER BY t.date DESC, t.created_at DESC
    ''', parameters: [userId]).map((results) {
      return results.map((row) => Map<String, dynamic>.from(row)).toList();
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
    double? latitude,
    double? longitude,
    String? mpesaCode,
  }) async {
    final userId = getUserId();
    if (userId == null) throw Exception('User not logged in');

    // Check if this is the first transaction - set the tracking start time
    final hasFirstTransaction = await UserPreferences.hasRecordedFirstTransaction();
    if (!hasFirstTransaction) {
      await UserPreferences.setFirstTransactionTime(DateTime.now());
      print('✓ First transaction recorded - tracking started');
    }

    final now = DateTime.now().toIso8601String();
    final results = await db.execute('''
      INSERT INTO $transactionsTable(
        id, user_id, title, amount, type, category_id, budget_id, date, notes, latitude, longitude, created_at, updated_at, mpesa_code
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
      latitude,
      longitude,
      now,
      now,
      mpesaCode,
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
    double? latitude,
    double? longitude,
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
        latitude = COALESCE(?, latitude),
        longitude = COALESCE(?, longitude),
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
      latitude,
      longitude,
      now,
      id,
    ]);
  }

  // Delete transaction
  Future<void> delete() async {
    await db.execute('DELETE FROM $transactionsTable WHERE id = ?', [id]);
  }

  /// Delete transaction and unlink all associated MPESA transactions
  /// This preserves the MPESA records but removes the foreign key link
  Future<void> deleteWithUnlink() async {
    // First unlink all MPESA transactions
    final linkedMpesa = await getLinkedMpesaTransactions();
    for (var mpesa in linkedMpesa) {
      await mpesa.unlink();
    }
    
    print('✓ Unlinked ${linkedMpesa.length} MPESA transaction(s)');
    
    // Then delete the transaction
    await delete();
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

  /// Check if this transaction was created from an MPESA transaction
  Future<bool> hasLinkedMpesaTransaction() async {
    final mpesaTransactions = await MpesaTransaction.getByLinkedTransactionId(id);
    return mpesaTransactions.isNotEmpty;
  }

  /// Get all MPESA transactions linked to this transaction
  Future<List<MpesaTransaction>> getLinkedMpesaTransactions() async {
    return await MpesaTransaction.getByLinkedTransactionId(id);
  }

  /// Get the first (primary) linked MPESA transaction if it exists
  Future<MpesaTransaction?> getPrimaryLinkedMpesaTransaction() async {
    final mpesaTransactions = await MpesaTransaction.getByLinkedTransactionId(id);
    return mpesaTransactions.isEmpty ? null : mpesaTransactions.first;
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

  // Helper method to check if transaction has location
  bool hasLocation() {
    return latitude != null && longitude != null;
  }

  // Helper method to get location as a formatted string
  String? getLocationString() {
    if (!hasLocation()) return null;
    return '${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}';
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
      latitude: latitude,
      longitude: longitude,
      mpesaCode: mpesaCode,
    );
  }

  @override
  String toString() {
    return 'Transaction(id: $id, title: $title, amount: $amount, type: ${type.name}, date: $date, location: ${getLocationString() ?? "none"}, mpesaCode: ${mpesaCode ?? "none"})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Transaction && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}