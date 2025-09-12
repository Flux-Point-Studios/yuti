import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../services/smart_wallet_service.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';

class SmartWalletWebCallbackScreen extends StatefulWidget {
  const SmartWalletWebCallbackScreen({Key? key}) : super(key: key);

  @override
  State<SmartWalletWebCallbackScreen> createState() => _SmartWalletWebCallbackScreenState();
}

class _SmartWalletWebCallbackScreenState extends State<SmartWalletWebCallbackScreen> {
  final SmartWalletService _smart = SmartWalletService();
  final AuthService _auth = AuthService();
  String? _status;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _handleCallback();
  }

  Future<void> _ensureUserSession(String email) async {
    if (_auth.isAuthenticated) return; // already signed in
    try {
      // Try to find an existing user by email
      final existing = await SupabaseService.client
          .from('users')
          .select('id')
          .eq('email', email)
          .maybeSingle();

      if (existing == null) {
        // Create a bare user row; RLS expects auth context, but we can use RPC or allow insert via anon for this route
        try {
          await SupabaseService.client.from('users').insert({
            'email': email,
            'created_at': DateTime.now().toIso8601String(),
          });
        } catch (_) {}
      }

      // Create a lightweight local user session object (no Supabase Auth token)
      // Our AuthService uses local storage; set a basic FREE user
      _auth.initialize();
      // Fetch user record back and store
      final userRow = await SupabaseService.client
          .from('users')
          .select('*')
          .eq('email', email)
          .single();
      // Save into AuthService via private fields handling
      // Using signIn flow is not available here; mimic post-login state
      // Minimal approach: set _currentUser via refresh
      await _auth.refreshUser();
    } catch (e) {
      // Fail-open; wallet link will still proceed
    }
  }

  Future<void> _handleCallback() async {
    final current = Uri.base;
    final code = current.queryParameters['code'];
    final state = current.queryParameters['state'];
    setState(() => _status = 'Processing Smart Wallet login…');
    try {
      if (code == null || state == null) {
        throw Exception('Missing OAuth parameters');
      }
      final auth = await _smart.completeWebLogin(code: code, state: state);

      // Ensure app user exists and is locally signed in
      await _ensureUserSession(auth.email);

      // Attempt activation immediately
      var address = await _smart.getWalletAddressByEmail(auth.email);
      address ??= await _smart.activateSeedlessWallet(idToken: auth.idToken, email: auth.email);
      if (address == null || address.isEmpty) {
        throw Exception('Activation required - please try again');
      }
      final success = await _auth.connectCardanoWalletExternal('Smart Wallet (${auth.email})', address, '');
      if (!success) throw Exception('Could not connect Smart Wallet');
      if (!mounted) return;
      setState(() => _status = 'Smart Wallet connected. Redirecting…');
      await Future.delayed(const Duration(milliseconds: 600));
      Navigator.pushReplacementNamed(context, '/profile');
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Smart Wallet error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            const CircularProgressIndicator(color: AppColors.primaryBlue),
            const SizedBox(height: 12),
            Text(_status ?? 'Starting…', style: const TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
} 