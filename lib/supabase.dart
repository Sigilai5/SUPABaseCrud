// lib/supabase.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_config.dart';

/// Initialize Supabase
/// This must be called before using any Supabase features
Future<void> loadSupabase() async {
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
    debug: false, // Set to true for debugging
  );
}