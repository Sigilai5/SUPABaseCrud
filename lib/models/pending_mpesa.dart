// // lib/models/pending_mpesa.dart
// import 'package:powersync/sqlite3_common.dart' as sqlite;
// import '../powersync.dart';
// import 'schema.dart';

// class PendingMpesa {
//   final String id;
//   final String userId;
//   final String rawMessage;
//   final String sender;
//   final String? transactionCode;
//   final double? amount;
//   final String? type; // 'income' or 'expense'
//   final String? parsedTitle;
//   final DateTime receivedAt;
//   final DateTime createdAt;

//   PendingMpesa({
//     required this.id,
//     required this.userId,
//     required this.rawMessage,
//     required this.sender,
//     this.transactionCode,
//     this.amount,
//     this.type,
//     this.parsedTitle,
//     required this.receivedAt,
//     required this.createdAt,
//   });

//   Map<String, dynamic> toJson() {
//     return {
//       'id': id,
//       'user_id': userId,
//       'raw_message': rawMessage,
//       'sender': sender,
//       'transaction_code': transactionCode,
//       'amount': amount,
//       'type': type,
//       'parsed_title': parsedTitle,
//       'received_at': receivedAt.toIso8601String(),
//       'created_at': createdAt.toIso8601String(),
//     };
//   }

//   factory PendingMpesa.fromJson(Map<String, dynamic> json) {
//     return PendingMpesa(
//       id: json['id'] as String,
//       userId: json['user_id'] as String,
//       rawMessage: json['raw_message'] as String,
//       sender: json['sender'] as String,
//       transactionCode: json['transaction_code'] as String?,
//       amount: json['amount'] != null ? (json['amount'] as num).toDouble() : null,
//       type: json['type'] as String?,
//       parsedTitle: json['parsed_title'] as String?,
//       receivedAt: DateTime.parse(json['received_at'] as String),
//       createdAt: DateTime.parse(json['created_at'] as String),
//     );
//   }

//   factory PendingMpesa.fromRow(sqlite.Row row) {
//     return PendingMpesa(
//       id: row['id'],
//       userId: row['user_id'],
//       rawMessage: row['raw_message'],
//       sender: row['sender'],
//       transactionCode: row['transaction_code'],
//       amount: row['amount']?.toDouble(),
//       type: row['type'],
//       parsedTitle: row['parsed_title'],
//       receivedAt: DateTime.parse(row['received_at']),
//       createdAt: DateTime.parse(row['created_at']),
//     );
//   }

//   // Watch user pending messages
//   static Stream<List<PendingMpesa>> watchUserPendingMessages() {
//     final userId = getUserId();
//     if (userId == null) return Stream.value([]);
    
//     return db.watch('''
//       SELECT * FROM $pendingMpesaTable 
//       WHERE user_id = ? 
//       ORDER BY received_at DESC
//     ''', parameters: [userId]).map((results) {
//       return results.map(PendingMpesa.fromRow).toList(growable: false);
//     });
//   }

//   // Create new pending message
//   static Future<PendingMpesa> create({
//     required String rawMessage,
//     required String sender,
//     String? transactionCode,
//     double? amount,
//     String? type,
//     String? parsedTitle,
//     required DateTime receivedAt,
//   }) async {
//     final userId = getUserId();
//     if (userId == null) throw Exception('User not logged in');

//     final now = DateTime.now().toIso8601String();
//     final results = await db.execute('''
//       INSERT INTO $pendingMpesaTable(
//         id, user_id, raw_message, sender, transaction_code, 
//         amount, type, parsed_title, received_at, created_at
//       ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
//       RETURNING *
//     ''', [
//       uuid.v4(),
//       userId,
//       rawMessage,
//       sender,
//       transactionCode,
//       amount,
//       type,
//       parsedTitle,
//       receivedAt.toIso8601String(),
//       now,
//     ]);
    
//     return PendingMpesa.fromRow(results.first);
//   }

//   // Delete this pending message
//   Future<void> delete() async {
//     await db.execute(
//       'DELETE FROM $pendingMpesaTable WHERE id = ?', 
//       [id]
//     );
//   }

//   // Delete by transaction code
//   static Future<void> deleteByTransactionCode(String transactionCode) async {
//     final userId = getUserId();
//     if (userId == null) return;
    
//     await db.execute('''
//       DELETE FROM $pendingMpesaTable 
//       WHERE user_id = ? AND transaction_code = ?
//     ''', [userId, transactionCode]);
//   }

//   // Delete all pending messages for current user
//   static Future<void> deleteAll() async {
//     final userId = getUserId();
//     if (userId == null) return;
    
//     await db.execute(
//       'DELETE FROM $pendingMpesaTable WHERE user_id = ?', 
//       [userId]
//     );
//   }

//   // Get pending message by transaction code
//   static Future<PendingMpesa?> getByTransactionCode(String transactionCode) async {
//     final userId = getUserId();
//     if (userId == null) return null;
    
//     final result = await db.getOptional('''
//       SELECT * FROM $pendingMpesaTable 
//       WHERE user_id = ? AND transaction_code = ?
//     ''', [userId, transactionCode]);
    
//     if (result == null) return null;
//     return PendingMpesa.fromRow(result);
//   }
// }