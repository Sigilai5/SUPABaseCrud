import 'package:powersync/powersync.dart';
import 'package:powersync/sqlite_async.dart';

final migrations = SqliteMigrations();

/// Configure and run all database migrations
Future<void> configureMigrations(PowerSyncDatabase db) async {
  // Existing migrations...
  // Example:
  // migrations.add(SqliteMigration(1, (tx) async {
  //   await tx.execute('CREATE TABLE transactions (...)');
  // }));

  // ✅ Migration 2: Add mpesa_code column to transactions
  migrations.add(SqliteMigration(2, (tx) async {
    // Add mpesa_code column if not already present
    await tx.execute('ALTER TABLE transactions ADD COLUMN mpesa_code TEXT;');

    // Create an index for quick lookups
    await tx.execute('CREATE INDEX IF NOT EXISTS mpesa_code_index ON transactions (mpesa_code);');
  }));

  // Apply migrations
  await migrations.run(db);
}

extension on SqliteMigrations {
  run(PowerSyncDatabase db) {}
}
