// lib/debug/schema_checker_page.dart
// Add this page to your app to check the local SQLite schema

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../powersync.dart';

class SchemaCheckerPage extends StatefulWidget {
  const SchemaCheckerPage({super.key});

  @override
  State<SchemaCheckerPage> createState() => _SchemaCheckerPageState();
}

class _SchemaCheckerPageState extends State<SchemaCheckerPage> {
  Map<String, List<Map<String, dynamic>>> _tableSchemas = {};
  Map<String, List<Map<String, dynamic>>> _indexes = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkSchema();
  }

  Future<void> _checkSchema() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Check transactions table
      final transactionsSchema = await _getTableSchema('transactions');
      final transactionsIndexes = await _getTableIndexes('transactions');

      // Check categories table
      final categoriesSchema = await _getTableSchema('categories');
      final categoriesIndexes = await _getTableIndexes('categories');

      // Check pending_mpesa table
      final pendingMpesaSchema = await _getTableSchema('pending_mpesa');
      final pendingMpesaIndexes = await _getTableIndexes('pending_mpesa');

      setState(() {
        _tableSchemas = {
          'transactions': transactionsSchema,
          'categories': categoriesSchema,
          'pending_mpesa': pendingMpesaSchema,
        };
        _indexes = {
          'transactions': transactionsIndexes,
          'categories': categoriesIndexes,
          'pending_mpesa': pendingMpesaIndexes,
        };
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _getTableSchema(String tableName) async {
    try {
      final results = await db.getAll('PRAGMA table_info($tableName)');
      return results.map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _getTableIndexes(String tableName) async {
    try {
      final results = await db.getAll('PRAGMA index_list($tableName)');
      return results.map((row) => Map<String, dynamic>.from(row)).toList();
    } catch (e) {
      return [];
    }
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied to clipboard!')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Schema Checker'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkSchema,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text('Error: $_error'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _checkSchema,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildSummaryCard(),
                    const SizedBox(height: 16),
                    ..._tableSchemas.entries.map((entry) {
                      return _buildTableCard(entry.key, entry.value);
                    }),
                    const SizedBox(height: 16),
                    _buildIndexesCard(),
                    const SizedBox(height: 16),
                    _buildComparisonCard(),
                  ],
                ),
    );
  }

  Widget _buildSummaryCard() {
    final totalTables = _tableSchemas.keys.length;
    final totalColumns = _tableSchemas.values
        .fold(0, (sum, schema) => sum + schema.length);
    final totalIndexes = _indexes.values
        .fold(0, (sum, indexes) => sum + indexes.length);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Schema Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem('Tables', totalTables, Icons.table_chart),
                _buildSummaryItem('Columns', totalColumns, Icons.view_column),
                _buildSummaryItem('Indexes', totalIndexes, Icons.speed),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, int count, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 32, color: Colors.blue),
        const SizedBox(height: 4),
        Text(
          count.toString(),
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        Text(label, style: TextStyle(color: Colors.grey[600])),
      ],
    );
  }

  Widget _buildTableCard(String tableName, List<Map<String, dynamic>> schema) {
    if (schema.isEmpty) {
      return Card(
        color: Colors.red.shade50,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.error, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(
                    tableName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Table not found! This table may be missing from your database.',
                style: TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Row(
            children: [
              const Icon(Icons.table_chart, size: 20),
              const SizedBox(width: 8),
              Text(
                tableName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${schema.length} columns',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Columns:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: () {
                          final text = schema
                              .map((col) =>
                                  '${col['name']}: ${col['type']} ${col['notnull'] == 1 ? 'NOT NULL' : 'NULLABLE'}')
                              .join('\n');
                          _copyToClipboard(text);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ...schema.map((column) {
                    final isRequired = column['notnull'] == 1;
                    final isPrimaryKey = column['pk'] == 1;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isPrimaryKey
                                  ? Colors.amber
                                  : isRequired
                                      ? Colors.blue
                                      : Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              column['name'],
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              column['type'],
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          if (isPrimaryKey) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'PK',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                          if (isRequired && !isPrimaryKey) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'REQ',
                                style: TextStyle(fontSize: 10),
                              ),
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIndexesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Indexes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ..._indexes.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    if (entry.value.isEmpty)
                      const Text(
                        'No indexes found',
                        style: TextStyle(color: Colors.orange),
                      )
                    else
                      ...entry.value.map((index) {
                        return Padding(
                          padding: const EdgeInsets.only(left: 16, top: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.speed, size: 16, color: Colors.blue),
                              const SizedBox(width: 8),
                              Text(index['name']),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonCard() {
    final expectedTables = ['transactions', 'categories', 'pending_mpesa'];
    final missingTables = expectedTables
        .where((table) =>
            !_tableSchemas.containsKey(table) ||
            _tableSchemas[table]!.isEmpty)
        .toList();

    final expectedColumns = {
      'transactions': [
        'id', 'user_id', 'title', 'amount', 'type', 'category_id',
        'budget_id', 'date', 'notes', 'created_at', 'updated_at'
      ],
      'categories': [
        'id', 'user_id', 'name', 'type', 'color', 'icon', 'created_at'
      ],
      'pending_mpesa': [
        'id', 'user_id', 'raw_message', 'sender', 'transaction_code',
        'amount', 'type', 'parsed_title', 'received_at', 'created_at'
      ],
    };

    final Map<String, List<String>> missingColumns = {};
    for (var entry in expectedColumns.entries) {
      final tableName = entry.key;
      final expected = entry.value;
      if (_tableSchemas.containsKey(tableName)) {
        final actual = _tableSchemas[tableName]!
            .map((col) => col['name'] as String)
            .toList();
        final missing = expected.where((col) => !actual.contains(col)).toList();
        if (missing.isNotEmpty) {
          missingColumns[tableName] = missing;
        }
      }
    }

    final hasIssues = missingTables.isNotEmpty || missingColumns.isNotEmpty;

    return Card(
      color: hasIssues ? Colors.orange.shade50 : Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  hasIssues ? Icons.warning : Icons.check_circle,
                  color: hasIssues ? Colors.orange : Colors.green,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Schema Validation',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!hasIssues)
              const Text(
                '✓ All expected tables and columns are present!',
                style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500),
              )
            else ...[
              if (missingTables.isNotEmpty) ...[
                const Text(
                  'Missing Tables:',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red),
                ),
                ...missingTables.map((table) => Padding(
                      padding: const EdgeInsets.only(left: 16, top: 4),
                      child: Text('• $table'),
                    )),
                const SizedBox(height: 8),
              ],
              if (missingColumns.isNotEmpty) ...[
                const Text(
                  'Missing Columns:',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.orange),
                ),
                ...missingColumns.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(left: 16, top: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${entry.key}:',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        ...entry.value.map((col) => Padding(
                              padding: const EdgeInsets.only(left: 16, top: 2),
                              child: Text('• $col'),
                            )),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ],
        ),
      ),
    );
  }
}