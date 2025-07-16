import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/app_colors.dart';
import '../services/auth_service.dart';
import '../config/app_config.dart';
import '../widgets/cardano_wallet_dialog.dart';
import 'chat_screen.dart';

class PricingScreen extends StatefulWidget {
  const PricingScreen({Key? key}) : super(key: key);

  @override
  State<PricingScreen> createState() => _PricingScreenState();
}

class _PricingScreenState extends State<PricingScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;

  final AuthService _authService = AuthService();
  bool _isLoading = false;
  String? _selectedPlan;
  String _paymentMethod = 'stripe';

  final List<PricingPlan> _plans = [
    PricingPlan(
      name: 'Free',
      value: 'FREE',
      price: '\$0',
      description: 'Perfect for getting started',
      features: [
        'Limited API Calls',
        'Entry model access',
        'Basic wallet features',
      ],
      buttonText: 'Get Started',
      isRecommended: false,
    ),
    PricingPlan(
      name: 'Basic',
      value: 'BASIC',
      price: '\$39.99',
      description: 'Great for individual developers',
      features: [
        'Saved Chat History',
        'Basic model access',
        'Earn Fragments (1x)',
        'Advanced wallet features',
        'Transaction history',
      ],
      buttonText: 'Subscribe',
      isRecommended: false,
    ),
    PricingPlan(
      name: 'Premium',
      value: 'PREMIUM',
      price: '\$99.99',
      description: 'Ideal for growing teams',
      features: [
        'Advanced model access',
        'Custom User Profile',
        'Earn Fragments (1.5x)',
        'Priority support',
        'Advanced analytics',
        'Multi-wallet management',
      ],
      buttonText: 'Subscribe',
      isRecommended: true,
    ),
    PricingPlan(
      name: 'VIP',
      value: 'VIP',
      price: '\$149.99',
      description: 'For enterprise & large teams',
      features: [
        'Enterprise model access',
        'Free Weekly Learning Sessions',
        'Dedicated Account Manager',
        'Earn Fragments (2x)',
        'White-label options',
        'Custom integrations',
        '24/7 support',
      ],
      buttonText: 'Subscribe',
      isRecommended: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation = Tween<double>(begin: 50.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
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
              Column(
                children: [
                  _buildHeader(),
                  Expanded(child: _buildPricingContent()),
                  _buildFooterLinks(),
                  const SizedBox(height: 10),
                ],
              ),
              if (_isLoading) _buildLoadingOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _skipToPremium,
                        child: Text(
                          'Skip',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [
                        AppColors.primaryBlue,
                        Colors.purple,
                        AppColors.primaryBlue,
                      ],
                    ).createShader(bounds),
                    child: const Text(
                      'Choose Your Plan',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Scale your Cardano development with the right tools',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.7),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPricingContent() {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: SingleChildScrollView(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: PageView.builder(
                  itemCount: _plans.length,
                  controller: PageController(viewportFraction: 0.9),
                  itemBuilder: (context, index) {
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      child: _buildPricingCard(_plans[index], index),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPricingCard(PricingPlan plan, int index) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final delay = 0.3 + (index * 0.1);
        final cardAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Interval(delay, 1.0, curve: Curves.easeOut),
          ),
        );

        return Transform.translate(
          offset: Offset(0, (1 - cardAnimation.value) * 100),
          child: Opacity(
            opacity: cardAnimation.value,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: plan.isRecommended
                              ? AppColors.primaryBlue.withOpacity(0.15)
                              : Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: plan.isRecommended
                                ? AppColors.primaryBlue.withOpacity(0.5)
                                : Colors.white.withOpacity(0.1),
                            width: plan.isRecommended ? 2 : 1,
                          ),
                        ),
                        child: SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight:
                                  MediaQuery.of(context).size.height * 0.6,
                            ),
                            child: IntrinsicHeight(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildPlanHeader(plan),
                                  const SizedBox(height: 24),
                                  _buildPlanPrice(plan),
                                  const SizedBox(height: 24),
                                  _buildPlanFeatures(plan),
                                  const SizedBox(height: 24),
                                  if (plan.value != 'FREE')
                                    _buildPaymentMethod(plan),
                                  if (plan.value != 'FREE')
                                    const SizedBox(height: 16),
                                  _buildSubscribeButton(plan),
                                  const SizedBox(height: 16),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (plan.isRecommended) _buildRecommendedBadge(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlanHeader(PricingPlan plan) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          plan.name,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          plan.description,
          style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.7)),
        ),
      ],
    );
  }

  Widget _buildPlanPrice(PricingPlan plan) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: plan.price,
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          if (plan.value != 'FREE')
            TextSpan(
              text: '/month',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.7),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlanFeatures(PricingPlan plan) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: plan.features.map((feature) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(
                Icons.check_circle,
                size: 20,
                color:
                    plan.isRecommended ? AppColors.primaryBlue : Colors.green,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  feature,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPaymentMethod(PricingPlan plan) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment Method',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.white.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: Theme(
            data: Theme.of(context).copyWith(
              canvasColor: AppColors.backgroundMedium,
            ),
            child: DropdownButton<String>(
              value: _paymentMethod,
              dropdownColor: AppColors.backgroundMedium,
              underline: const SizedBox(),
              isExpanded: true,
              style: const TextStyle(color: Colors.white),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
              items: const [
                DropdownMenuItem(
                  value: 'stripe',
                  child: Text(
                    'Credit Card (Stripe)',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                DropdownMenuItem(
                  value: 'ada',
                  child: Text(
                    'Token & NFT Holders',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
              onChanged: (value) {
                setState(() {
                  _paymentMethod = value ?? 'stripe';
                });
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubscribeButton(PricingPlan plan) {
    final isSelected = _selectedPlan == plan.value;

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : () => _handleSubscribe(plan),
        style: ElevatedButton.styleFrom(
          backgroundColor: plan.value == 'FREE'
              ? Colors.transparent
              : (plan.isRecommended
                  ? AppColors.primaryBlue
                  : AppColors.primaryBlue.withOpacity(0.8)),
          foregroundColor: Colors.white,
          side: plan.value == 'FREE'
              ? const BorderSide(color: AppColors.primaryBlue, width: 2)
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(25),
          ),
          elevation: plan.value == 'FREE' ? 0 : 8,
        ),
        child: isSelected && _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Text(
                plan.buttonText,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: plan.value == 'FREE'
                      ? AppColors.primaryBlue
                      : Colors.white,
                ),
              ),
      ),
    );
  }

  Widget _buildRecommendedBadge() {
    return Positioned(
      top: -8,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primaryBlue, Colors.purple],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Text(
            'Most Popular',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
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

  Future<void> _handleSubscribe(PricingPlan plan) async {
    setState(() {
      _isLoading = true;
      _selectedPlan = plan.value;
    });

    try {
      if (plan.value == 'FREE') {
        // For free plan, just navigate to chat
        _navigateToChat();
      } else if (_paymentMethod == 'ada') {
        // Handle Cardano wallet connection for token/NFT holders
        await _handleCardanoWalletConnection(plan);
      } else {
        // Handle traditional Stripe payment
        await _handleStripePayment(plan);
      }
    } catch (e) {
      _showError('Subscription failed. Please try again.');
    } finally {
      setState(() {
        _isLoading = false;
        _selectedPlan = null;
      });
    }
  }

  Future<void> _handleCardanoWalletConnection(PricingPlan plan) async {
    // Show dialog to connect Cardano wallet
    final walletConnected = await _showCardanoWalletDialog();

    if (walletConnected == true) {
      // Check if user has premium access via Cardano wallet
      final hasPremiumAccess = await _authService.refreshCardanoPremiumAccess();

      if (hasPremiumAccess) {
        _showSuccess('Premium access verified! Welcome to ${plan.name}!');

        // Navigate to chat after successful verification
        await Future.delayed(const Duration(seconds: 1));
        _navigateToChat();
      } else {
        _showError(
            'Your wallet does not contain the required assets for premium access.');
      }
    }
  }

  Future<void> _handleStripePayment(PricingPlan plan) async {
    // Simulate Stripe payment process
    await Future.delayed(const Duration(seconds: 2));

    // Update user tier
    await _authService.updateUserTier(plan.value);

    _showSuccess('Successfully subscribed to ${plan.name} plan!');

    // Navigate to chat after successful subscription
    await Future.delayed(const Duration(seconds: 1));
    _navigateToChat();
  }

  Future<bool?> _showCardanoWalletDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CardanoWalletDialog(authService: _authService),
    );
  }

  void _skipToPremium() async {
    setState(() => _isLoading = true);

    // Continue with free tier
    await Future.delayed(const Duration(milliseconds: 500));
    _navigateToChat();
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

  Widget _buildFooterLinks() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => _launchUrl(AppConfig().privacyPolicyUrl),
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
                onTap: () => _launchUrl(AppConfig().termsOfServiceUrl),
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
            '© 2024 ${AppConfig().companyName}',
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }
}

class PricingPlan {
  final String name;
  final String value;
  final String price;
  final String description;
  final List<String> features;
  final String buttonText;
  final bool isRecommended;

  PricingPlan({
    required this.name,
    required this.value,
    required this.price,
    required this.description,
    required this.features,
    required this.buttonText,
    required this.isRecommended,
  });
}
