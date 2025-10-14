// lib/widgets/common/mpesa_link_badge.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/transaction.dart';
import '../../models/mpesa_transaction.dart';

/// Widget to display MPESA transaction link badge on regular transactions
/// Shows when a transaction was created from an MPESA SMS
class MpesaLinkBadge extends StatelessWidget {
  final Transaction transaction;
  final bool showDetails;

  const MpesaLinkBadge({
    super.key, 
    required this.transaction,
    this.showDetails = false,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MpesaTransaction?>(
      future: transaction.getPrimaryLinkedMpesaTransaction(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        
        final mpesa = snapshot.data!;
        
        if (showDetails) {
          return _buildDetailedBadge(context, mpesa);
        }
        
        return _buildCompactBadge(context, mpesa);
      },
    );
  }

  Widget _buildCompactBadge(BuildContext context, MpesaTransaction mpesa) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.link,
            size: 12,
            color: Colors.green.shade700,
          ),
          const SizedBox(width: 4),
          Text(
            'MPESA: ${mpesa.transactionCode}',
            style: TextStyle(
              fontSize: 10,
              color: Colors.green.shade900,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedBadge(BuildContext context, MpesaTransaction mpesa) {
    return InkWell(
      onTap: () => _showMpesaDetails(context, mpesa),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.verified,
                  size: 16,
                  color: Colors.green.shade700,
                ),
                const SizedBox(width: 8),
                Text(
                  'From MPESA Transaction',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildInfoRow(
              Icons.tag,
              'Code',
              mpesa.transactionCode,
              Colors.green.shade700,
            ),
            const SizedBox(height: 4),
            _buildInfoRow(
              Icons.access_time,
              'Date',
              DateFormat('MMM dd, yyyy • h:mm a').format(mpesa.transactionDate),
              Colors.grey.shade700,
            ),
            if (mpesa.transactionCost > 0) ...[
              const SizedBox(height: 4),
              _buildInfoRow(
                Icons.receipt,
                'Fee',
                'KES ${NumberFormat('#,##0.00').format(mpesa.transactionCost)}',
                Colors.grey.shade700,
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Tap to view details',
              style: TextStyle(
                fontSize: 10,
                color: Colors.green.shade600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  void _showMpesaDetails(BuildContext context, MpesaTransaction mpesa) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.phone_android,
                        color: Colors.green.shade700,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MPESA Details',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[800],
                            ),
                          ),
                          Text(
                            mpesa.getDisplayName(),
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                
                // Transaction details
                _buildDetailRow('Transaction Code', mpesa.transactionCode),
                _buildDetailRow('Type', mpesa.transactionType.name.toUpperCase()),
                _buildDetailRow('Amount', 'KES ${NumberFormat('#,##0.00').format(mpesa.amount)}'),
                _buildDetailRow('Counterparty', mpesa.counterpartyName),
                
                if (mpesa.counterpartyNumber != null)
                  _buildDetailRow(
                    mpesa.transactionType == MpesaTransactionType.paybill ? 'Account' : 'Phone',
                    mpesa.counterpartyNumber!,
                  ),
                
                _buildDetailRow(
                  'Date & Time',
                  DateFormat('EEEE, MMMM dd, yyyy • h:mm:ss a').format(mpesa.transactionDate),
                ),
                _buildDetailRow('New Balance', 'KES ${NumberFormat('#,##0.00').format(mpesa.newBalance)}'),
                
                if (mpesa.transactionCost > 0)
                  _buildDetailRow('Transaction Fee', 'KES ${NumberFormat('#,##0.00').format(mpesa.transactionCost)}'),
                
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                
                // Original SMS
                Text(
                  'Original SMS Message',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: SelectableText(
                    mpesa.rawMessage,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                      height: 1.5,
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Close button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget to display transaction link badge on MPESA transactions
/// Shows when an MPESA transaction has been converted to a regular transaction
class TransactionLinkBadge extends StatelessWidget {
  final MpesaTransaction mpesaTransaction;
  final bool showDetails;

  const TransactionLinkBadge({
    super.key,
    required this.mpesaTransaction,
    this.showDetails = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!mpesaTransaction.isLinked()) return const SizedBox.shrink();
    
    return FutureBuilder<Transaction?>(
      future: mpesaTransaction.getLinkedTransaction(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        
        final transaction = snapshot.data!;
        
        if (showDetails) {
          return _buildDetailedBadge(context, transaction);
        }
        
        return _buildCompactBadge(context, transaction);
      },
    );
  }

  Widget _buildCompactBadge(BuildContext context, Transaction transaction) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long,
            size: 12,
            color: Colors.blue.shade700,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Linked: ${transaction.title}',
              style: TextStyle(
                fontSize: 10,
                color: Colors.blue.shade900,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedBadge(BuildContext context, Transaction transaction) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle,
                size: 16,
                color: Colors.blue.shade700,
              ),
              const SizedBox(width: 8),
              Text(
                'Already Recorded',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.title, size: 12, color: Colors.grey.shade700),
              const SizedBox(width: 6),
              Text(
                'Title: ',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),
              Expanded(
                child: Text(
                  transaction.title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade700),
              const SizedBox(width: 6),
              Text(
                'Date: ',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                DateFormat('MMM dd, yyyy').format(transaction.date),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Simple indicator that shows a transaction was created from MPESA
class MpesaOriginIndicator extends StatelessWidget {
  final Transaction transaction;

  const MpesaOriginIndicator({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: transaction.hasLinkedMpesaTransaction(),
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();
        
        return Tooltip(
          message: 'Created from MPESA SMS',
          child: Icon(
            Icons.phone_android,
            size: 16,
            color: Colors.green.shade700,
          ),
        );
      },
    );
  }
}

/// Badge showing count of linked MPESA transactions
class MpesaCountBadge extends StatelessWidget {
  final Transaction transaction;

  const MpesaCountBadge({super.key, required this.transaction});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MpesaTransaction>>(
      future: transaction.getLinkedMpesaTransactions(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }
        
        final count = snapshot.data!.length;
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.green.shade700,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.link,
                size: 10,
                color: Colors.white,
              ),
              const SizedBox(width: 3),
              Text(
                '$count',
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}