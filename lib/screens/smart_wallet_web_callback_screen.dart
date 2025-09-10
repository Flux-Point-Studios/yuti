import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../services/smart_wallet_service.dart';
import '../services/auth_service.dart';

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

  Future<void> _handleCallback() async {
    final uri = ModalRoute.of(context)?.settings.name;
    final current = Uri.base;
    final code = current.queryParameters['code'];
    final state = current.queryParameters['state'];
    setState(() => _status = 'Processing Smart Wallet login…');
    try {
      if (code == null || state == null) {
        throw Exception('Missing OAuth parameters');
      }
      final auth = await _smart.completeWebLogin(code: code, state: state);
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