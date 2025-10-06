// lib/models/category.dart
import 'package:powersync/sqlite3_common.dart' as sqlite;
import '../powersync.dart';
import 'schema.dart';

class Category {
  final String id;
  final String userId;
  final String name;
  final String type; // 'income', 'expense', or 'both'
  final String color;
  final String icon;
  final DateTime createdAt;

  Category({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    required this.color,
    required this.icon,
    required this.createdAt,
  });

  factory Category.fromRow(sqlite.Row row) {
    return Category(
      id: row['id'],
      userId: row['user_id'],
      name: row['name'],
      type: row['type'],
      color: row['color'],
      icon: row['icon'],
      createdAt: DateTime.parse(row['created_at']),
    );
  }

  // Watch user categories
  static Stream<List<Category>> watchUserCategories() {
    final userId = getUserId();
    if (userId == null) return Stream.value([]);
    
    return db.watch('''
      SELECT * FROM $categoriesTable 
      WHERE user_id = ? 
      ORDER BY name ASC
    ''', parameters: [userId]).map((results) {
      return results.map(Category.fromRow).toList(growable: false);
    });
  }

  // Create default categories for new user
  static Future<void> createDefaultCategories() async {
    final userId = getUserId();
    if (userId == null) throw Exception('User not logged in');

    final defaultCategories = [
      {'name': 'Salary', 'type': 'income', 'color': '#4CAF50', 'icon': 'work'},
      {'name': 'Freelance', 'type': 'income', 'color': '#2196F3', 'icon': 'computer'},
      {'name': 'Business', 'type': 'income', 'color': '#9C27B0', 'icon': 'business'},
      {'name': 'Food', 'type': 'expense', 'color': '#FF9800', 'icon': 'restaurant'},
      {'name': 'Transport', 'type': 'expense', 'color': '#607D8B', 'icon': 'directions_car'},
      {'name': 'Shopping', 'type': 'expense', 'color': '#E91E63', 'icon': 'shopping_cart'},
      {'name': 'Bills', 'type': 'expense', 'color': '#F44336', 'icon': 'receipt'},
      {'name': 'Entertainment', 'type': 'expense', 'color': '#673AB7', 'icon': 'movie'},
      {'name': 'Health', 'type': 'expense', 'color': '#009688', 'icon': 'local_hospital'},
    ];

    for (final category in defaultCategories) {
      await create(
        name: category['name']!,
        type: category['type']!,
        color: category['color']!,
        icon: category['icon']!,
      );
    }
  }

  // Create new category
  static Future<Category> create({
    required String name,
    required String type,
    required String color,
    required String icon,
  }) async {
    final userId = getUserId();
    if (userId == null) throw Exception('User not logged in');

    final now = DateTime.now().toIso8601String();
    final results = await db.execute('''
      INSERT INTO $categoriesTable(
        id, user_id, name, type, color, icon, created_at
      ) VALUES(?, ?, ?, ?, ?, ?, ?)
      RETURNING *
    ''', [
      uuid.v4(),
      userId,
      name,
      type,
      color,
      icon,
      now,
    ]);
    
    return Category.fromRow(results.first);
  }

  // Update category
  Future<void> update({
    String? name,
    String? type,
    String? color,
    String? icon,
  }) async {
    await db.execute('''
      UPDATE $categoriesTable SET
        name = COALESCE(?, name),
        type = COALESCE(?, type),
        color = COALESCE(?, color),
        icon = COALESCE(?, icon)
      WHERE id = ?
    ''', [
      name,
      type,
      color,
      icon,
      id,
    ]);
  }

  // Delete category
  Future<void> delete() async {
    await db.execute('DELETE FROM $categoriesTable WHERE id = ?', [id]);
  }

  // Get category by ID
  static Future<Category?> getById(String categoryId) async {
    final result = await db.getOptional(
      'SELECT * FROM $categoriesTable WHERE id = ?',
      [categoryId],
    );
    
    if (result == null) return null;
    return Category.fromRow(result);
  }

  // Get categories by type
  static Stream<List<Category>> watchCategoriesByType(String type) {
    final userId = getUserId();
    if (userId == null) return Stream.value([]);
    
    return db.watch('''
      SELECT * FROM $categoriesTable 
      WHERE user_id = ? AND (type = ? OR type = 'both')
      ORDER BY name ASC
    ''', parameters: [userId, type]).map((results) {
      return results.map(Category.fromRow).toList(growable: false);
    });
  }

  // Count transactions using this category
  Future<int> getTransactionCount() async {
    final result = await db.getOptional('''
      SELECT COUNT(*) as count FROM transactions 
      WHERE category_id = ?
    ''', [id]);
    
    return (result?['count'] as int?) ?? 0;
  }
}