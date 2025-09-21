import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_colors.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';

class AuthCallbackScreen extends StatefulWidget {
  const AuthCallbackScreen({Key? key}) : super(key: key);

  @override
  State<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends State<AuthCallbackScreen> {
  String _status = 'Completing sign-in...';
  bool _isProcessing = true;

  @override
  void initState() {
    super.initState();
    _handleAuthCallback();
  }

  Future<void> _handleAuthCallback() async {
    try {
      final uri = Uri.base;
      final auth = SupabaseService.client.auth;

      // Prefer PKCE code exchange when available
      final code = uri.queryParameters['code'];
      if (code != null && code.isNotEmpty) {
        await auth.exchangeCodeForSession(code);
      } else {
        // Fallback for implicit flows and magic links that contain access token in URL
        await auth.getSessionFromUrl(uri);
      }

      // Ensure our app user/session is hydrated
      final authService = AuthService();
      await authService.initialize();
      await authService.refreshUser();

      setState(() {
        _status = 'Sign-in complete. Redirecting...';
      });

      await Future.delayed(const Duration(milliseconds: 600));

      if (!mounted) return;
      // Route to pricing if FREE, else to chat
      if (authService.currentUser?.tier == 'FREE') {
        Navigator.pushNamedAndRemoveUntil(context, '/pricing', (route) => false);
      } else {
        Navigator.pushNamedAndRemoveUntil(context, '/chat', (route) => false);
      }
    } catch (e) {
      setState(() {
        _status = 'Authentication link handling failed. ${kIsWeb ? 'Please try again or request a new link.' : ''}\n\nDetails: ${e.toString()}';
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock_open, color: AppColors.primaryBlue, size: 56),
              const SizedBox(height: 16),
              Text(
                _status,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (_isProcessing)
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
                )
              else
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamedAndRemoveUntil(context, '/welcome', (route) => false);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                  ),
                  child: const Text('Back to Home', style: TextStyle(color: Colors.white)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

