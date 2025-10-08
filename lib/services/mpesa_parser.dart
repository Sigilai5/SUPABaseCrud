class MpesaTransaction {
  final String title;
  final double amount;
  final String type; // 'income' or 'expense'
  final String? recipient;
  final String? sender;
  final String transactionCode;
  final DateTime date;
  final String rawMessage;

  MpesaTransaction({
    required this.title,
    required this.amount,
    required this.type,
    this.recipient,
    this.sender,
    required this.transactionCode,
    required this.date,
    required this.rawMessage,
  });
}

class MpesaParser {
  static MpesaTransaction? parse(String message) {
    try {
      // Remove extra whitespace
      final cleanMessage = message.replaceAll(RegExp(r'\s+'), ' ').trim();
      
      // Extract transaction code
      final codeMatch = RegExp(r'([A-Z0-9]{10})').firstMatch(cleanMessage);
      final transactionCode = codeMatch?.group(1) ?? 'UNKNOWN';
      
      // Extract amount
      final amountMatch = RegExp(r'Ksh([\d,]+\.?\d*)').firstMatch(cleanMessage);
      if (amountMatch == null) return null;
      
      final amountStr = amountMatch.group(1)!.replaceAll(',', '');
      final amount = double.tryParse(amountStr);
      if (amount == null) return null;

      // Determine transaction type and extract details
      String type = 'expense';
      String title = 'MPESA Transaction';
      String? recipient;
      String? sender;

      if (cleanMessage.contains('received')) {
        // Money received - INCOME
        type = 'income';
        final senderMatch = RegExp(r'from\s+([A-Z\s]+)\s+\d').firstMatch(cleanMessage) ??
                           RegExp(r'from\s+(\d+)').firstMatch(cleanMessage);
        sender = senderMatch?.group(1)?.trim();
        title = sender != null ? 'Received from $sender' : 'Money Received';
        
      } else if (cleanMessage.contains('sent to')) {
        // Money sent - EXPENSE
        type = 'expense';
        final recipientMatch = RegExp(r'to\s+([A-Z\s]+)\s+\d').firstMatch(cleanMessage) ??
                              RegExp(r'to\s+(\d+)').firstMatch(cleanMessage);
        recipient = recipientMatch?.group(1)?.trim();
        title = recipient != null ? 'Sent to $recipient' : 'Money Sent';
        
      } else if (cleanMessage.contains('paid to')) {
        // Payment - EXPENSE
        type = 'expense';
        final merchantMatch = RegExp(r'to\s+([A-Z\s]+)\s').firstMatch(cleanMessage);
        recipient = merchantMatch?.group(1)?.trim();
        title = recipient != null ? 'Paid to $recipient' : 'Payment';
        
      } else if (cleanMessage.contains('withdrawn')) {
        // Withdrawal - EXPENSE
        type = 'expense';
        title = 'Cash Withdrawal';
        
      } else if (cleanMessage.contains('bought')) {
        // Airtime/goods - EXPENSE
        type = 'expense';
        if (cleanMessage.contains('airtime')) {
          title = 'Airtime Purchase';
        } else {
          title = 'Purchase';
        }
      }

      return MpesaTransaction(
        title: title,
        amount: amount,
        type: type,
        recipient: recipient,
        sender: sender,
        transactionCode: transactionCode,
        date: DateTime.now(),
        rawMessage: message,
      );
    } catch (e) {
      print('Error parsing MPESA message: $e');
      return null;
    }
  }
}