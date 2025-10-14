// lib/services/mpesa_parser.dart
import '../models/mpesa_transaction.dart';

class MpesaTransactionData {
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

  MpesaTransactionData({
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
  });
}

class EnhancedMpesaParser {
  static MpesaTransactionData? parse(String message) {
    try {
      final cleanMessage = message.replaceAll(RegExp(r'\s+'), ' ').trim();
      
      // Extract transaction code (always at start)
      final codeMatch = RegExp(r'^([A-Z0-9]{10})').firstMatch(cleanMessage);
      if (codeMatch == null) return null;
      final transactionCode = codeMatch.group(1)!;

      // Extract amount
      final amountMatch = RegExp(r'Ksh([\d,]+\.?\d*)').firstMatch(cleanMessage);
      if (amountMatch == null) return null;
      final amount = double.parse(amountMatch.group(1)!.replaceAll(',', ''));

      // Extract new balance
      final balanceMatch = RegExp(r'balance is Ksh([\d,]+\.?\d*)').firstMatch(cleanMessage);
      if (balanceMatch == null) return null;
      final newBalance = double.parse(balanceMatch.group(1)!.replaceAll(',', ''));

      // Extract transaction cost
      final costMatch = RegExp(r'cost,?\s*Ksh([\d,]+\.?\d*)').firstMatch(cleanMessage);
      final transactionCost = costMatch != null 
          ? double.parse(costMatch.group(1)!.replaceAll(',', '')) 
          : 0.0;

      // Extract date and time from message
      final dateMatch = RegExp(r'on (\d{1,2}/\d{1,2}/\d{2}) at (\d{1,2}:\d{2} [AP]M)').firstMatch(cleanMessage);
      DateTime transactionDate = DateTime.now();
      
      if (dateMatch != null) {
        try {
          final dateStr = dateMatch.group(1)!; // e.g., "9/10/25"
          final timeStr = dateMatch.group(2)!; // e.g., "7:17 PM"
          
          // Parse date (format: d/M/yy)
          final dateParts = dateStr.split('/');
          final day = int.parse(dateParts[0]);
          final month = int.parse(dateParts[1]);
          final year = 2000 + int.parse(dateParts[2]); // Assuming 20xx
          
          // Parse time
          final timeParts = timeStr.split(' ');
          final hourMinute = timeParts[0].split(':');
          int hour = int.parse(hourMinute[0]);
          final minute = int.parse(hourMinute[1]);
          final isPM = timeParts[1] == 'PM';
          
          // Convert to 24-hour format
          if (isPM && hour != 12) {
            hour += 12;
          } else if (!isPM && hour == 12) {
            hour = 0;
          }
          
          transactionDate = DateTime(year, month, day, hour, minute);
        } catch (e) {
          print('Error parsing date/time, using current time: $e');
          // Fall back to current time if parsing fails
        }
      }

      // Determine transaction type and extract counterparty
      MpesaTransactionType type;
      String counterpartyName;
      String? counterpartyNumber;
      bool isDebit;

      if (cleanMessage.contains('You have received')) {
        // Money received - INCOME
        type = MpesaTransactionType.received;
        final nameMatch = RegExp(r'from ([A-Z\s]+) (\d+)').firstMatch(cleanMessage);
        counterpartyName = nameMatch?.group(1)?.trim() ?? 'Unknown';
        counterpartyNumber = nameMatch?.group(2);
        isDebit = false;

      } else if (cleanMessage.contains('sent to') && !cleanMessage.contains('paid to')) {
        // Check if it's Pochi La Biashara (has the sign-up link)
        if (cleanMessage.contains('Sign up for Lipa Na M-PESA Till')) {
          type = MpesaTransactionType.pochi;
          final nameMatch = RegExp(r'sent to ([A-Z\s]+) on').firstMatch(cleanMessage);
          counterpartyName = nameMatch?.group(1)?.trim() ?? 'Unknown';
          counterpartyNumber = null;
        } else {
          // Regular send money
          type = MpesaTransactionType.send;
          // Try to match name with phone number
          final nameMatch = RegExp(r'sent to ([A-Za-z\s]+) (\d+)').firstMatch(cleanMessage);
          if (nameMatch != null) {
            counterpartyName = nameMatch.group(1)?.trim() ?? 'Unknown';
            counterpartyNumber = nameMatch.group(2);
          } else {
            // Fallback if pattern doesn't match
            final altMatch = RegExp(r'sent to ([A-Z\s]+)').firstMatch(cleanMessage);
            counterpartyName = altMatch?.group(1)?.trim() ?? 'Unknown';
            counterpartyNumber = null;
          }
        }
        isDebit = true;

      } else if (cleanMessage.contains('paid to')) {
        // Lipa Na MPESA Till
        type = MpesaTransactionType.till;
        // Match pattern like "paid to THE GRILLMASTERS PORK JOINT & BUTCHERIES."
        final nameMatch = RegExp(r'paid to ([A-Z\s.&]+?)\.').firstMatch(cleanMessage);
        counterpartyName = nameMatch?.group(1)?.trim() ?? 'Unknown';
        counterpartyNumber = null;
        isDebit = true;

      } else if (cleanMessage.contains('for account')) {
        // Paybill payment
        type = MpesaTransactionType.paybill;
        // Match pattern like "sent to Equity Paybill Account for account 0716940147"
        final nameMatch = RegExp(r'sent to ([A-Za-z\s]+)\.?\s+for account').firstMatch(cleanMessage);
        counterpartyName = nameMatch?.group(1)?.trim() ?? 'Unknown';
        
        // Extract account number
        final accountMatch = RegExp(r'for account ([A-Z0-9]+)').firstMatch(cleanMessage);
        counterpartyNumber = accountMatch?.group(1);
        isDebit = true;

      } else {
        // Unknown format - return null
        print('Unknown MPESA message format');
        return null;
      }

      return MpesaTransactionData(
        transactionCode: transactionCode,
        transactionType: type,
        amount: amount,
        counterpartyName: counterpartyName,
        counterpartyNumber: counterpartyNumber,
        transactionDate: transactionDate,
        newBalance: newBalance,
        transactionCost: transactionCost,
        isDebit: isDebit,
        rawMessage: message,
      );

    } catch (e) {
      print('Error parsing MPESA message: $e');
      return null;
    }
  }

