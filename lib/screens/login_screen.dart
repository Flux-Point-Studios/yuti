import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/app_colors.dart';
import '../services/auth_service.dart';
import '../services/wallet_auth_service.dart';
import '../widgets/glassmorphism_container.dart';
import 'chat_screen.dart';
import 'pricing_screen.dart';
import '../widgets/cardano_wallet_dialog.dart'; // Added import for CardanoWalletDialog

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  // Company contact information
  static const String _companyEmail = 'contact@fluxpointstudios.com';
  static const String _companyWebsite = 'https://fluxpointstudios.com';
  static const String _privacyPolicyUrl =
      'https://fluxpointstudios.com/privacy-policy';
  static const String _termsOfServiceUrl = 'https://fluxpointstudios.com/terms';
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final AuthService _authService = AuthService();
  final WalletAuthService _walletAuthService = WalletAuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.backgroundDark,
              AppColors.backgroundDark.withBlue(30),
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: Offset(0, _slideAnimation.value),
                      child: Opacity(
                        opacity: _fadeAnimation.value,
                        child: Column(
                          children: [
                            const SizedBox(height: 40),
                            _buildHeader(),
                            const SizedBox(height: 40),
                            _buildLoginForm(),
                            const SizedBox(height: 24),
                            _buildForgotPassword(),
                            const SizedBox(height: 32),
                            _buildWalletLoginSection(),
                            const SizedBox(height: 40),
                            _buildBackButton(),
                            const SizedBox(height: 40),
                            _buildFooterLinks(),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_isLoading) _buildLoadingOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AppColors.primaryBlue,
                AppColors.primaryBlue.withOpacity(0.6),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withOpacity(0.3),
                blurRadius: 15,
                spreadRadius: 1,
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              'assets/bluelight.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(
                  Icons.account_balance_wallet,
                  size: 40,
                  color: Colors.white,
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 24),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [
              AppColors.primaryBlue,
              Colors.purple,
              AppColors.primaryBlue,
            ],
          ).createShader(bounds),
          child: const Text(
            'Welcome Back',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Sign in to continue to Yuti',
          style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.7)),
        ),
      ],
    );
  }

  Widget _buildLoginForm() {
    return GlassmorphismContainer(
      glassType: GlassType.medium,
      padding: const EdgeInsets.all(24),
      borderRadius: BorderRadius.circular(20),
      blur: 15.0,
      showGlow: true,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildEmailField(),
                const SizedBox(height: 20),
                _buildPasswordField(),
                const SizedBox(height: 32),
                _buildLoginButton(),
              ],
            ),
          ),
    );
  }

  Widget _buildEmailField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Email',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter your email',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            prefixIcon: Icon(
              Icons.email_outlined,
              color: Colors.white.withOpacity(0.7),
            ),
            filled: true,
            fillColor: AppColors.glassBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.primaryBlue, width: 2),
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Email is required';
            }
            if (!value.contains('@')) {
              return 'Enter a valid email';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildPasswordField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Password',
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Enter your password',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            prefixIcon: Icon(
              Icons.lock_outlined,
              color: Colors.white.withOpacity(0.7),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
                color: Colors.white.withOpacity(0.7),
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
            filled: true,
            fillColor: AppColors.glassBackground,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.primaryBlue, width: 2),
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Password is required';
            }
            if (value.length < 6) {
              return 'Password must be at least 6 characters';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      height: 56,
      child: GlassButton(
        onPressed: _isLoading ? null : _handleLogin,
        isPrimary: true,
        showGlow: true,
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: _isLoading
            ? const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              )
            : const Text(
                'Sign In',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  Widget _buildForgotPassword() {
    return TextButton(
      onPressed: _handleForgotPassword,
      child: const Text(
        'Forgot Password?',
        style: TextStyle(
          color: AppColors.primaryBlue,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return TextButton.icon(
      onPressed: () => Navigator.pop(context),
      icon: const Icon(Icons.arrow_back, color: Colors.white),
      label: Text(
        'Back to Welcome',
        style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 16),
      ),
    );
  }

  Widget _buildWalletLoginSection() {
    return Column(
      children: [
        // Divider with "OR" text
        Row(
          children: [
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.transparent,
                      Colors.white.withOpacity(0.3),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'OR',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.white.withOpacity(0.3),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        
        // Smart Wallet login button
        GlassmorphismContainer(
          glassType: GlassType.light,
          padding: EdgeInsets.zero,
          borderRadius: BorderRadius.circular(16),
          blur: 10.0,
          showGlow: true,
          customGradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.purple.withOpacity(0.2),
              Colors.blue.withOpacity(0.1),
              Colors.transparent,
            ],
          ),
          child: InkWell(
            onTap: _isLoading ? null : _handleSmartWalletLogin,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_open,
                    color: Colors.white.withOpacity(0.9),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Continue with Smart Wallet',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Smart Wallet description
        Text(
          'Sign in using your Google-backed Smart Wallet',
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 12,
            fontStyle: FontStyle.italic,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.5),
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final result = await _authService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (result.isSuccess) {
        final user = result.user!;

        // Admin bypass - skip pricing page for admin email
        if (_emailController.text.trim().toLowerCase() ==
            'nathanielminton@fluxpointstudios.com') {
          _navigateToChat();
          return;
        }

        // Navigate based on user tier
        if (user.tier == 'FREE') {
          _navigateToPricing();
        } else {
          _navigateToChat();
        }
      } else {
        _showError(result.error ?? 'Login failed');
      }
    } catch (e) {
      _showError('An error occurred during login');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleWalletLogin() async {
    setState(() => _isLoading = true);

    try {
      final result = await _walletAuthService.authenticateWithWallet(WalletAuthType.login);

      if (result.success) {
        final user = result.user!;
        
        _showSuccess('Wallet connected successfully! Welcome ${user.walletAddress?.substring(0, 10)}...');
        
        // Navigate based on user tier
        await Future.delayed(const Duration(seconds: 1));
        if (user.tier == 'FREE') {
          _navigateToPricing();
        } else {
          _navigateToChat();
        }
      } else {
        _showError(result.error ?? 'Wallet authentication failed');
      }
    } catch (e) {
      _showError('Failed to connect wallet. Please try again.');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    if (_emailController.text.trim().isEmpty) {
      _showError('Please enter your email first');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _authService.resetPassword(
        email: _emailController.text.trim(),
      );

      if (result.isSuccess) {
        _showSuccess(result.message ?? 'Password reset email sent');
      } else {
        _showError(result.error ?? 'Failed to send reset email');
      }
    } catch (e) {
      _showError('An error occurred');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _navigateToChat() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const ChatScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  void _navigateToPricing() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const PricingScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          );
        },
      ),
    );
  }

  Widget _buildFooterLinks() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _launchUrl(_privacyPolicyUrl),
                child: const Text(
                  'Privacy Policy',
                  style: TextStyle(
                    color: AppColors.primaryBlue,
                    fontSize: 14,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
              Text(
                ' • ',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                ),
              ),
              GestureDetector(
                onTap: () => _launchUrl(_termsOfServiceUrl),
                child: const Text(
                  'Terms of Service',
                  style: TextStyle(
                    color: AppColors.primaryBlue,
                    fontSize: 14,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '© 2024 Flux Point Studios, Inc.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _launchUrl(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch $url');
      }
    } catch (e) {
      _showError('Could not open link: $e');
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  Future<void> _handleSmartWalletLogin() async {
    setState(() => _isLoading = true);
    try {
      // Open Smart Wallet dialog through pricing-like path (reusing dialog)
      print('🔍 DEBUG: Login -> opening Smart Wallet dialog');
      final connected = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => CardanoWalletDialog(authService: _authService),
      );

      if (connected == true) {
        _showSuccess('Smart Wallet connected!');
        await Future.delayed(const Duration(milliseconds: 600));
        _navigateToChat();
      } else {
        _showError('Smart Wallet connection cancelled');
      }
    } catch (e) {
      _showError('Smart Wallet error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
}
