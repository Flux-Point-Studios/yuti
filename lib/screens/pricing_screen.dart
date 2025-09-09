import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/app_colors.dart';
import '../services/auth_service.dart';
import '../config/app_config.dart';
import '../widgets/cardano_wallet_dialog.dart';
import '../widgets/glassmorphism_container.dart';
import '../services/uex_service.dart';
import 'chat_screen.dart';
import 'dart:convert'; // Added for json
import 'package:http/http.dart' as http; // Added for http

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
  late PageController _pageController;

  final AuthService _authService = AuthService();
  bool _isLoading = false;
  String? _selectedPlan;
  String _paymentMethod = 'stripe';
  int _currentPageIndex = 0;

  final List<PricingPlan> _plans = [
    PricingPlan(
      name: 'Free',
      value: 'FREE',
      price: '\$0',
      description: 'Perfect for getting started',
      features: [
        '20 messages per day',
      ],
      buttonText: 'Get Started',
      isRecommended: false,
    ),
    PricingPlan(
      name: 'Premium',
      value: 'PREMIUM',
      price: '\$99.99',
      description: 'Unlock everything',
      features: [
        'Unlimited messages',
      ],
      buttonText: 'Subscribe',
      isRecommended: true,
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

    _pageController = PageController(viewportFraction: 0.9);
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _pageController.dispose();
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
                child: Stack(
                  children: [
                    PageView.builder(
                      itemCount: _plans.length,
                      controller: _pageController,
                      onPageChanged: (index) {
                        // Use post-frame callback to avoid conflicts with AnimatedBuilder
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            setState(() {
                              _currentPageIndex = index;
                            });
                          }
                        });
                      },
                      itemBuilder: (context, index) {
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          child: _buildPricingCard(_plans[index], index),
                        );
                      },
                    ),
                    _buildNavigationArrows(),
                    _buildPageIndicators(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavigationArrows() {
    if (!mounted) return const SizedBox.shrink();
    
    return Positioned.fill(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left Arrow
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: AnimatedOpacity(
                opacity: _currentPageIndex > 0 ? 1.0 : 0.3,
                duration: const Duration(milliseconds: 200),
                child: GestureDetector(
                  onTap: _currentPageIndex > 0 ? _previousPage : null,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.9),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryBlue.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Right Arrow
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: AnimatedOpacity(
                opacity: _currentPageIndex < _plans.length - 1 ? 1.0 : 0.3,
                duration: const Duration(milliseconds: 200),
                child: GestureDetector(
                  onTap: _currentPageIndex < _plans.length - 1 ? _nextPage : null,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue.withOpacity(0.9),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primaryBlue.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _previousPage() {
    if (!mounted || _currentPageIndex <= 0) return;
    
    _pageController.animateToPage(
      _currentPageIndex - 1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _nextPage() {
    if (!mounted || _currentPageIndex >= _plans.length - 1) return;
    
    _pageController.animateToPage(
      _currentPageIndex + 1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Widget _buildPageIndicators() {
    if (!mounted) return const SizedBox.shrink();
    
    return Positioned(
      bottom: 20,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_plans.length, (index) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: _currentPageIndex == index ? 24 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: _currentPageIndex == index 
                  ? AppColors.primaryBlue 
                  : Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(4),
              boxShadow: _currentPageIndex == index 
                  ? [
                      BoxShadow(
                        color: AppColors.primaryBlue.withOpacity(0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
          );
        }),
      ),
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
                  GlassmorphismContainer(
                    glassType: plan.isRecommended ? GlassType.medium : GlassType.light,
                    padding: const EdgeInsets.all(24),
                    borderRadius: BorderRadius.circular(24),
                    blur: 15.0,
                    showGlow: plan.isRecommended,
                    customGradient: plan.isRecommended 
                        ? AppColors.blueGlowGradient.scale(0.8)
                        : null,
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
                    'AGENT Holders (≥ 100,000 \$AGENT)',
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
      child: GlassButton(
        onPressed: _isLoading ? null : () => _handleSubscribe(plan),
        isPrimary: plan.value != 'FREE',
        showGlow: plan.isRecommended,
        padding: const EdgeInsets.symmetric(vertical: 12),
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
        // Handle Cardano wallet connection for AGENT holders (≥ 100,000 AGENT)
        await _handleCardanoWalletConnection(plan);
      } else if (_paymentMethod == 'stripe') {
        // Handle Stripe payment
        await _handleStripePayment(plan);
      } else {
        // Handle traditional Stripe payment (kept for fallback/testing)
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

  Future<void> _handleUEXPayment(PricingPlan plan) async {
    try {
      final userId = _authService.currentUser?.id ?? 'anonymous';
      final orderId = '${userId}_${plan.value}_${DateTime.now().millisecondsSinceEpoch}';
      final itemName = '${plan.name} Subscription';

      // Map plan to amount in cents
      final int amountCents;
      switch (plan.value) {
        case 'PREMIUM':
          amountCents = 9999; // $99.99
          break;
        default:
          amountCents = 0;
      }

      if (amountCents <= 0) {
        throw Exception('Invalid plan amount');
      }

      // TODO: Replace with production webhook URLs or deep links
      const String successUrl = 'https://api.fluxpointstudios.com/uex/success';
      const String failureUrl = 'https://api.fluxpointstudios.com/uex/failed';

      final redirectUrl = await UEXService().generatePaymentUrl(
        orderId: orderId,
        itemName: itemName,
        amountCents: amountCents,
        successUrl: successUrl,
        failureUrl: failureUrl,
      );

      await _launchUrl(redirectUrl);

      // Inform user that activation will follow after payment confirmation
      _showSuccess('Complete payment in your browser. Subscription activates shortly after confirmation.');
    } catch (e) {
      _showError('Unable to start payment: $e');
    }
  }

  Future<void> _handleCardanoWalletConnection(PricingPlan plan) async {
    // If a wallet is already connected, skip dialog and verify directly
    final cardano = _authService.cardanoWalletService;
    bool proceed = true;
    if (!cardano.isConnected) {
      // Show dialog to connect Cardano wallet
      final walletConnected = await _showCardanoWalletDialog();
      proceed = walletConnected == true;
    }

    if (!proceed) return;

    // Check if user has premium access via Cardano wallet
    final hasPremiumAccess = await _authService.refreshCardanoPremiumAccess();

    if (hasPremiumAccess) {
      _showSuccess('Premium access verified! Welcome to ${plan.name}!');

      // Navigate to chat after successful verification
      await Future.delayed(const Duration(seconds: 1));
      _navigateToChat();
    } else {
      _showError('Your wallet does not contain the required assets for premium access.');
    }
  }

  Future<void> _handleStripePayment(PricingPlan plan) async {
    try {
      final user = _authService.currentUser;
      if (user == null) throw Exception('Not signed in');
      final resp = await http.post(
        Uri.parse('/api/stripe/checkout'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'plan': plan.value,
          'userId': user.id,
          'email': user.email,
          'successUrl': '${Uri.base.origin}/payment-success?status=success',
          'cancelUrl': '${Uri.base.origin}/pricing?status=cancel',
        }),
      );
      if (resp.statusCode != 200) {
        throw Exception('Stripe error: ${resp.body}');
      }
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final url = data['url'] as String?;
      if (url == null || url.isEmpty) {
        throw Exception('No checkout URL returned');
      }
      await _launchUrl(url);
      _showSuccess('Complete payment in the opened page. You\'ll be upgraded after confirmation.');
    } catch (e) {
      _showError('Unable to start payment: $e');
    }
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
