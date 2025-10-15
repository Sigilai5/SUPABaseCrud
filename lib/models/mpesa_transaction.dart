// lib/models/mpesa_transaction.dart
import 'package:powersync/sqlite3_common.dart' as sqlite;
import '../powersync.dart';
import 'schema.dart';
import 'transaction.dart';

enum MpesaTransactionType {
  send,      // Send money to phone number
  pochi,     // Pochi La Biashara
  till,      // Lipa Na MPESA Till
  paybill,   // Paybill payment
  received   // Money received
}

class MpesaTransaction {
  final String id;
  final String userId;
  final String transactionCode;
  final MpesaTransactionType transactionType;
  final double amount;
  final String counterpartyName;
  final String? counterpartyNumber;
  final DateTime transactionDate;
  final double newBalance;
  final double transactionCost;
  final bool isDebit;
  final String rawMessage;
  final String? notes;
  final String? linkedTransactionId; // FOREIGN KEY -> transactions.id
  final DateTime createdAt;

  MpesaTransaction({
    required this.id,
    required this.userId,
    required this.transactionCode,
    required this.transactionType,
    required this.amount,
    required this.counterpartyName,
    this.counterpartyNumber,
    required this.transactionDate,
    required this.newBalance,
    required this.transactionCost,
    required this.isDebit,
    required this.rawMessage,
    this.notes,
    this.linkedTransactionId,
    required this.createdAt,
  });

  factory MpesaTransaction.fromRow(sqlite.Row row) {
    return MpesaTransaction(
      id: row['id'],
      userId: row['user_id'],
      transactionCode: row['transaction_code'],
      transactionType: _parseTransactionType(row['transaction_type']),
      amount: (row['amount'] as num).toDouble(),
      counterpartyName: row['counterparty_name'],
      counterpartyNumber: row['counterparty_number'],
      transactionDate: DateTime.parse(row['transaction_date']),
      newBalance: (row['new_balance'] as num).toDouble(),
      transactionCost: (row['transaction_cost'] as num).toDouble(),
      isDebit: row['is_debit'] == 1,
      rawMessage: row['raw_message'],
      notes: row['notes'],
      linkedTransactionId: row['linked_transaction_id'],
      createdAt: DateTime.parse(row['created_at']),
    );
  }

  static MpesaTransactionType _parseTransactionType(String type) {
    return MpesaTransactionType.values.firstWhere(
      (e) => e.name.toUpperCase() == type.toUpperCase(),
    );
  }

  String get transactionTypeString => transactionType.name.toUpperCase();

  // Watch all MPESA transactions for user
  static Stream<List<MpesaTransaction>> watchUserTransactions() {
    final userId = getUserId();
    if (userId == null) return Stream.value([]);
    
    return db.watch('''
      SELECT * FROM $mpesaTransactionsTable 
      WHERE user_id = ? 
      ORDER BY transaction_date DESC, created_at DESC
    ''', parameters: [userId]).map((results) {
      return results.map(MpesaTransaction.fromRow).toList(growable: false);
    });
  }

  // Watch only unlinked (pending) MPESA transactions
  static Stream<List<MpesaTransaction>> watchPendingTransactions() {
    final userId = getUserId();
    if (userId == null) return Stream.value([]);
    
    return db.watch('''
      SELECT * FROM $mpesaTransactionsTable 
      WHERE user_id = ? AND linked_transaction_id IS NULL
      ORDER BY transaction_date DESC, created_at DESC
    ''', parameters: [userId]).map((results) {
      return results.map(MpesaTransaction.fromRow).toList(growable: false);
    });
  }

  // Watch all MPESA transactions with their linked transactions (JOIN query)
  static Stream<List<Map<String, dynamic>>> watchTransactionsWithLinks() {
    final userId = getUserId();
    if (userId == null) return Stream.value([]);
    
    return db.watch('''
      SELECT 
        m.*,
        t.title as linked_title,
        t.amount as linked_amount,
        t.type as linked_type,
        t.category_id as linked_category_id
      FROM $mpesaTransactionsTable m
      LEFT JOIN $transactionsTable t ON m.linked_transaction_id = t.id
      WHERE m.user_id = ?
      ORDER BY m.transaction_date DESC, m.created_at DESC
    ''', parameters: [userId]).map((results) {
      return results.map((row) => Map<String, dynamic>.from(row)).toList();
    });
  }

