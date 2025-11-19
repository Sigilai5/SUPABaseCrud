// lib/models/discarded_mpesa.dart
import 'package:powersync/sqlite3_common.dart' as sqlite;
import '../powersync.dart';
import 'schema.dart';

/// Model for MPESA transactions that the user has explicitly discarded
/// These won't appear in the pending list anymore
class DiscardedMpesa {
  final String id;
  final String userId;
  final String transactionCode;
  final String transactionType;
  final double amount;
  final String counterpartyName;
  final String? counterpartyNumber;
  final DateTime transactionDate;
  final bool isDebit;
  final String rawMessage;
  final DateTime discardedAt;
  final String? discardReason;

  DiscardedMpesa({
    required this.id,
    required this.userId,
    required this.transactionCode,
    required this.transactionType,
    required this.amount,
    required this.counterpartyName,
    this.counterpartyNumber,
    required this.transactionDate,
    required this.isDebit,
    required this.rawMessage,
    required this.discardedAt,
    this.discardReason,
  });

  factory DiscardedMpesa.fromRow(sqlite.Row row) {
    return DiscardedMpesa(
      id: row['id'],
      userId: row['user_id'],
      transactionCode: row['transaction_code'],
      transactionType: row['transaction_type'],
      amount: (row['amount'] as num).toDouble(),
      counterpartyName: row['counterparty_name'],
      counterpartyNumber: row['counterparty_number'],
      transactionDate: DateTime.parse(row['transaction_date']),
      isDebit: row['is_debit'] == 1,
      rawMessage: row['raw_message'],
      discardedAt: DateTime.parse(row['discarded_at']),
      discardReason: row['discard_reason'],
    );
  }

  /// Create a new discarded MPESA entry
  static Future<DiscardedMpesa> create({
    required String transactionCode,
    required String transactionType,
    required double amount,
    required String counterpartyName,
    String? counterpartyNumber,
    required DateTime transactionDate,
    required bool isDebit,
    required String rawMessage,
    String? discardReason,
  }) async {
    final userId = getUserId();
    if (userId == null) throw Exception('User not logged in');

    final now = DateTime.now().toIso8601String();
    
    final results = await db.execute('''
      INSERT INTO $discardedMpesaTable(
        id, user_id, transaction_code, transaction_type, amount,
        counterparty_name, counterparty_number, transaction_date,
        is_debit, raw_message, discarded_at, discard_reason
      ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      RETURNING *
    ''', [
      uuid.v4(),
      userId,
      transactionCode,
      transactionType,
      amount,
      counterpartyName,
      counterpartyNumber,
      transactionDate.toIso8601String(),
      isDebit ? 1 : 0,
      rawMessage,
      now,
      discardReason,
    ]);
    
    print('✓ Discarded MPESA transaction saved: $transactionCode');
    return DiscardedMpesa.fromRow(results.first);
  }

  /// Check if a transaction code has been discarded
  static Future<bool> isDiscarded(String transactionCode) async {
    final userId = getUserId();
    if (userId == null) return false;
    
    final result = await db.getOptional('''
      SELECT COUNT(*) as count FROM $discardedMpesaTable 
      WHERE user_id = ? AND transaction_code = ?
    ''', [userId, transactionCode]);
    
    return (result?['count'] as int? ?? 0) > 0;
  }

  /// Get discarded transaction by code
  static Future<DiscardedMpesa?> getByCode(String transactionCode) async {
    final userId = getUserId();
    if (userId == null) return null;
    
    final result = await db.getOptional('''
      SELECT * FROM $discardedMpesaTable 
      WHERE user_id = ? AND transaction_code = ?
    ''', [userId, transactionCode]);
    
    if (result == null) return null;
    return DiscardedMpesa.fromRow(result);
  }

  /// Watch all discarded transactions for current user
  static Stream<List<DiscardedMpesa>> watchUserDiscarded() {
    final userId = getUserId();
    if (userId == null) return Stream.value([]);
    
    return db.watch('''
      SELECT * FROM $discardedMpesaTable 
      WHERE user_id = ? 
      ORDER BY discarded_at DESC
    ''', parameters: [userId]).map((results) {
      return results.map(DiscardedMpesa.fromRow).toList(growable: false);
    });
  }

  /// Get count of discarded transactions
  static Future<int> getDiscardedCount() async {
    final userId = getUserId();
    if (userId == null) return 0;
    
    final result = await db.getOptional('''
      SELECT COUNT(*) as count FROM $discardedMpesaTable 
      WHERE user_id = ?
    ''', [userId]);
    
    return (result?['count'] as int?) ?? 0;
  }

  /// Delete this discarded entry (restore to pending)
  Future<void> delete() async {
    await db.execute(
      'DELETE FROM $discardedMpesaTable WHERE id = ?', 
      [id]
    );
    print('✓ Removed from discarded: $transactionCode');
  }

  /// Clear all discarded transactions for current user
  static Future<void> clearAll() async {
    final userId = getUserId();
    if (userId == null) return;
    
    await db.execute(
      'DELETE FROM $discardedMpesaTable WHERE user_id = ?', 
      [userId]
    );
    print('✓ Cleared all discarded MPESA transactions');
  }
}