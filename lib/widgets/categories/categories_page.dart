// lib/widgets/categories/categories_page.dart
import 'package:flutter/material.dart';
import '../../models/category.dart';
import '../../powersync.dart';
import '../common/status_app_bar.dart';
import 'category_form.dart';

class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const StatusAppBar(title: Text('Categories')),
      body: StreamBuilder<List<Category>>(
        stream: Category.watchUserCategories(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      // Trigger rebuild
                      (context as Element).markNeedsBuild();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final categories = snapshot.data ?? [];

          if (categories.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.category_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'No categories yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap + to add your first category',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => _showCreateDefaultCategories(context),
                    icon: const Icon(Icons.auto_awesome),
                    label: const Text('Create Default Categories'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          // Group categories by type
          final incomeCategories = categories
              .where((cat) => cat.type == 'income' || cat.type == 'both')
              .toList();
          final expenseCategories = categories
              .where((cat) => cat.type == 'expense' || cat.type == 'both')
              .toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Summary Card
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildSummaryItem(
                        'Total',
                        categories.length.toString(),
                        Icons.category,
                        Colors.blue,
                      ),
                      _buildSummaryItem(
                        'Income',
                        incomeCategories.length.toString(),
                        Icons.trending_up,
                        Colors.green,
                      ),
                      _buildSummaryItem(
                        'Expense',
                        expenseCategories.length.toString(),
                        Icons.trending_down,
                        Colors.red,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Income Categories Section
              if (incomeCategories.isNotEmpty) ...[
                _buildSectionHeader(
                  'Income Categories',
                  Icons.trending_up,
                  Colors.green,
                ),
                const SizedBox(height: 8),
                ...incomeCategories.map((category) => CategoryItem(
                      category: category,
                      onEdit: () => _editCategory(context, category),
                      onDelete: () => _deleteCategory(context, category),
                    )),
                const SizedBox(height: 24),
              ],

              // Expense Categories Section
              if (expenseCategories.isNotEmpty) ...[
                _buildSectionHeader(
                  'Expense Categories',
                  Icons.trending_down,
                  Colors.red,
                ),
                const SizedBox(height: 8),
                ...expenseCategories.map((category) => CategoryItem(
                      category: category,
                      onEdit: () => _editCategory(context, category),
                      onDelete: () => _deleteCategory(context, category),
                    )),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddCategory(context),
        tooltip: 'Add Category',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildSummaryItem(
      String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  void _showAddCategory(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const CategoryForm(),
      ),
    );
  }

  void _editCategory(BuildContext context, Category category) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CategoryForm(category: category),
      ),
    );
  }

  void _deleteCategory(BuildContext context, Category category) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text(
          'Are you sure you want to delete "${category.name}"?\n\n'
          'Transactions using this category will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await category.delete();
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${category.name} deleted'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error deleting category: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showCreateDefaultCategories(BuildContext context) async {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Creating default categories...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await Category.createDefaultCategories();
      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Default categories created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

class CategoryItem extends StatelessWidget {
  final Category category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const CategoryItem({
    super.key,
    required this.category,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = _parseColor(category.color);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _getIconData(category.icon),
            color: color,
            size: 28,
          ),
        ),
        title: Text(
          category.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          _getCategoryTypeLabel(category.type),
          style: TextStyle(color: Colors.grey[600]),
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 8),
                  Text('Edit'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Text('Delete', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'edit') {
              onEdit();
            } else if (value == 'delete') {
              onDelete();
            }
          },
        ),
      ),
    );
  }

  Color _parseColor(String hexColor) {
    try {
      return Color(int.parse(hexColor.substring(1), radix: 16) + 0xFF000000);
    } catch (e) {
      return Colors.blue;
    }
  }

  IconData _getIconData(String iconName) {
    // Map common icon names to IconData
    final iconMap = {
      'work': Icons.work,
      'computer': Icons.computer,
      'restaurant': Icons.restaurant,
      'directions_car': Icons.directions_car,
      'shopping_cart': Icons.shopping_cart,
      'receipt': Icons.receipt,
      'home': Icons.home,
      'local_hospital': Icons.local_hospital,
      'school': Icons.school,
      'sports_esports': Icons.sports_esports,
      'movie': Icons.movie,
      'flight': Icons.flight,
      'fitness_center': Icons.fitness_center,
      'pets': Icons.pets,
      'card_giftcard': Icons.card_giftcard,
      'business': Icons.business,
      'attach_money': Icons.attach_money,
      'savings': Icons.savings,
      'category': Icons.category,
    };

    return iconMap[iconName] ?? Icons.category;
  }

  String _getCategoryTypeLabel(String type) {
    switch (type) {
      case 'income':
        return 'Income only';
      case 'expense':
        return 'Expense only';
      case 'both':
        return 'Income & Expense';
      default:
        return type;
    }
  }
}