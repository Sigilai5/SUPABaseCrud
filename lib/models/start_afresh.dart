// lib/models/start_afresh.dart
import 'package:powersync/sqlite3_common.dart' as sqlite;
import '../powersync.dart';
import 'schema.dart';

class StartAfresh {
  final String userId;
  final DateTime startTime;
  final DateTime createdAt;
  final DateTime updatedAt;

  StartAfresh({
    required this.userId,
    required this.startTime,
    required this.createdAt,
    required this.updatedAt,
  });

  factory StartAfresh.fromRow(sqlite.Row row) {
    return StartAfresh(
      userId: row['user_id'],
      startTime: DateTime.parse(row['start_time']),
      createdAt: DateTime.parse(row['created_at']),
      updatedAt: DateTime.parse(row['updated_at']),
    );
  }

  /// Get the start afresh record for the current user
  static Future<StartAfresh?> getForCurrentUser() async {
    final userId = getUserId();
    if (userId == null) return null;
    
    final result = await db.getOptional('''
      SELECT * FROM $startAfreshTable 
      WHERE user_id = ?
    ''', [userId]);
    
    if (result == null) return null;
    return StartAfresh.fromRow(result);
  }

  /// Create initial start afresh record for a new user
  /// This is called when user signs up
  static Future<StartAfresh> createInitial() async {
    final userId = getUserId();
    if (userId == null) throw Exception('User not logged in');

    final now = DateTime.now().toIso8601String();
    
    final results = await db.execute('''
      INSERT INTO $startAfreshTable(
        id, user_id, start_time, created_at, updated_at
      ) VALUES(?, ?, ?, ?, ?)
      RETURNING *
    ''', [
      uuid.v4(),
      userId,
      now, // start_time defaults to now
      now,
      now,
    ]);
    
    return StartAfresh.fromRow(results.first);
  }

  /// Update the start time to now - this is the "Start Afresh" action
  /// This effectively resets the user's tracking period
  static Future<StartAfresh> resetStartTime() async {
    final userId = getUserId();
    if (userId == null) throw Exception('User not logged in');

    final now = DateTime.now().toIso8601String();
    
    // Update existing record
    await db.execute('''
      UPDATE $startAfreshTable 
      SET start_time = ?, updated_at = ?
      WHERE user_id = ?
    ''', [now, now, userId]);
    
    // Return the updated record
    final record = await getForCurrentUser();
    if (record == null) {
      throw Exception('Failed to update start afresh record');
    }
    
    return record;
  }

  /// Check if a record exists for the current user
  static Future<bool> exists() async {
    final userId = getUserId();
    if (userId == null) return false;
    
    final result = await db.getOptional('''
      SELECT COUNT(*) as count FROM $startAfreshTable 
      WHERE user_id = ?
    ''', [userId]);
    
    return (result?['count'] as int? ?? 0) > 0;
  }

  /// Get the start time for the current user
  /// Returns null if no record exists
  static Future<DateTime?> getStartTime() async {
    final record = await getForCurrentUser();
    return record?.startTime;
  }

  /// Initialize start afresh record if it doesn't exist
  /// This should be called after user signs up or logs in
  static Future<void> ensureExists() async {
    final exists = await StartAfresh.exists();
    if (!exists) {
      await createInitial();
      print('✓ Created initial start_afresh record');
    }
  }
}