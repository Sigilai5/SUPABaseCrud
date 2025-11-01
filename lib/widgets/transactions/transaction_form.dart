// lib/widgets/transactions/transaction_form.dart - FIXED VERSION
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/transaction.dart';
import '../../models/category.dart';
import '../../services/location_service.dart';

class TransactionForm extends StatefulWidget {
  final Transaction? transaction;
  final String? initialTitle;
  final double? initialAmount;
  final TransactionType? initialType;
  final String? initialCategoryId;
  final String? initialNotes;
  final String? initialMpesaCode;  // ✓ ADDED THIS
  
  const TransactionForm({
    super.key, 
    this.transaction,
    this.initialTitle,
    this.initialAmount,
    this.initialType,
    this.initialCategoryId,
    this.initialNotes,
    this.initialMpesaCode,  // ✓ ADDED THIS
  });

  @override
  State<TransactionForm> createState() => _TransactionFormState();
}

class _TransactionFormState extends State<TransactionForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  TransactionType _type = TransactionType.expense;
  String? _selectedCategoryId;
  DateTime _selectedDate = DateTime.now();
  List<Category> _categories = [];
  bool _loading = false;
  
  // Location fields - captured automatically in background
  double? _latitude;
  double? _longitude;
  
  // ✓ ADDED THIS - Store MPESA code
  String? _mpesaCode;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    
    if (widget.transaction != null) {
      _populateForm();
    } else {
      // Populate with initial values if provided
      if (widget.initialTitle != null || widget.initialAmount != null) {
        _titleController.text = widget.initialTitle ?? '';
        if (widget.initialAmount != null) {
          _amountController.text = widget.initialAmount.toString();
        }
        _type = widget.initialType ?? TransactionType.expense;
        _selectedCategoryId = widget.initialCategoryId;
        _notesController.text = widget.initialNotes ?? '';
        _mpesaCode = widget.initialMpesaCode;  // ✓ ADDED THIS
      }
      
      // Auto-capture location in background for new transactions
      _captureLocationInBackground();
    }
  }

  void _populateForm() {
    final transaction = widget.transaction!;
    _titleController.text = transaction.title;
    _amountController.text = transaction.amount.toString();
    _type = transaction.type;
    _selectedCategoryId = transaction.categoryId;
    _selectedDate = transaction.date;
    _notesController.text = transaction.notes ?? '';
    _latitude = transaction.latitude;
    _longitude = transaction.longitude;
    _mpesaCode = transaction.mpesaCode;  // ✓ ADDED THIS
  }

  Future<void> _captureLocationInBackground() async {
    try {
      // Check if we have location permission
      final hasPermission = await LocationService.hasLocationPermission();
      if (!hasPermission) {
        print('Location permission not granted, skipping location capture');
        return;
      }

      // Get current position silently in background
      final position = await LocationService.getCurrentPosition();
      
      if (position != null && mounted) {
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
        });
        print('Location captured: $_latitude, $_longitude');
      }
    } catch (e) {
      print('Error capturing location in background: $e');
      // Silently fail - don't show error to user
    }
  }

  Future<void> _loadCategories() async {
    final categories = await Category.watchUserCategories().first;
    setState(() {
      _categories = categories;
      // If no category selected and we have categories, select the first appropriate one
      if (_selectedCategoryId == null && _categories.isNotEmpty) {
        final appropriateCategories = _categories
            .where((cat) => cat.type == _type.name || cat.type == 'both')
            .toList();
        if (appropriateCategories.isNotEmpty) {
          _selectedCategoryId = appropriateCategories.first.id;
        }
      }
    });
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  List<Category> get _filteredCategories {
    return _categories
        .where((cat) => cat.type == _type.name || cat.type == 'both')
        .toList();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a category'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final amount = double.parse(_amountController.text);
      
      if (widget.transaction == null) {
        // Create new transaction
        await Transaction.create(
          title: _titleController.text.trim(),
          amount: amount,
          type: _type,
          categoryId: _selectedCategoryId!,
          date: _selectedDate,
          notes: _notesController.text.trim().isEmpty 
              ? null 
              : _notesController.text.trim(),
          latitude: _latitude,
          longitude: _longitude,
          mpesaCode: _mpesaCode,  // ✓ ADDED THIS - Pass mpesaCode to database
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Transaction created successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true);
        }
      } else {
        // Update existing transaction
        await widget.transaction!.update(
          title: _titleController.text.trim(),
          amount: amount,
          type: _type,
          categoryId: _selectedCategoryId,
          date: _selectedDate,
          notes: _notesController.text.trim().isEmpty 
              ? null 
              : _notesController.text.trim(),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Transaction updated successfully!'),
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

  Future<void> _delete() async {
    if (widget.transaction == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Transaction'),
        content: const Text('Are you sure you want to delete this transaction?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);

    try {
      await widget.transaction!.delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Transaction deleted'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting: $e'),
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
        title: Text(widget.transaction == null 
            ? 'Add Transaction' 
            : 'Edit Transaction'),
        actions: [
          if (widget.transaction != null)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: _loading ? null : _delete,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ✓ ADDED THIS - Show MPESA badge if this is from MPESA
                  if (_mpesaCode != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.phone_android, color: Colors.green.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'MPESA Transaction',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade900,
                                  ),
                                ),
                                Text(
                                  'Code: $_mpesaCode',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Type selector
                  SegmentedButton<TransactionType>(
                    segments: const [
                      ButtonSegment(
                        value: TransactionType.expense,
                        label: Text('Expense'),
                        icon: Icon(Icons.trending_down),
                      ),
                      ButtonSegment(
                        value: TransactionType.income,
                        label: Text('Income'),
                        icon: Icon(Icons.trending_up),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (Set<TransactionType> newSelection) {
                      setState(() {
                        _type = newSelection.first;
                        // Reset category when type changes
                        final appropriateCategories = _filteredCategories;
                        if (appropriateCategories.isNotEmpty &&
                            !appropriateCategories.any((cat) => cat.id == _selectedCategoryId)) {
                          _selectedCategoryId = appropriateCategories.first.id;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 24),

                  // Title
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.title),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a title';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Amount
                  TextFormField(
                    controller: _amountController,
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter an amount';
                      }
                      if (double.tryParse(value) == null) {
                        return 'Please enter a valid number';
                      }
                      if (double.parse(value) <= 0) {
                        return 'Amount must be greater than 0';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Category
                  DropdownButtonFormField<String>(
                    value: _selectedCategoryId,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.category),
                    ),
                    items: _filteredCategories.map((category) {
                      return DropdownMenuItem(
                        value: category.id,
                        child: Text(category.name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _selectedCategoryId = value);
                    },
                    validator: (value) {
                      if (value == null) {
                        return 'Please select a category';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Date
                  InkWell(
                    onTap: _selectDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Date',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(DateFormat('MMM dd, yyyy').format(_selectedDate)),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Notes
                  TextFormField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.note),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 24),

                
                  // Submit button
                  ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text(
                      widget.transaction == null 
                          ? 'Add Transaction' 
                          : 'Update Transaction',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }
}