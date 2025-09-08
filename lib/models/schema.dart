import 'package:powersync/powersync.dart';

const transactionsTable = 'transactions';
const categoriesTable = 'categories';

Schema schema = Schema([
  // Transactions table for income and expenses
  const Table(transactionsTable, [
    Column.text('user_id'),           // Owner of the transaction
    Column.text('title'),             // Transaction description
    Column.real('amount'),            // Amount (positive for income, negative for expense)
    Column.text('type'),              // 'income' or 'expense'
    Column.text('category_id'),       // Foreign key to categories
    Column.text('date'),              // Transaction date (ISO string)
    Column.text('notes'),             // Optional notes
    Column.text('created_at'),        // Creation timestamp
    Column.text('updated_at'),        // Last update timestamp
  ], indexes: [
    Index('user_transactions', [IndexedColumn('user_id')]),
    Index('transaction_date', [IndexedColumn('date')]),
    Index('transaction_type', [IndexedColumn('type')]),
    Index('transaction_category', [IndexedColumn('category_id')]),
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
]);