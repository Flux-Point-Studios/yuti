import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  /// Master kill-switch. When true, the app runs in local guest mode: no
  /// account, no login/signup, no Supabase auth or database traffic. The SDK
  /// is still initialized (so `client` stays valid and stray calls fail soft
  /// instead of crashing), but nothing here talks to the backend. Flip to
  /// false to restore the full account system.
  static const bool disabled = true;

  // Production Supabase configuration
  static const String _prodSupabaseUrl =
      'https://zlvcevggynsrmvyiaxru.supabase.co';
  static const String _prodSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpsdmNldmdneW5zcm12eWlheHJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzM3NTMxOTIsImV4cCI6MjA0OTMyOTE5Mn0.CJvntljVFvnrLk0suvStENcBqdHylJEGQkb209fJDFY';

  // Local development Supabase configuration
  static const String _localSupabaseUrl = 'http://127.0.0.1:54321';
  static const String _localSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';

  // Use local development in debug mode, production otherwise
  static bool get _useLocalDev =>
      kDebugMode &&
      const bool.fromEnvironment('USE_LOCAL_SUPABASE', defaultValue: false);

  static String get _supabaseUrl =>
      _useLocalDev ? _localSupabaseUrl : _prodSupabaseUrl;
  static String get _supabaseAnonKey =>
      _useLocalDev ? _localSupabaseAnonKey : _prodSupabaseAnonKey;

  static const List<String> _adminEmails = [
    'contact@fluxpointstudios.com',
    'nathanielminton@fluxpointstudios.com',
    'fluxpointstudios@gmail.com',
    'fluxpointpartner1@fluxpointstudios.com',
    'decimalist@protonmail.com',
  ];

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    if (disabled) {
      print('🔧 Supabase DISABLED — local guest mode (no auth/database).');
    } else {
      print('🔧 Supabase Config: ${_useLocalDev ? "LOCAL DEV" : "PRODUCTION"}');
      print('📡 URL: $_supabaseUrl');
    }

    // Always initialize the SDK so `client` is valid and any stray call fails
    // soft rather than throwing. Wrapped so a bad init never blocks app boot.
    try {
      await Supabase.initialize(
        url: _supabaseUrl,
        anonKey: _supabaseAnonKey,
        debug: _useLocalDev,
      );
    } catch (e) {
      print('Supabase.initialize failed (continuing without it): $e');
    }
  }

  static bool isAdminEmail(String? email) {
    return email != null && _adminEmails.contains(email);
  }

  // Helper methods for environment info
  static bool get isLocalDevelopment => _useLocalDev;
  static bool get isProduction => !_useLocalDev;
  static String get currentEnvironment =>
      _useLocalDev ? 'Local Development' : 'Production';
  static String get currentDatabaseUrl => _supabaseUrl;

  // For debugging and development
  static void printConnectionInfo() {
    print('🌐 Supabase Connection Info:');
    print('   Environment: $currentEnvironment');
    print('   URL: $currentDatabaseUrl');
    print('   Debug Mode: ${_useLocalDev}');
    print('   Flutter Debug Mode: ${kDebugMode}');
  }
}
