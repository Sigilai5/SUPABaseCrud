// lib/models/schema.dart
import 'package:powersync/powersync.dart';

const transactionsTable = 'transactions';
const categoriesTable = 'categories';
const mpesaTransactionsTable = 'mpesa_transactions';
const startAfreshTable = 'start_afresh';

Schema schema = Schema([
  // Transactions table for income and expenses
  const Table(transactionsTable, [
    Column.text('user_id'),           // Owner of the transaction
    Column.text('title'),             // Transaction description
    Column.real('amount'),            // Amount (positive for income, negative for expense)
    Column.text('type'),              // 'income' or 'expense'
    Column.text('category_id'),       // Foreign key to categories
    Column.text('budget_id'),         // Budget reference
    Column.text('date'),              // Transaction date (ISO string)
    Column.text('notes'),             // Optional notes
    Column.real('latitude'),          // Location latitude
    Column.real('longitude'),         // Location longitude
    Column.text('created_at'),        // Creation timestamp
    Column.text('updated_at'),        // Last update timestamp
    Column.text('mpesa_code'),       // M-PESA transaction code (if applicable)
  ], indexes: [
    Index('user_transactions', [IndexedColumn('user_id')]),
    Index('transaction_date', [IndexedColumn('date')]),
    Index('transaction_type', [IndexedColumn('type')]),
    Index('transaction_category', [IndexedColumn('category_id')]),
    Index('transaction_budget', [IndexedColumn('budget_id')]),
    Index('mpesa_code_index', [IndexedColumn('mpesa_code')]),
  ]),
  
  // Categories table for organizing transactions
  const Table(categoriesTable, [
    Column.text('user_id'),           // Owner of the category
    Column.text('name'),              // Category name
    Column.text('type'),              // 'income' or 'expense' or 'both'
    Column.text('color'),             // Hex color for UI
    Column.text('icon'),              // Icon identifier
    Column.text('created_at'),        // Creation timestamp
  ], indexes: [
    Index('user_categories', [IndexedColumn('user_id')]),
    Index('category_type', [IndexedColumn('type')]),
  ]),

  // MPESA Transactions table - comprehensive storage for all MPESA messages
  const Table(mpesaTransactionsTable, [
    Column.text('user_id'),                 // Owner of the transaction
    Column.text('transaction_code'),        // MPESA code (e.g., TJ9JN6XFA2)
    Column.text('transaction_type'),        // SEND, POCHI, TILL, PAYBILL, RECEIVED
    Column.real('amount'),                  // Transaction amount
    Column.text('counterparty_name'),       // Person/business name
    Column.text('counterparty_number'),     // Phone number or account number
    Column.text('transaction_date'),        // When transaction occurred (ISO string)
    Column.real('new_balance'),             // M-PESA balance after transaction
    Column.real('transaction_cost'),        // Fee charged by M-PESA
    Column.integer('is_debit'),             // 1 = money out, 0 = money in
    Column.text('raw_message'),             // Original SMS for reference
    Column.text('notes'),                   // Auto-generated or user notes
    Column.text('linked_transaction_id'),   // FOREIGN KEY -> transactions.id (NULL if not converted)
    Column.text('created_at'),              // When recorded in app
  ], indexes: [
    Index('user_mpesa', [IndexedColumn('user_id')]),
    Index('mpesa_code', [IndexedColumn('transaction_code')]),
    Index('mpesa_date', [IndexedColumn('transaction_date')]),
    Index('mpesa_type', [IndexedColumn('transaction_type')]),
    Index('mpesa_linked', [IndexedColumn('linked_transaction_id')]),
  ]),

]);