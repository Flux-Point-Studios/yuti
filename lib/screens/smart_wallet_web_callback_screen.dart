import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../services/smart_wallet_service.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:supabase/supabase.dart' show OAuthProvider; // for OAuthProvider enum
import 'dart:convert';

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

  Future<void> _ensureUserProfile(String userId, String email) async {
    try {
      // Try RPC first (bypasses RLS)
      try {
        await SupabaseService.client.rpc('create_user_profile', params: {
          'user_id': userId,
          'user_email': email,
        });
      } catch (_) {
        // Fallback: check if exists, else insert (may be blocked by RLS in prod)
        final exists = await SupabaseService.client
            .from('users')
            .select('id')
            .eq('id', userId)
            .maybeSingle();
        if (exists == null) {
          try {
            await SupabaseService.client.from('users').insert({
              'id': userId,
              'email': email,
              'created_at': DateTime.now().toIso8601String(),
            });
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Map<String, String> _extractOAuthParams() {
    final current = Uri.base;
    final uriString = current.toString();
    String? code = current.queryParameters['code'];
    String? state = current.queryParameters['state'];
    final frag = current.fragment;
    print('🔍 SW OAuth: Uri.base=${uriString.length > 120 ? uriString.substring(0,120) + '…' : uriString}');
    print('🔍 SW OAuth: fragment len=${frag.length}');

    if ((code == null || state == null) && frag.isNotEmpty) {
      try {
        var fragStr = frag;
        // Support cases where fragment contains additional prefixes
        final idx = fragStr.indexOf('sw_oauth=');
        if (idx >= 0) {
          fragStr = fragStr.substring(idx + 'sw_oauth='.length);
        }
        final jsonStr = Uri.decodeComponent(fragStr);
        final m = json.decode(jsonStr) as Map<String, dynamic>;
        code = m['code']?.toString();
        state = m['state']?.toString();
      } catch (e) {
        print('❌ SW OAuth: fragment parse error: $e');
      }
    }
    return {
      if (code != null) 'code': code,
      if (state != null) 'state': state,
    };
  }

  Future<void> _handleCallback() async {
    final params = _extractOAuthParams();
    final code = params['code'];
    final state = params['state'];
    print('🧭 SW OAuth: callback params received state=${state != null ? state.substring(0, 8) : 'null'} codeLen=${code?.length ?? 0}');
    setState(() => _status = 'Processing Smart Wallet login…');
    try {
      if (code == null || state == null) {
        throw Exception('Missing OAuth parameters');
      }
      final auth = await _smart.completeWebLogin(code: code, state: state);
      print('🪪 SW OAuth: id_token len=${auth.idToken.length} email=${auth.email}');

      // Create real Supabase Auth session from Google id_token
      setState(() => _status = 'Creating session…');
      final res = await SupabaseService.client.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: auth.idToken,
      );
      final supaUser = res.user ?? SupabaseService.client.auth.currentUser;
      if (supaUser == null) {
        throw Exception('Failed to create Supabase session');
      }
      print('🔐 SW Session: userId=${supaUser.id} email=${auth.email}');

      // Ensure profile in users table
      await _ensureUserProfile(supaUser.id, auth.email);

      // Refresh local AuthService so _currentUser is populated
      await _auth.refreshUser();

      // Attempt activation immediately
      setState(() => _status = 'Linking Smart Wallet…');
      var address = await _smart.getWalletAddressByEmail(auth.email);
      address ??= await _smart.activateSeedlessWallet(idToken: auth.idToken, email: auth.email);
      if (address == null || address.isNotEmpty == false) {
        throw Exception('Activation required - please try again');
      }
      print('🔗 SW Wallet: address=${address.length > 16 ? address.substring(0,16) + '…' : address}');
      final success = await _auth.connectCardanoWalletExternal('Smart Wallet (${auth.email})', address, '');
      if (!success) throw Exception('Could not connect Smart Wallet');
      if (!mounted) return;
      setState(() => _status = 'Smart Wallet connected. Redirecting…');
      await Future.delayed(const Duration(milliseconds: 600));
      Navigator.pushReplacementNamed(context, '/profile');
    } catch (e) {
      if (!mounted) return;
      print('❌ SW OAuth Error: $e');
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