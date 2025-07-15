import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static const String _supabaseUrl = 'https://zlvcevggynsrmvyiaxru.supabase.co';
  static const String _supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpsdmNldmdneW5zcm12eWlheHJ1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzM3NTMxOTIsImV4cCI6MjA0OTMyOTE5Mn0.CJvntljVFvnrLk0suvStENcBqdHylJEGQkb209fJDFY';

  static const List<String> _adminEmails = [
    'contact@fluxpointstudios.com',
    'nathanielminton@fluxpointstudios.com',
    'fluxpointstudios@gmail.com',
    'fluxpointpartner1@fluxpointstudios.com',
    'decimalist@protonmail.com',
  ];

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
      debug: false,
    );
  }

  static bool isAdminEmail(String? email) {
    return email != null && _adminEmails.contains(email);
  }
}