  // Create new MPESA transaction
  static Future<MpesaTransaction> create({
    required String transactionCode,
    required MpesaTransactionType transactionType,
    required double amount,
    required String counterpartyName,
    String? counterpartyNumber,
    required DateTime transactionDate,
    required double newBalance,
    required double transactionCost,
    required bool isDebit,
    required String rawMessage,
    String? notes,
  }) async {
    final userId = getUserId();
    if (userId == null) throw Exception('User not logged in');

    final now = DateTime.now().toIso8601String();
    final results = await db.execute('''
      INSERT INTO $mpesaTransactionsTable(
        id, user_id, transaction_code, transaction_type, amount,
        counterparty_name, counterparty_number, transaction_date,
        new_balance, transaction_cost, is_debit, raw_message,
        notes, linked_transaction_id, created_at
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      RETURNING *
    ''', [
      uuid.v4(),
      userId,
      transactionCode,
      transactionType.name.toUpperCase(),
      amount,
      counterpartyName,
      counterpartyNumber,
      transactionDate.toIso8601String(),
      newBalance,
      transactionCost,
      isDebit ? 1 : 0,
      rawMessage,
      notes,
      null, // linked_transaction_id starts as NULL
      now,
    ]);
    
    return MpesaTransaction.fromRow(results.first);
  }

  // lib/models/mpesa_transaction.dart - FIXED linkToTransaction method

/// Link this MPESA transaction to a regular transaction
/// This sets the foreign key relationship
Future<void> linkToTransaction(String transactionId) async {
  print('=== linkToTransaction called ===');
  print('MPESA ID: $id');
  print('Transaction Code: $transactionCode');
  print('Target Transaction ID: $transactionId');
  print('User ID: $userId');
  
  // Verify the transaction exists before linking
  final transaction = await Transaction.getById(transactionId);
  if (transaction == null) {
    throw Exception('Cannot link to non-existent transaction: $transactionId');
  }
  print('✓ Target transaction exists: ${transaction.title}');
  
  // Verify the transaction belongs to the same user
  if (transaction.userId != userId) {
    throw Exception('Cannot link MPESA transaction to transaction owned by different user');
  }
  print('✓ User ID matches');
  
  // CRITICAL: Update using transaction_code instead of id to avoid stale object issues
  final rowsAffected = await db.execute('''
    UPDATE mpesa_transactions 
    SET linked_transaction_id = ?
    WHERE transaction_code = ? AND user_id = ?
  ''', [transactionId, transactionCode, userId]);
  
  print('Rows affected: $rowsAffected');
  
  if (rowsAffected == 0) {
    print('⚠ WARNING: No rows updated - MPESA transaction may not exist');
    throw Exception('Failed to update MPESA transaction - not found in database');
  }
  
  print('✓ MPESA transaction $transactionCode linked to transaction $transactionId');
}

  /// Unlink from transaction (set foreign key to NULL)
  Future<void> unlink() async {
    await db.execute('''
      UPDATE $mpesaTransactionsTable 
      SET linked_transaction_id = NULL
      WHERE id = ?
    ''', [id]);
    
    print('✓ MPESA transaction $transactionCode unlinked');
  }

  /// Get the linked transaction if it exists
  Future<Transaction?> getLinkedTransaction() async {
    if (linkedTransactionId == null) return null;
    return await Transaction.getById(linkedTransactionId!);
  }

  /// Check if this MPESA transaction is linked to a regular transaction
  bool isLinked() {
    return linkedTransactionId != null;
  }

  /// Get all MPESA transactions for a specific regular transaction
  static Future<List<MpesaTransaction>> getByLinkedTransactionId(String transactionId) async {
    final results = await db.getAll('''
      SELECT * FROM $mpesaTransactionsTable 
      WHERE linked_transaction_id = ?
      ORDER BY transaction_date DESC
    ''', [transactionId]);
    
    return results.map(MpesaTransaction.fromRow).toList();
  }

  // Delete this MPESA transaction
  Future<void> delete() async {
    await db.execute(
      'DELETE FROM $mpesaTransactionsTable WHERE id = ?', 
      [id]
    );
  }

  // Check if transaction code already exists
  static Future<bool> exists(String transactionCode) async {
    final userId = getUserId();
    if (userId == null) return false;
    
    final result = await db.getOptional('''
      SELECT COUNT(*) as count FROM $mpesaTransactionsTable 
      WHERE user_id = ? AND transaction_code = ?
    ''', [userId, transactionCode]);
    
    return  (result?['count'] as int? ?? 0) > 0;
  }

  // Get by transaction code
  static Future<MpesaTransaction?> getByCode(String transactionCode) async {
    final userId = getUserId();
    if (userId == null) return null;
    
    final result = await db.getOptional('''
      SELECT * FROM $mpesaTransactionsTable 
      WHERE user_id = ? AND transaction_code = ?
    ''', [userId, transactionCode]);
    
    if (result == null) return null;
    return MpesaTransaction.fromRow(result);
  }

  // Get display name for UI
  String getDisplayName() {
    switch (transactionType) {
      case MpesaTransactionType.send:
        return 'Sent to $counterpartyName';
      case MpesaTransactionType.pochi:
        return 'Pochi: $counterpartyName';
      case MpesaTransactionType.till:
        return 'Paid to $counterpartyName';
      case MpesaTransactionType.paybill:
        return 'Paybill: $counterpartyName';
      case MpesaTransactionType.received:
        return 'Received from $counterpartyName';
    }
  }
}