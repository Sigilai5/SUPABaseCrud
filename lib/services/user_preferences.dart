// lib/services/user_preferences.dart
import 'package:shared_preferences/shared_preferences.dart';

/// Service to manage user preferences and app state
class UserPreferences {
  // Keys for SharedPreferences
  static const String _firstTransactionKey = 'first_transaction_timestamp';
  
  /// Sets the timestamp when the user recorded their first transaction
  /// This marks when the user started actively tracking their finances
  static Future<void> setFirstTransactionTime(DateTime timestamp) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_firstTransactionKey, timestamp.millisecondsSinceEpoch);
      print('✓ First transaction time set: $timestamp');
    } catch (e) {
      print('✗ Error setting first transaction time: $e');
      rethrow;
    }
  }
  
  /// Gets the timestamp when the user recorded their first transaction
  /// Returns null if no transaction has been recorded yet
  static Future<DateTime?> getFirstTransactionTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timestamp = prefs.getInt(_firstTransactionKey);
      
      if (timestamp == null) {
        return null;
      }
      
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    } catch (e) {
      print('✗ Error getting first transaction time: $e');
      return null;
    }
  }
  
  /// Checks if the user has recorded at least one transaction
  /// This determines if we should start tracking pending MPESA messages
  static Future<bool> hasRecordedFirstTransaction() async {
    final firstTransactionTime = await getFirstTransactionTime();
    return firstTransactionTime != null;
  }
  
  /// Clears the first transaction timestamp
  /// Useful for testing or resetting the app state
  static Future<void> clearFirstTransactionTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_firstTransactionKey);
      print('✓ First transaction time cleared');
    } catch (e) {
      print('✗ Error clearing first transaction time: $e');
      rethrow;
    }
  }
  
  /// Gets a human-readable string of when tracking started
  /// Returns "Not started" if no transaction has been recorded
  static Future<String> getTrackingStartedMessage() async {
    final firstTime = await getFirstTransactionTime();
    
    if (firstTime == null) {
      return 'Not started tracking yet';
    }
    
    final now = DateTime.now();
    final difference = now.difference(firstTime);
    
    if (difference.inDays > 0) {
      return 'Tracking since ${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return 'Tracking since ${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return 'Tracking since ${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Tracking started just now';
    }
  }
}