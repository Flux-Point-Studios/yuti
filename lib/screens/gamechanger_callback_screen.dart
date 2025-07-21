import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../utils/app_colors.dart';
import '../services/auth_service.dart';
import '../services/gamechanger_service.dart';
import '../services/supabase_service.dart';
import '../main.dart';
import 'chat_screen.dart';
import 'pricing_screen.dart';
import 'welcome_screen.dart';

class GameChangerCallbackScreen extends StatefulWidget {
  const GameChangerCallbackScreen({Key? key}) : super(key: key);

  @override
  State<GameChangerCallbackScreen> createState() =>
      _GameChangerCallbackScreenState();
}

class _GameChangerCallbackScreenState extends State<GameChangerCallbackScreen> {
  bool _isProcessing = true;
  String _status = 'Processing wallet connection...';

  final AuthService _authService = AuthService();
  final GameChangerService _gameChangerService = GameChangerService();

  @override
  void initState() {
    super.initState();
    _handleCallback();
  }

  Future<void> _handleCallback() async {
    try {
      if (kIsWeb) {
        // Web callback handling (existing logic)
        await _handleWebCallback();
      } else {
        // iOS/Android callback handling
        await _handleNativeCallback();
      }
    } catch (e) {
      print('🔍 DEBUG: Callback screen error: $e');
      setState(() {
        _status = 'Error: ${e.toString()}';
      });
    }
  }

  Future<void> _handleWebCallback() async {
    // Get the current URL and extract the result parameter
    final currentUrl = Uri.base.toString();
    final uri = Uri.parse(currentUrl);

    print('🔍 DEBUG: Callback screen - Current URL: $currentUrl');

    final result = uri.queryParameters['result'];
    if (result != null) {
      print(
          '🔍 DEBUG: Callback screen - Found result parameter, processing wallet data...');

      setState(() {
        _status = 'Processing wallet data...';
      });

      // Parse the GameChanger result data
      final gameChangerService = GameChangerService();
      final walletData = gameChangerService.parseCallbackUrl(currentUrl);

      await _processWalletData(walletData);
    } else {
      setState(() {
        _status = 'No wallet data found in URL. Please try connecting again.';
      });
    }
  }

  Future<void> _handleNativeCallback() async {
    print('🔍 DEBUG: Native callback handling - iOS/Android');
    
    setState(() {
      _status = 'Checking for GameChanger callback data...';
    });

    // Check for pending callback data from iOS
    final callbackData = getPendingGameChangerCallback();
    
    if (callbackData != null) {
      print('🔍 DEBUG: Found pending callback data: $callbackData');
      
      setState(() {
        _status = 'Processing GameChanger wallet data...';
      });
      
      try {
        // Decode the callback data
        final decodedData = _gameChangerService.decodeCallbackResult(callbackData);
        
        if (decodedData != null) {
          print('🔍 DEBUG: Successfully decoded callback data');
          await _processWalletData(decodedData);
        } else {
          print('🔍 DEBUG: Failed to decode callback data');
          setState(() {
            _status = 'Error: Could not process wallet data from GameChanger';
            _isProcessing = false;
          });
        }
      } catch (e) {
        print('🔍 DEBUG: Error processing callback data: $e');
        setState(() {
          _status = 'Error: ${e.toString()}';
          _isProcessing = false;
        });
      }
    } else {
      print('🔍 DEBUG: No pending callback data found, waiting...');
      
      // Wait a bit more and check again in case the callback is still coming
      await Future.delayed(Duration(seconds: 3));
      
      final callbackDataRetry = getPendingGameChangerCallback();
      if (callbackDataRetry != null) {
        print('🔍 DEBUG: Found callback data on retry');
        return _handleNativeCallback(); // Retry processing
      }
      
      setState(() {
        _status = 'No GameChanger callback data received.\n\n'
            'If you were redirected here from GameChanger:\n'
            '1. Please try the wallet connection again\n'
            '2. Make sure you approved the connection in GameChanger\n'
            '3. Check that BlueLight is set as the return app\n\n'
            'Return to chat to try again.';
        _isProcessing = false;
      });
    }
  }

  Future<void> _processWalletData(GameChangerWalletData walletData) async {
    print('🔍 DEBUG: Parsed wallet data: ${walletData.toString()}');

    setState(() {
      _status = 'Setting up account...';
    });

    // Check if user is already authenticated with Supabase
    final isAuthenticated = _authService.isAuthenticated;

          if (!isAuthenticated) {
            print(
                '🔍 DEBUG: User not authenticated, signing up anonymously...');

            // Create anonymous user account or sign in guest user
            // For now, we'll create a guest account with the wallet address as email
            final guestEmail =
                '${walletData.address.substring(0, 10)}@wallet.guest';
            final guestPassword =
                'wallet_${walletData.address.substring(0, 16)}';

            try {
              // Try to sign up a guest account
              await _authService.signUp(
                email: guestEmail,
                password: guestPassword,
                firstName: 'Wallet',
                lastName: 'User',
              );
            } catch (e) {
              // If signup fails (user exists), try to sign in
              print('🔍 DEBUG: Signup failed, trying signin: $e');
              try {
                await _authService.signIn(
                  email: guestEmail,
                  password: guestPassword,
                );
              } catch (signinError) {
                print('🔍 DEBUG: Both signup and signin failed: $signinError');
                // Continue anyway - the wallet connection might still work
              }
            }
          }

          setState(() {
            _status = 'Connecting wallet to account...';
          });

          // Connect the wallet to the user's account
          final success = await _authService.connectCardanoWalletExternal(
            walletData.walletName,
            walletData.address,
            walletData.stakeAddress,
          );

          if (success) {
            setState(() {
              _status = 'Wallet connected successfully! Redirecting...';
            });

            // Small delay to show success message
            await Future.delayed(const Duration(seconds: 2));

            // Check if user has premium access
            final hasPremiumAccess = _authService.canAccessPremiumFeatures();

            print('🔍 DEBUG: Has premium access: $hasPremiumAccess');

            // Navigate based on user access level
            if (mounted) {
              if (hasPremiumAccess) {
                print('🔍 DEBUG: Navigating to chat screen');
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/chat',
                  (route) => false,
                );
              } else {
                print('🔍 DEBUG: Navigating to pricing screen');
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/pricing',
                  (route) => false,
                );
              }
            }
          } else {
            setState(() {
              _status = 'Failed to connect wallet. Please try again.';
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
