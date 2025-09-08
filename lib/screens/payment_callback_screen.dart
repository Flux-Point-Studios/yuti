import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/app_colors.dart';
import '../services/auth_service.dart';
import '../main.dart';
import 'chat_screen.dart';
import 'pricing_screen.dart';

class PaymentCallbackScreen extends StatefulWidget {
  const PaymentCallbackScreen({Key? key}) : super(key: key);

  @override
  State<PaymentCallbackScreen> createState() => _PaymentCallbackScreenState();
}

class _PaymentCallbackScreenState extends State<PaymentCallbackScreen> {
  bool _isProcessing = true;
  String _status = 'Processing payment...';
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _handleCallback();
  }

  Future<void> _handleCallback() async {
    try {
      if (kIsWeb) {
        await _handleWebCallback();
      } else {
        await _handleNativeCallback();
      }
    } catch (e) {
      setState(() {
        _status = 'Error: ${e.toString()}';
        _isProcessing = false;
      });
    }
  }

  Future<void> _handleWebCallback() async {
    final currentUrl = Uri.base.toString();
    final uri = Uri.parse(currentUrl);

    // Accept generic params like ?status=success&order=... or payload in result
    final status = (uri.queryParameters['status'] ?? uri.queryParameters['result'] ?? '').toLowerCase();

    setState(() {
      _status = 'Verifying payment...';
    });

    // Always refresh user; server/webhook may have updated subscription
    await _authService.refreshUser();

    final hasPremiumAccess = _authService.canAccessPremiumFeatures();
    if (hasPremiumAccess || status == 'success' || status == 'paid') {
      setState(() {
        _status = 'Payment successful! Unlocking premium...';
      });
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/chat', (route) => false);
      }
    } else {
      setState(() {
        _status = 'Payment not confirmed yet. You can continue and check later.';
        _isProcessing = false;
      });
    }
  }

  Future<void> _handleNativeCallback() async {
    setState(() {
      _status = 'Awaiting payment confirmation...';
    });

    // If native deep link provided payload via MethodChannel
    final payload = getPendingPaymentCallback();
    if (payload != null) {
      // We ignore payload content and rely on DB refresh for truth
      await _authService.refreshUser();
      final hasPremiumAccess = _authService.canAccessPremiumFeatures();
      if (hasPremiumAccess) {
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, '/chat', (route) => false);
          return;
        }
      }
    }

    // Fallback: brief delay, then refresh again
    await Future.delayed(const Duration(seconds: 2));
    await _authService.refreshUser();
    final hasPremiumAccess = _authService.canAccessPremiumFeatures();
    if (hasPremiumAccess) {
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/chat', (route) => false);
        return;
      }
    }

    setState(() {
      _status = 'Waiting for payment confirmation. You can check back on the Pricing page.';
      _isProcessing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.blueGlowGradient,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: AppColors.curvedBlueGradient,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.glowColor,
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.credit_score,
                  size: 50,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                _status,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (!_isProcessing)
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/pricing',
                      (route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Back to Pricing',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
} 