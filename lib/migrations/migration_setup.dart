// // lib/migrations/migration_setup.dart

// import 'package:powersync/powersync.dart';
// import 'package:powersync/sqlite_async.dart';

// final migrations = SqliteMigrations();

// /// Configure and run all database migrations
// Future<void> configureMigrations(PowerSyncDatabase db) async {
//   // Migration 1: Initial setup
//   migrations.add(SqliteMigration(1, (tx) async {
//     // Create custom indexes for better query performance
//     await tx.execute(r'''
//       CREATE INDEX IF NOT EXISTS idx_transactions_amount 
//       ON ps_data_transactions (json_extract(data, '$.amount'));
//     ''');
    
//     // Create a view for quick balance calculations
//     await tx.execute(r'''
//       CREATE VIEW IF NOT EXISTS user_balance AS
//       SELECT 
//         json_extract(data, '$.user_id') as user_id,
//         SUM(CASE 
//           WHEN json_extract(data, '$.type') = 'income' 
//           THEN CAST(json_extract(data, '$.amount') AS REAL)
//           ELSE 0 
//         END) as total_income,
//         SUM(CASE 
//           WHEN json_extract(data, '$.type') = 'expense' 
//           THEN CAST(json_extract(data, '$.amount') AS REAL)
//           ELSE 0 
//         END) as total_expenses,
//         SUM(CASE 
//           WHEN json_extract(data, '$.type') = 'income' 
//           THEN CAST(json_extract(data, '$.amount') AS REAL)
//           WHEN json_extract(data, '$.type') = 'expense' 
//           THEN -CAST(json_extract(data, '$.amount') AS REAL)
//           ELSE 0 
//         END) as balance
//       FROM ps_data_transactions
//       GROUP BY json_extract(data, '$.user_id');
//     ''');
//   }));

//   // Migration 2: Add transaction summary view
//   migrations.add(SqliteMigration(2, (tx) async {
//     await tx.execute(r'''
//       CREATE VIEW IF NOT EXISTS monthly_transaction_summary AS
//       SELECT 
//         json_extract(data, '$.user_id') as user_id,
//         json_extract(data, '$.type') as type,
//         strftime('%Y-%m', json_extract(data, '$.date')) as month,
//         COUNT(*) as transaction_count,
//         SUM(CAST(json_extract(data, '$.amount') AS REAL)) as total_amount
//       FROM ps_data_transactions
//       GROUP BY 
//         json_extract(data, '$.user_id'),
//         json_extract(data, '$.type'),
//         strftime('%Y-%m', json_extract(data, '$.date'));
//     ''');
//   }));

//   // Migration 3: Add category spending view
//   migrations.add(SqliteMigration(3, (tx) async {
//     await tx.execute(r'''
//       CREATE VIEW IF NOT EXISTS category_spending AS
//       SELECT 
//         json_extract(t.data, '$.user_id') as user_id,
//         json_extract(t.data, '$.category_id') as category_id,
//         json_extract(c.data, '$.name') as category_name,
//         json_extract(t.data, '$.type') as type,
//         COUNT(*) as transaction_count,
//         SUM(CAST(json_extract(t.data, '$.amount') AS REAL)) as total_amount,
//         AVG(CAST(json_extract(t.data, '$.amount') AS REAL)) as avg_amount
//       FROM ps_data_transactions t
//       LEFT JOIN ps_data_categories c 
//         ON json_extract(t.data, '$.category_id') = json_extract(c.data, '$.id')
//       GROUP BY 
//         json_extract(t.data, '$.user_id'),
//         json_extract(t.data, '$.category_id'),
//         json_extract(c.data, '$.name'),
//         json_extract(t.data, '$.type');
//     ''');
//   }));

//   // Migration 4: Add local-only tags table
//   migrations.add(SqliteMigration(4, (tx) async {
//     await tx.execute(r'''
//       CREATE TABLE IF NOT EXISTS local_transaction_tags (
//         transaction_id TEXT NOT NULL,
//         tag TEXT NOT NULL,
//         created_at TEXT DEFAULT (datetime('now')),
//         PRIMARY KEY (transaction_id, tag)
//       );
//     ''');
    
//     await tx.execute(r'''
//       CREATE INDEX IF NOT EXISTS idx_local_tags_transaction 
//       ON local_transaction_tags (transaction_id);
//     ''');
    
//     await tx.execute(r'''
//       CREATE INDEX IF NOT EXISTS idx_local_tags_tag 
//       ON local_transaction_tags (tag);
//     ''');
//   }));

//   // Migration 5: Add search optimization
//   migrations.add(SqliteMigration(5, (tx) async {
//     // Create virtual FTS table for full-text search
//     await tx.execute(r'''
//       CREATE VIRTUAL TABLE IF NOT EXISTS transactions_fts 
//       USING fts5(
//         id UNINDEXED,
//         title,
//         notes,
//         content='ps_data_transactions',
//         content_rowid='rowid'
//       );
//     ''');
    
//     // Trigger to keep FTS table in sync with transactions
//     await tx.execute(r'''
//       CREATE TRIGGER IF NOT EXISTS transactions_fts_insert 
//       AFTER INSERT ON ps_data_transactions BEGIN
//         INSERT INTO transactions_fts(id, title, notes)
//         VALUES (
//           json_extract(new.data, '$.id'),
//           json_extract(new.data, '$.title'),
//           json_extract(new.data, '$.notes')
//         );
//       END;
//     ''');
    
//     await tx.execute(r'''
//       CREATE TRIGGER IF NOT EXISTS transactions_fts_update 
//       AFTER UPDATE ON ps_data_transactions BEGIN
//         UPDATE transactions_fts 
//         SET 
//           title = json_extract(new.data, '$.title'),
//           notes = json_extract(new.data, '$.notes')
//         WHERE id = json_extract(old.data, '$.id');
//       END;
//     ''');
    
//     await tx.execute(r'''
//       CREATE TRIGGER IF NOT EXISTS transactions_fts_delete 
//       AFTER DELETE ON ps_data_transactions BEGIN
//         DELETE FROM transactions_fts 
//         WHERE id = json_extract(old.data, '$.id');
//       END;
//     ''');
//   }));

//   // Run all pending migrations
//   await migrations.migrate(db);
// }

// // Helper function to check current migration version
// Future<int> getCurrentMigrationVersion(PowerSyncDatabase db) async {
//   final result = await db.getOptional(
//     'SELECT user_version FROM pragma_user_version'
//   );
//   return result?['user_version'] as int? ?? 0;
// }