  // Helper method to get a user-friendly description
  static String getTransactionDescription(MpesaTransactionData data) {
    switch (data.transactionType) {
      case MpesaTransactionType.send:
        return 'Sent to ${data.counterpartyName}';
      case MpesaTransactionType.pochi:
        return 'Pochi: ${data.counterpartyName}';
      case MpesaTransactionType.till:
        return 'Paid to ${data.counterpartyName}';
      case MpesaTransactionType.paybill:
        return 'Paybill: ${data.counterpartyName}';
      case MpesaTransactionType.received:
        return 'Received from ${data.counterpartyName}';
    }
  }

  // Helper method to generate auto-notes
  static String generateNotes(MpesaTransactionData data) {
    final buffer = StringBuffer();
    buffer.write('MPESA ${data.transactionType.name.toUpperCase()}');
    buffer.write('\nCode: ${data.transactionCode}');
    
    if (data.counterpartyNumber != null) {
      buffer.write('\n${data.transactionType == MpesaTransactionType.paybill ? 'Account' : 'Phone'}: ${data.counterpartyNumber}');
    }
    
    if (data.transactionCost > 0) {
      buffer.write('\nFee: KES ${data.transactionCost.toStringAsFixed(2)}');
    }
    
    buffer.write('\nBalance: KES ${data.newBalance.toStringAsFixed(2)}');
    
    return buffer.toString();
  }
}