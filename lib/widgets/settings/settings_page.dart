// lib/widgets/settings/settings_page.dart
import 'package:crud/widgets/mpesa/comprehensive_pending_page.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/mpesa_service.dart';
import '../../services/location_service.dart';
import '../../powersync.dart';
import '../auth/login_page.dart';
import '../common/status_app_bar.dart';
import '../mpesa/pending_mpesa_page.dart';
import '../../models/pending_mpesa.dart';


class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _smsPermission = false;
  bool _overlayPermission = false;
  bool _locationPermission = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
  }

  Future<void> _loadPermissions() async {
    final sms = await MpesaService.hasSmsPermission();
    final overlay = await MpesaService.hasOverlayPermission();
    final location = await LocationService.hasLocationPermission();
    
    if (mounted) {
      setState(() {
        _smsPermission = sms;
        _overlayPermission = overlay;
        _locationPermission = location;
      });
    }
  }

 

  Future<void> _handleSignOut() async {
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

  if (shouldSignOut != true || !mounted) return;

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
              Text('Signing out...'),
            ],
          ),
        ),
      ),
    ),
  );

  try {
    // Logout with timeout
    await logout().timeout(
      const Duration(seconds: 10),
      onTimeout: () async {
        // Force logout if taking too long
        print('Logout timeout - forcing sign out');
        await Supabase.instance.client.auth.signOut();
      },
    );
    
    if (!mounted) return;
    
    // Close loading dialog
    Navigator.of(context).pop();
    
    // Navigate to login page
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const LoginPage()),
      (route) => false,
    );
    
  } catch (e) {
    print('Sign out error: $e');
    
    if (!mounted) return;
    
    // Close loading dialog
    Navigator.of(context).pop();
    
    // Show error with force logout option
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Error signing out: $e'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Force Logout',
          textColor: Colors.white,
          onPressed: () async {
            await Supabase.instance.client.auth.signOut();
            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginPage()),
                (route) => false,
              );
            }
          },
        ),
      ),
    );
  }
}

  Future<void> _handleStartAfresh() async {
    final shouldProceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Text('Start Afresh'),
          ],
        ),
        content: const Text(
          'This will permanently delete ALL your transactions. '
          'Your categories will be preserved.\n\n'
          'This action cannot be undone!\n\n'
          'Enter your password to confirm.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (shouldProceed != true || !mounted) return;

    final password = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final passwordController = TextEditingController();
        return AlertDialog(
          title: const Text('Verify Password'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter your password to confirm deletion of all transactions:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    Navigator.pop(context, value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context, null);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final pass = passwordController.text;
                Navigator.pop(context, pass.trim().isNotEmpty ? pass : null);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('Verify'),
            ),
          ],
        );
      },
    );

    if (password == null || password.trim().isEmpty || !mounted) return;

    setState(() => _isLoading = true);

    bool passwordValid = false;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }

      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: user.email!,
        password: password,
      );

      passwordValid = response.session != null;
    } on AuthException catch (e) {
      passwordValid = false;
      print('Auth error: $e');
    } catch (e) {
      passwordValid = false;
      print('Error verifying password: $e');
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!passwordValid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Incorrect password. Operation cancelled.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Final Confirmation'),
        content: const Text(
          'Are you absolutely sure? This will delete ALL transactions permanently.',
        ),
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
            child: const Text('Yes, Delete All'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);

    try {
      await _deleteAllTransactions();

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All transactions deleted successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting transactions: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _deleteAllTransactions() async {
    final userId = getUserId();
    if (userId == null) throw Exception('User not logged in');

    await db.execute('''
      DELETE FROM transactions WHERE user_id = ?
    ''', [userId]);

    print('All transactions deleted for user: $userId');
  }

  Future<void> _requestSmsPermission() async {
    final granted = await MpesaService.requestSmsPermission();
    if (mounted) {
      setState(() => _smsPermission = granted);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            granted 
              ? 'SMS permission granted' 
              : 'SMS permission denied',
          ),
          backgroundColor: granted ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _requestOverlayPermission() async {
    await MpesaService.requestOverlayPermission();
    await Future.delayed(const Duration(seconds: 1));
    await _loadPermissions();
  }

  Future<void> _requestLocationPermission() async {
    final isDeniedForever = await LocationService.isPermissionDeniedForever();
    
    if (isDeniedForever) {
      if (mounted) {
        await LocationService.showOpenSettingsDialog(context);
      }
      return;
    }

    final granted = await LocationService.showLocationPermissionDialog(context);
    if (mounted) {
      setState(() => _locationPermission = granted);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            granted 
              ? 'Location permission granted' 
              : 'Location permission denied',
          ),
          backgroundColor: granted ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _handleClearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text(
          'This will clear all cached data and force a fresh sync from the server. '
          'You will not lose any data.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear Cache'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isLoading = true);

    try {
      await db.disconnectAndClear();
      
      final connector = SupabaseConnector();
      db.connect(connector: connector);

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cache cleared! Syncing fresh data...'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing cache: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    
    return Scaffold(
      appBar: const StatusAppBar(title: Text('Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // User Profile Section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: Colors.blue.shade100,
                          child: Icon(
                            Icons.person,
                            size: 48,
                            color: Colors.blue.shade700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          user?.email ?? 'No email',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'User ID: ${user?.id.substring(0, 8)}...',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

              
                // App Settings Section
                
                const SizedBox(height: 8),
                              
                // Danger Zone
                Text(
                  'Danger Zone',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red[700],
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.delete_sweep, color: Colors.orange),
                        title: const Text(
                          'Start Afresh',
                          style: TextStyle(color: Colors.orange),
                        ),
                        subtitle: const Text('Delete all transactions and start over'),
                        trailing: const Icon(Icons.chevron_right, color: Colors.orange),
                        onTap: _handleStartAfresh,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.logout, color: Colors.red),
                        title: const Text(
                          'Sign Out',
                          style: TextStyle(color: Colors.red),
                        ),
                        subtitle: const Text('Sign out of your account'),
                        trailing: const Icon(Icons.chevron_right, color: Colors.red),
                        onTap: _handleSignOut,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
    );
  }

  void _showSyncStatus() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sync Status'),
        content: StreamBuilder(
          stream: db.statusStream,
          builder: (context, snapshot) {
            final status = snapshot.data ?? db.currentStatus;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatusRow(
                  'Connected',
                  status.connected ? 'Yes' : 'No',
                  status.connected ? Colors.green : Colors.red,
                ),
                const SizedBox(height: 8),
                _buildStatusRow(
                  'Uploading',
                  status.uploading ? 'Yes' : 'No',
                  status.uploading ? Colors.blue : Colors.grey,
                ),
                const SizedBox(height: 8),
                _buildStatusRow(
                  'Downloading',
                  status.downloading ? 'Yes' : 'No',
                  status.downloading ? Colors.blue : Colors.grey,
                ),
                const SizedBox(height: 8),
                if (status.anyError != null) ...[
                  _buildStatusRow(
                    'Error',
                    status.anyError.toString(),
                    Colors.red,
                  ),
                ],
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Last Synced',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                ),
                Text(
                  status.lastSyncedAt != null
                      ? status.lastSyncedAt.toString()
                      : 'Never',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            );
          },
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

  Widget _buildStatusRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        Flexible(
          child: Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }

  void _showAboutDialog() {
    showAboutDialog(
      context: context,
      applicationName: 'Expense Tracker',
      applicationVersion: '1.0.0',
      applicationIcon: Icon(
        Icons.account_balance_wallet,
        size: 48,
        color: Colors.blue.shade700,
      ),
      children: [
        const SizedBox(height: 16),
        const Text(
          'A modern expense tracking app with automatic MPESA transaction detection and location tagging.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Built with Flutter and PowerSync for real-time synchronization.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Features:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text('• Automatic MPESA SMS detection'),
        const Text('• Location tagging for transactions'),
        const Text('• Real-time sync across devices'),
        const Text('• Detailed spending reports'),
        const Text('• Category management'),
        const Text('• Offline support'),
        const SizedBox(height: 16),
        const Text(
          'Need help?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text('Contact: support@expensetracker.app'),
      ],
    );
  }
}