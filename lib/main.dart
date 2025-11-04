// lib/main.dart - Updated with automatic pending transaction check
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'powersync.dart';
import 'services/mpesa_service.dart';
import 'services/location_service.dart';
import 'services/theme_service.dart';
import 'widgets/auth/login_page.dart';
import 'widgets/transactions/transaction_list.dart';
import 'widgets/transactions/transaction_form.dart';
import 'widgets/categories/categories_page.dart';
import 'widgets/reports/reports_page.dart';
import 'widgets/settings/settings_page.dart';
import 'widgets/sms/sms_messages_page.dart';
import 'models/transaction.dart';

// Global navigator key for notification navigation
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  WidgetsFlutterBinding.ensureInitialized();
  
  await openDatabase();
  await MpesaService.initialize();
  await MpesaService.processPendingTransactions();

  final loggedIn = isLoggedIn();
  
  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeService(),
      child: ExpenseTrackerApp(loggedIn: loggedIn),
    ),
  );
}

class ExpenseTrackerApp extends StatelessWidget {
  final bool loggedIn;

  const ExpenseTrackerApp({super.key, required this.loggedIn});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        return MaterialApp(
          navigatorKey: navigatorKey,
          title: 'Expense Tracker',
          theme: AppThemes.lightTheme,
          darkTheme: AppThemes.darkTheme,
          themeMode: themeService.themeMode,
          home: loggedIn ? const HomePage() : const LoginPage(),
        );
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  bool _hasCheckedPending = false; // Track if we've checked for pending transactions

  final List<String> _pageTitles = [
    'Transactions',
    'Categories',
    'Reports',
  ];

  final List<Widget> _pages = [
    const TransactionList(),
    const CategoriesPage(),
    const ReportsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _checkAndProcessPendingTransactions(); // Check for pending transactions on startup
  }

  Future<void> _checkAndProcessPendingTransactions() async {
    // Avoid checking multiple times
    if (_hasCheckedPending) return;
    _hasCheckedPending = true;

    // Wait a bit for the UI to settle
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      print('=== Checking for pending transactions on app startup ===');
      
      // Get pending transactions from SharedPreferences
      final List<dynamic>? pendingList = await MpesaService.getPendingTransactionsFromSharedPrefs();
      
      if (pendingList != null && pendingList.isNotEmpty && mounted) {
        print('Found ${pendingList.length} pending transaction(s) - opening form for first one');
        
        // Get the first pending transaction
        final firstPending = Map<String, dynamic>.from(pendingList.first);
        
        // Extract transaction details
        final title = firstPending['title'] as String? ?? 'Unknown';
        final amount = (firstPending['amount'] as num?)?.toDouble() ?? 0.0;
        final type = firstPending['type'] as String? ?? 'expense';
        final transactionCode = firstPending['transactionCode'] as String? ?? '';
        final notes = firstPending['notes'] as String?;
        
        print('Opening transaction form for: $title - KES $amount');
        
        // Navigate to transaction form with the pending transaction data
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TransactionForm(
              initialTitle: title,
              initialAmount: amount,
              initialType: type == 'income' ? TransactionType.income : TransactionType.expense,
              initialNotes: notes,
              initialMpesaCode: transactionCode,
            ),
          ),
        );
        
        // After returning from transaction form, remove this transaction from pending
        if (transactionCode.isNotEmpty) {
          try {
            const platform = MethodChannel('com.example.crud/mpesa');
            await platform.invokeMethod('removePendingTransaction', {
              'transactionCode': transactionCode,
            });
            print('✓ Removed pending transaction: $transactionCode');
          } catch (e) {
            print('Error removing pending transaction: $e');
          }
        }
        
