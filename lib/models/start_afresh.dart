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
      // Convert stored times to local timezone (Nairobi time in your case)
      startTime: DateTime.parse(row['start_time']).toLocal(),
      createdAt: DateTime.parse(row['created_at']).toLocal(),
      updatedAt: DateTime.parse(row['updated_at']).toLocal(),
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

    // Use local time
    final now = DateTime.now();
    final nowString = now.toIso8601String();
    
    print('Creating initial start_afresh record with local time: $now (${now.timeZoneName})');
    
    final results = await db.execute('''
      INSERT INTO $startAfreshTable(
        id, user_id, start_time, created_at, updated_at
      ) VALUES(?, ?, ?, ?, ?)
      RETURNING *
    ''', [
      uuid.v4(),
      userId,
      nowString, // start_time defaults to now (local time)
      nowString,
      nowString,
    ]);
    
    return StartAfresh.fromRow(results.first);
  }

  /// Update the start time to now - this is the "Start Afresh" action
  /// This effectively resets the user's tracking period
  static Future<StartAfresh> resetStartTime() async {
    final userId = getUserId();
    if (userId == null) throw Exception('User not logged in');

    // Use local time
    final now = DateTime.now();
    final nowString = now.toIso8601String();
    
    print('Resetting start_afresh to local time: $now (${now.timeZoneName})');
    
    // Update existing record
    await db.execute('''
      UPDATE $startAfreshTable 
      SET start_time = ?, updated_at = ?
      WHERE user_id = ?
    ''', [nowString, nowString, userId]);
    
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

  /// Get a formatted string showing the start time in local timezone
  String getFormattedStartTime() {
    return '${startTime.day}/${startTime.month}/${startTime.year} at ${startTime.hour}:${startTime.minute.toString().padLeft(2, '0')} (${startTime.timeZoneName})';
  }

  /// Get days since start time
  int getDaysSinceStart() {
    final now = DateTime.now();
    final difference = now.difference(startTime);
    return difference.inDays;
  }

  /// Check if the start time is today
  bool isToday() {
    final now = DateTime.now();
    return startTime.year == now.year &&
           startTime.month == now.month &&
           startTime.day == now.day;
  }
}