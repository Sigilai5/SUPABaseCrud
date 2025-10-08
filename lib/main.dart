import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'powersync.dart';
import 'services/mpesa_service.dart';  // Add this import
import 'widgets/auth/login_page.dart';
import 'widgets/transactions/transaction_list.dart';
import 'widgets/categories/categories_page.dart';
import 'widgets/reports/reports_page.dart';
import 'widgets/common/status_app_bar.dart';

void main() async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    print('${record.level.name}: ${record.time}: ${record.message}');
  });

  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize PowerSync database
  await openDatabase();
  
  // Initialize MPESA service
  await MpesaService.initialize();  // Add this line

  final loggedIn = isLoggedIn();
  runApp(ExpenseTrackerApp(loggedIn: loggedIn));
}

class ExpenseTrackerApp extends StatelessWidget {
  final bool loggedIn;

  const ExpenseTrackerApp({super.key, required this.loggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Expense Tracker',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: loggedIn ? const HomePage() : const LoginPage(),
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

  final List<Widget> _pages = [
    const TransactionList(),
    const CategoriesPage(),
    const ReportsPage(),
  ];

  @override
  void initState() {
    super.initState();
    _checkPermissions();  // Add this
  }

  Future<void> _checkPermissions() async {
    // Check and request SMS permission
    final hasSms = await MpesaService.hasSmsPermission();
    if (!hasSms) {
      await MpesaService.requestSmsPermission();
    }

    // Check and request overlay permission
    final hasOverlay = await MpesaService.hasOverlayPermission();
    if (!hasOverlay && mounted) {
      _showOverlayPermissionDialog();
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
      drawer: const AppDrawer(),
    );
  }
}

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Colors.blue),
            child: Text(
              'Expense Tracker',
              style: TextStyle(color: Colors.white, fontSize: 24),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('Settings'),
            onTap: () {
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign Out'),
            onTap: () async {
              Navigator.pop(context);
              await logout();
              if (context.mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}