        // Check if there are more pending transactions and show a snackbar
        final remainingList = await MpesaService.getPendingTransactionsFromSharedPrefs();
        if (mounted && remainingList != null && remainingList.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text('${remainingList.length} more pending ${remainingList.length == 1 ? 'transaction' : 'transactions'}'),
                  ),
                ],
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'View All',
                textColor: Colors.white,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const SmsMessagesPage(),
                    ),
                  );
                },
              ),
            ),
          );
        }
      } else {
        print('No pending transactions found in SharedPreferences');
      }
    } catch (e, stackTrace) {
      print('✗ Error checking pending transactions: $e');
      print('Stack trace: $stackTrace');
    }
  }

  Future<void> _checkPermissions() async {
    // Check SMS permission
    final hasSms = await MpesaService.hasSmsPermission();
    if (!hasSms) {
      await MpesaService.requestSmsPermission();
    }

    // Check Overlay permission
    final hasOverlay = await MpesaService.hasOverlayPermission();
    if (!hasOverlay && mounted) {
      _showOverlayPermissionDialog();
    }

    // Check Location permission
    final hasLocation = await LocationService.hasLocationPermission();
    if (!hasLocation && mounted) {
      await LocationService.showLocationPermissionDialog(context);
    }
  }

  void _showOverlayPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enable Auto-Detection'),
        content: const Text(
          'Allow overlay permission to automatically detect and confirm MPESA transactions from SMS.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              MpesaService.requestOverlayPermission();
            },
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(_pageTitles[_selectedIndex]),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () {
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
      ),
      drawer: const AppDrawer(),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.list),
            label: 'Transactions',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.category),
            label: 'Categories',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.analytics),
            label: 'Reports',
          ),
        ],
      ),
    );
  }
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              height: 180,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          Colors.blue.shade900,
                          Colors.blue.shade700,
                        ]
                      : [
                          Colors.blue.shade700,
                          Colors.blue.shade500,
                        ],
                ),
              ),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    child: Icon(
                      Icons.account_balance_wallet,
                      size: 32,
                      color: Colors.blue.shade700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Expense Tracker',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Manage your finances',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            
            ListTile(
              leading: const Icon(Icons.list),
              title: const Text('Transactions'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.category),
              title: const Text('Categories'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.analytics),
              title: const Text('Reports'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            
            const Divider(),
            
            // MPESA SMS Button
            ListTile(
              leading: const Icon(Icons.message, color: Colors.green),
              title: const Text('MPESA SMS'),
              subtitle: const Text('View all MPESA messages'),
              trailing: const Icon(Icons.chevron_right, size: 18),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const SmsMessagesPage(),
                  ),
                );
              },
            ),
            
            const Divider(),
            
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const SettingsPage(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Help & Support'),
              onTap: () {
                Navigator.pop(context);
                _showHelpDialog(context);
              },
            ),
            
            const Divider(),
            
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  'Sign Out',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  final shouldSignOut = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Sign Out'),
                      content: const Text('Are you sure you want to sign out?'),
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
                          child: const Text('Sign Out'),
                        ),
                      ],
                    ),
                  );

                  if (shouldSignOut == true && context.mounted) {
                    await logout();
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (context) => const LoginPage()),
                        (route) => false,
                      );
                    }
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Help & Support'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Getting Started',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(
                '1. Enable SMS and Notification permissions in Settings\n'
                '2. Create categories for your transactions\n'
                '3. Add transactions manually or let them auto-detect from MPESA SMS\n'
                '4. View reports to track your spending',
              ),
              SizedBox(height: 16),
              Text(
                'Features',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text('• Automatic MPESA SMS detection\n'
                  '• Instant notifications with Add/Dismiss buttons\n'
                  '• Location tagging for transactions\n'
                  '• Light & Dark themes\n'
                  '• Real-time sync across devices\n'
                  '• Detailed spending reports\n'
                  '• Category management\n'
                  '• Offline support\n'
                  '• View all MPESA SMS messages'),
              SizedBox(height: 16),
              Text(
                'Need more help?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              SizedBox(height: 8),
              Text('Contact us at support@expensetracker.app'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}