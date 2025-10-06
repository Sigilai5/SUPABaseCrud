// lib/widgets/categories/category_form.dart
import 'package:flutter/material.dart';
import '../../models/category.dart';

class CategoryForm extends StatefulWidget {
  final Category? category;

  const CategoryForm({super.key, this.category});

  @override
  State<CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<CategoryForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  String _type = 'expense';
  Color _selectedColor = Colors.blue;
  String _selectedIcon = 'category';
  bool _loading = false;

  // Predefined colors
  final List<Color> _colors = [
    Colors.red,
    Colors.pink,
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.lightBlue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.lightGreen,
    Colors.lime,
    Colors.yellow,
    Colors.amber,
    Colors.orange,
    Colors.deepOrange,
    Colors.brown,
    Colors.grey,
  ];

  // Predefined icons with names
  final Map<String, IconData> _icons = {
    'category': Icons.category,
    'work': Icons.work,
    'computer': Icons.computer,
    'restaurant': Icons.restaurant,
    'local_cafe': Icons.local_cafe,
    'fastfood': Icons.fastfood,
    'directions_car': Icons.directions_car,
    'directions_bus': Icons.directions_bus,
    'shopping_cart': Icons.shopping_cart,
    'shopping_bag': Icons.shopping_bag,
    'receipt': Icons.receipt,
    'receipt_long': Icons.receipt_long,
    'home': Icons.home,
    'apartment': Icons.apartment,
    'local_hospital': Icons.local_hospital,
    'medical_services': Icons.medical_services,
    'school': Icons.school,
    'menu_book': Icons.menu_book,
    'sports_esports': Icons.sports_esports,
    'sports_soccer': Icons.sports_soccer,
    'movie': Icons.movie,
    'theater_comedy': Icons.theater_comedy,
    'flight': Icons.flight,
    'train': Icons.train,
    'fitness_center': Icons.fitness_center,
    'pool': Icons.pool,
    'pets': Icons.pets,
    'spa': Icons.spa,
    'card_giftcard': Icons.card_giftcard,
    'redeem': Icons.redeem,
    'business': Icons.business,
    'business_center': Icons.business_center,
    'attach_money': Icons.attach_money,
    'payments': Icons.payments,
    'savings': Icons.savings,
    'account_balance': Icons.account_balance,
    'credit_card': Icons.credit_card,
    'smartphone': Icons.smartphone,
    'laptop': Icons.laptop,
    'headphones': Icons.headphones,
    'phone_android': Icons.phone_android,
  };

  @override
  void initState() {
    super.initState();
    if (widget.category != null) {
      _populateForm();
    }
  }

  void _populateForm() {
    final category = widget.category!;
    _nameController.text = category.name;
    _type = category.type;
    _selectedIcon = category.icon;
    _selectedColor = _parseColor(category.color);
  }

  Color _parseColor(String hexColor) {
    try {
      return Color(int.parse(hexColor.substring(1), radix: 16) + 0xFF000000);
    } catch (e) {
      return Colors.blue;
    }
  }

  String _colorToHex(Color color) {
    return '#${color.value.toRadixString(16).substring(2).toUpperCase()}';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    try {
      if (widget.category == null) {
        // Create new category
        await Category.create(
          name: _nameController.text.trim(),
          type: _type,
          color: _colorToHex(_selectedColor),
          icon: _selectedIcon,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${_nameController.text} created successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true);
        }
      } else {
        // Update existing category
        await widget.category!.update(
          name: _nameController.text.trim(),
          type: _type,
          color: _colorToHex(_selectedColor),
          icon: _selectedIcon,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${_nameController.text} updated successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category == null ? 'Add Category' : 'Edit Category'),
        actions: [
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Preview Card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text(
                      'Preview',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: _selectedColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        _icons[_selectedIcon],
                        color: _selectedColor,
                        size: 40,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _nameController.text.isEmpty
                          ? 'Category Name'
                          : _nameController.text,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getCategoryTypeLabel(_type),
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Name Field
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Category Name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label),
                hintText: 'e.g., Groceries, Salary, Entertainment',
              ),
              textCapitalization: TextCapitalization.words,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a category name';
                }
                if (value.trim().length < 2) {
                  return 'Name must be at least 2 characters';
                }
                if (value.trim().length > 50) {
                  return 'Name must be less than 50 characters';
                }
                return null;
              },
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 24),

            // Type Selection
            const Text(
              'Category Type',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'income',
                  label: Text('Income'),
                  icon: Icon(Icons.trending_up),
                ),
                ButtonSegment(
                  value: 'expense',
                  label: Text('Expense'),
                  icon: Icon(Icons.trending_down),
                ),
                ButtonSegment(
                  value: 'both',
                  label: Text('Both'),
                  icon: Icon(Icons.swap_horiz),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (Set<String> newSelection) {
                setState(() => _type = newSelection.first);
              },
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                _getTypeDescription(_type),
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Color Selection
            const Text(
              'Color',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _colors.map((color) {
                final isSelected = color == _selectedColor;
                return GestureDetector(
                  onTap: () => setState(() => _selectedColor = color),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? Colors.black : Colors.transparent,
                        width: 3,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: color.withOpacity(0.5),
                                blurRadius: 8,
                                spreadRadius: 2,
                              )
                            ]
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white, size: 28)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Icon Selection
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Icon',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_icons.length} icons available',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 280,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: _icons.length,
                itemBuilder: (context, index) {
                  final entry = _icons.entries.elementAt(index);
                  final isSelected = entry.key == _selectedIcon;

                  return GestureDetector(
                    onTap: () => setState(() => _selectedIcon = entry.key),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _selectedColor.withOpacity(0.2)
                            : Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              isSelected ? _selectedColor : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        entry.value,
                        color:
                            isSelected ? _selectedColor : Colors.grey[600],
                        size: 28,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 32),

            // Submit Button
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        widget.category == null
                            ? 'Add Category'
                            : 'Update Category',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // Cancel Button
            if (widget.category == null)
              TextButton(
                onPressed: _loading ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
          ],
        ),
      ),
    );
  }

  String _getCategoryTypeLabel(String type) {
    switch (type) {
      case 'income':
        return 'Income Only';
      case 'expense':
        return 'Expense Only';
      case 'both':
        return 'Income & Expense';
      default:
        return type;
    }
  }

  String _getTypeDescription(String type) {
    switch (type) {
      case 'income':
        return 'This category will only appear when adding income transactions';
      case 'expense':
        return 'This category will only appear when adding expense transactions';
      case 'both':
        return 'This category will appear for both income and expense transactions';
      default:
        return '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }
}