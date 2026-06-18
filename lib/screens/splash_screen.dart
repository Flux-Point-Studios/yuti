import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../services/wallet_service.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../utils/app_colors.dart';
import '../services/cardano_wallet_service.dart';
import '../cip186/app_wiring.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  late VideoPlayerController _videoController;
  bool _isVideoInitialized = false;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
    _initializeApp();
  }

  Future<void> _initializeVideo() async {
    try {
      _videoController =
          VideoPlayerController.asset('assets/loading_loop_fast.mp4');
      await _videoController.initialize();

      // Ensure autoplay on web by muting
      // (Browsers block autoplay with sound)
      try { _videoController.setVolume(0); } catch (_) {}

      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });

        // Set video to loop and play
        _videoController.setLooping(true);
        _videoController.play();
      }
    } catch (e) {
      print('Error initializing video: $e');
      // If video fails to load, show fallback after delay
      await Future.delayed(const Duration(seconds: 3));
      if (mounted && !_hasNavigated) {
        _navigateToNextScreen();
      }
    }
  }

    Future<void> _initializeApp() async {
    // Give video time to start playing
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      // Initialize authentication service
      final authService = AuthService();
      await authService.initialize();
      
      // Initialize wallet services
      final walletService = context.read<WalletService>();
      await walletService.initialize();
      // Restore Cardano wallet connection if previously connected
      final cardano = CardanoWalletService();
      await cardano.initialize();

      // Let video play for at least 2 seconds
      await Future.delayed(const Duration(seconds: 2));

      if (mounted && !_hasNavigated) {
        _navigateToNextScreen();
      }
    } catch (e) {
      print('Error initializing app: $e');
      // Wait a bit longer then navigate on error
      await Future.delayed(const Duration(seconds: 3));
      if (mounted && !_hasNavigated) {
        _navigateToNextScreen();
      }
    }
  }

  void _navigateToNextScreen() {
    if (_hasNavigated) return;
    _hasNavigated = true;

    try {
      // Supabase disabled: route purely on local wallet presence — no account,
      // no login/signup gate. No wallet -> set up (create/restore); wallet
      // present -> straight into the app.
      if (SupabaseService.disabled) {
        final walletService = context.read<WalletService>();
        final hasWallet =
            walletService.hasWallet && walletService.isWalletLoaded;
        final hasCardanoWallet = CardanoWalletService().isConnected;
        Navigator.pushReplacementNamed(
          context,
          (hasWallet || hasCardanoWallet) ? '/chat' : '/onboarding',
        );
        return;
      }

      // Check authentication status first
      final authService = AuthService();
      final isAuthenticated = authService.isAuthenticated;

      if (isAuthenticated) {
        // User is logged in, go to chat
        Navigator.pushReplacementNamed(context, '/chat');
      } else {
        // User not logged in, check if they have a wallet set up
        final walletService = context.read<WalletService>();
        final cardano = CardanoWalletService();
        final hasWallet = walletService.hasWallet;
        final hasWalletLoaded = walletService.isWalletLoaded;
        final hasCardanoWallet = cardano.isConnected;

        if ((hasWallet && hasWalletLoaded) || hasCardanoWallet) {
          // Has wallet but not authenticated, go to chat
          Navigator.pushReplacementNamed(context, '/chat');
        } else {
          // No wallet or not loaded, go to welcome screen for login/signup
          Navigator.pushReplacementNamed(context, '/welcome');
        }
      }
    } catch (e) {
      print('Error in navigation logic: $e');
      // On error, go to welcome screen
      Navigator.pushReplacementNamed(context, '/welcome');
    } finally {
      // Past splash: let any queued CIP-186 deep-link present its consent sheet.
      markCip186UiReady();
    }
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Stack(
        children: [
          // Video background
          if (_isVideoInitialized)
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _videoController.value.size.width,
                  height: _videoController.value.size.height,
                  child: VideoPlayer(_videoController),
                ),
              ),
            )
          else
            // Fallback background while video loads
            Container(
              decoration: const BoxDecoration(
                gradient: AppColors.blueGlowGradient,
              ),
            ),

          // Remove fallback overlay; rely solely on the animated video splash
          // Keeping a minimal gradient background while video initializes

        ],
      ),
    );
  }
}
