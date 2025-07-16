import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:html' as html;
import '../utils/app_colors.dart';
import 'chat_screen.dart';
import 'pricing_screen.dart';

class GameChangerCallbackScreen extends StatefulWidget {
  const GameChangerCallbackScreen({Key? key}) : super(key: key);

  @override
  State<GameChangerCallbackScreen> createState() =>
      _GameChangerCallbackScreenState();
}

class _GameChangerCallbackScreenState extends State<GameChangerCallbackScreen> {
  bool _isProcessing = true;
  String _status = 'Processing wallet connection...';

  @override
  void initState() {
    super.initState();
    _handleCallback();
  }

  Future<void> _handleCallback() async {
    try {
      if (kIsWeb) {
        // Get the current URL and extract the result parameter
        final currentUrl = html.window.location.href;
        final uri = Uri.parse(currentUrl);

        print('🔍 DEBUG: Callback screen - Current URL: $currentUrl');

        final result = uri.queryParameters['result'];
        if (result != null) {
          print('🔍 DEBUG: Callback screen - Found result parameter');

          // Close this window/tab and let flutter_web_auth handle the result
          // The flutter_web_auth package will automatically detect this callback

          setState(() {
            _status = 'Wallet connected successfully! Redirecting...';
          });

          // Small delay to show success message
          await Future.delayed(const Duration(seconds: 2));

          // Navigate back to chat or pricing depending on user state
          if (mounted) {
            Navigator.pushNamedAndRemoveUntil(
              context,
              '/chat',
              (route) => false,
            );
          }
        } else {
          setState(() {
            _status = 'No wallet data received. Please try again.';
            _isProcessing = false;
          });
        }
      } else {
        // For native apps, this screen shouldn't be reached
        setState(() {
          _status = 'This callback is for web only.';
          _isProcessing = false;
        });
      }
    } catch (e) {
      print('🔍 DEBUG: Callback screen error: $e');
      setState(() {
        _status = 'Error processing wallet connection: $e';
        _isProcessing = false;
      });
    }
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
              // GameChanger logo or icon
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
                  Icons.account_balance_wallet,
                  size: 50,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 32),

              // Status text
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

              // Loading indicator or retry button
              if (_isProcessing)
                const CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
                )
              else
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamedAndRemoveUntil(
                      context,
                      '/welcome',
                      (route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Back to Home',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
