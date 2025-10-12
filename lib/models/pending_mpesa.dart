// lib/models/pending_mpesa.dart
class PendingMpesa {
  final String id;
  final String userId;
  final String rawMessage;
  final String sender;
  final String? transactionCode;
  final double? amount;
  final String? type; // 'income' or 'expense'
  final String? parsedTitle;
  final DateTime receivedAt;
  final DateTime createdAt;

  PendingMpesa({
    required this.id,
    required this.userId,
    required this.rawMessage,
    required this.sender,
    this.transactionCode,
    this.amount,
    this.type,
    this.parsedTitle,
    required this.receivedAt,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'raw_message': rawMessage,
      'sender': sender,
      'transaction_code': transactionCode,
      'amount': amount,
      'type': type,
      'parsed_title': parsedTitle,
      'received_at': receivedAt.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory PendingMpesa.fromJson(Map<String, dynamic> json) {
    return PendingMpesa(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      rawMessage: json['raw_message'] as String,
      sender: json['sender'] as String,
      transactionCode: json['transaction_code'] as String?,
      amount: json['amount'] != null ? (json['amount'] as num).toDouble() : null,
      type: json['type'] as String?,
      parsedTitle: json['parsed_title'] as String?,
      receivedAt: DateTime.parse(json['received_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}