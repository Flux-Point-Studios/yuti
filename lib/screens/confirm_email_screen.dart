import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../services/auth_service.dart';
import 'email_login_screen.dart';

class ConfirmEmailScreen extends StatefulWidget {
  final String email;
  const ConfirmEmailScreen({Key? key, required this.email}) : super(key: key);

  @override
  State<ConfirmEmailScreen> createState() => _ConfirmEmailScreenState();
}

class _ConfirmEmailScreenState extends State<ConfirmEmailScreen> {
  final AuthService _auth = AuthService();
  bool _sending = false;
  String? _message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text('Confirm your email', style: TextStyle(color: AppColors.textPrimary)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'We\'ve sent a confirmation link to:',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Text(
              widget.email,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              'Open your email and click the link to activate your account. If you can\'t find it, check Spam/Promotions or resend below.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_message!, style: const TextStyle(color: AppColors.primaryBlue)),
              ),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _sending ? null : _resend,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue, foregroundColor: Colors.white),
                  child: _sending
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                      : const Text('Resend'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _openMail,
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.textPrimary, side: BorderSide(color: Colors.white.withOpacity(0.3))),
                  child: const Text('Open mail app'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _checkStatus,
                  child: const Text('I confirmed already', style: TextStyle(color: AppColors.primaryBlue)),
                ),
              ],
            ),
            const Spacer(),
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const EmailLoginScreen()),
                  );
                },
                child: const Text('Back to login', style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _resend() async {
    setState(() { _sending = true; _message = null; });
    try {
      await _auth.resendSignUpConfirmation(widget.email);
      setState(() { _message = 'Confirmation email re-sent to ${widget.email}'; });
    } catch (e) {
      setState(() { _message = 'Could not resend: $e'; });
    } finally {
      setState(() { _sending = false; });
    }
  }

  Future<void> _openMail() async {
    // We simply show a hint; opening native mail apps isn\'t guaranteed on web.
    setState(() { _message = 'Tip: Switch to your mail app and look for our message. It may be in Spam/Promotions.'; });
  }

  Future<void> _checkStatus() async {
    try {
      await _auth.refreshUser();
      if (mounted) {
        // If user confirmed in another tab and returned, sign them in from login screen
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const EmailLoginScreen()));
      }
    } catch (e) {
      setState(() { _message = 'Still not confirmed. Try resending.'; });
    }
  }
} 