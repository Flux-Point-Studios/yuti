import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../models/user.dart';
import '../widgets/cardano_wallet_dialog.dart';
import '../widgets/wallet_security_settings.dart';
import '../services/gamification_service.dart';
import '../services/wallet_service.dart';
import '../services/cardano_wallet_service.dart';
import '../screens/pricing_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final AuthService _authService = AuthService();
  final GamificationService _gami = GamificationService();
  User? _currentUser;
  bool _isLoading = true;
  bool _isWalletLoading = false;
  GamificationState? _gamiState;
  
  // Usage statistics
  int _chatCount = 0;
  int _fragmentCount = 0;
  int _referralCount = 0;
  bool _isStatsLoading = false;
  
  // Affiliate program
  String? _referralLink;
  bool _isAffiliateLoading = false;
  
  // Activity chart data
  List<FlSpot> _chatSpots = [];
  List<FlSpot> _fragmentSpots = [];
  List<FlSpot> _referralSpots = [];
  bool _isChartLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadGamification();
    // Ensure local and Cardano wallet services are initialized and refresh UI
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final walletService = context.read<WalletService>();
        await walletService.initialize();
        await CardanoWalletService().initialize();
        if (mounted) setState(() {});
      } catch (_) {}
    });
  }

  Future<void> _loadGamification() async {
    final s = await _gami.getState();
    setState(() {
      _gamiState = s;
    });
  }

  Future<void> _loadUserData() async {
    setState(() {
      _currentUser = _authService.currentUser;
      _isLoading = false;
    });
    
    // Load additional profile data
    await Future.wait([
      _loadUserStats(),
      _loadReferralLink(),
      _loadActivityChartData(),
      _loadGamification(),
    ]);
  }

  Future<void> _loadUserStats() async {
    if (_currentUser?.id == null) return;
    
    setState(() => _isStatsLoading = true);
    
    try {
      // Try to fetch from user_analysis table first
      final statsResponse = await SupabaseService.client
          .from('user_analysis')
          .select('chat_count, fragments, referral_count')
          .eq('id', _currentUser!.id)
          .maybeSingle();
      
      if (statsResponse != null) {
        setState(() {
          _chatCount = statsResponse['chat_count'] ?? 0;
          _fragmentCount = statsResponse['fragments'] ?? 0;
          _referralCount = statsResponse['referral_count'] ?? 0;
        });
      } else {
        // Fallback: calculate stats from individual tables
        await _calculateStatsFromTables();
      }
    } catch (e) {
      print('Error loading user stats: $e');
      // Fallback: calculate stats from individual tables
      await _calculateStatsFromTables();
    } finally {
      setState(() => _isStatsLoading = false);
    }
  }

  Future<void> _calculateStatsFromTables() async {
    try {
      // Count chats for user
      final chatResponse = await SupabaseService.client
          .from('chats')
          .select('id')
          .eq('user_id', _currentUser!.id);
      
      // Count messages for user (alternative chat metric)
      final messageResponse = await SupabaseService.client
          .from('messages')
          .select('id')
          .eq('user_id', _currentUser!.id);
      
      // For fragments, we'll use message count as a proxy for now
      // In the future, this could be a separate metric
      
      // Count referrals (if referrals table exists)
      int referralCount = 0;
      try {
        final referralResponse = await SupabaseService.client
            .from('referral_uses')
            .select('id')
            .eq('referrer_id', _currentUser!.id);
        referralCount = referralResponse.length;
      } catch (e) {
        // Referral table might not exist yet
        print('Referral count not available: $e');
      }
      
      setState(() {
        _chatCount = chatResponse.length;
        _fragmentCount = messageResponse.length; // Using messages as proxy for fragments
        _referralCount = referralCount;
      });
    } catch (e) {
      print('Error calculating stats from tables: $e');
    }
  }

  Future<void> _loadReferralLink() async {
    if (_currentUser?.id == null) return;
    
    try {
      final referralResponse = await SupabaseService.client
          .from('referrals')
          .select('referral_link')
          .eq('user_id', _currentUser!.id)
          .maybeSingle();
      
      if (referralResponse != null) {
        setState(() {
          _referralLink = referralResponse['referral_link'];
        });
      }
    } catch (e) {
      print('Error loading referral link: $e');
      // Referrals table might not exist yet - this is fine
    }
  }

  Future<void> _createReferralLink() async {
    if (_currentUser?.id == null) return;
    
    setState(() => _isAffiliateLoading = true);
    
    try {
      // Generate unique referral code
      final referralCode = const Uuid().v4().substring(0, 8).toUpperCase();
      
      // Create referral link (adjust domain as needed)
      final referralLink = 'https://bluelight.ai/signup?ref=$referralCode';
      
      // Insert into referrals table
      await SupabaseService.client.from('referrals').insert({
        'user_id': _currentUser!.id,
        'referral_code': referralCode,
        'referral_link': referralLink,
        'created_at': DateTime.now().toIso8601String(),
      });
      
      setState(() {
        _referralLink = referralLink;
      });
      
      _showSuccess('Affiliate link created successfully!');
      
      // Refresh stats to update referral count
      await _loadUserStats();
      
    } catch (e) {
      print('Error creating referral link: $e');
      _showError('Failed to create affiliate link. Please try again.');
    } finally {
      setState(() => _isAffiliateLoading = false);
    }
  }

  Future<void> _loadActivityChartData() async {
    if (_currentUser?.id == null) return;
    
    setState(() => _isChartLoading = true);
    
    try {
      // Try to fetch from analysis_month table
      final monthlyResponse = await SupabaseService.client
          .from('analysis_month')
          .select('month, chat_count, fragments, referral_count')
          .eq('user_id', _currentUser!.id)
          .order('month', ascending: true);
      
      if (monthlyResponse.isNotEmpty) {
        _buildChartDataFromMonthly(monthlyResponse);
      } else {
        // Fallback: create sample data based on current stats
        _buildSampleChartData();
      }
    } catch (e) {
      print('Error loading activity chart data: $e');
      // Fallback: create sample data
      _buildSampleChartData();
    } finally {
      setState(() => _isChartLoading = false);
    }
  }

  void _buildChartDataFromMonthly(List<dynamic> monthlyData) {
    _chatSpots.clear();
    _fragmentSpots.clear();
    _referralSpots.clear();
    
    for (int i = 0; i < monthlyData.length; i++) {
      final data = monthlyData[i];
      final x = i.toDouble();
      
      _chatSpots.add(FlSpot(x, (data['chat_count'] ?? 0).toDouble()));
      _fragmentSpots.add(FlSpot(x, (data['fragments'] ?? 0).toDouble()));
      _referralSpots.add(FlSpot(x, (data['referral_count'] ?? 0).toDouble()));
    }
  }

  void _buildSampleChartData() {
    // Create sample data for the last 6 months based on current stats
    _chatSpots.clear();
    _fragmentSpots.clear();
    _referralSpots.clear();
    
    final random = DateTime.now().millisecond;
    for (int i = 0; i < 6; i++) {
      final x = i.toDouble();
      // Create realistic progression
      final chatBase = (_chatCount / 6) * (i + 1);
      final fragmentBase = (_fragmentCount / 6) * (i + 1);
      final referralBase = (_referralCount / 6) * (i + 1);
      
      _chatSpots.add(FlSpot(x, chatBase.toDouble()));
      _fragmentSpots.add(FlSpot(x, fragmentBase.toDouble()));
      _referralSpots.add(FlSpot(x, referralBase.toDouble()));
    }
  }

  Widget _buildActivityChartSection() {
    return _buildSection(
      title: 'Activity Overview',
      children: [
        if (_isChartLoading)
          const Padding(
            padding: EdgeInsets.all(32.0),
            child: Center(child: CircularProgressIndicator(color: AppColors.primaryBlue)),
          )
        else
          Container(
            height: 250,
            padding: const EdgeInsets.all(16),
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: AppColors.textSecondary.withOpacity(0.1),
                      strokeWidth: 1,
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 30,
                      interval: 1,
                      getTitlesWidget: (double value, TitleMeta meta) {
                        const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun'];
                        if (value.toInt() < months.length) {
                          return Text(
                            months[value.toInt()],
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          );
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      getTitlesWidget: (double value, TitleMeta meta) {
                        return Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(
                    color: AppColors.textSecondary.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                minX: 0,
                maxX: 5,
                minY: 0,
                lineBarsData: [
                  // Chats line
                  LineChartBarData(
                    spots: _chatSpots,
                    isCurved: true,
                    color: AppColors.primaryBlue,
                    barWidth: 3,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.primaryBlue.withOpacity(0.1),
                    ),
                  ),
                  // Fragments line
                  LineChartBarData(
                    spots: _fragmentSpots,
                    isCurved: true,
                    color: AppColors.success,
                    barWidth: 3,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.success.withOpacity(0.1),
                    ),
                  ),
                  // Referrals line
                  LineChartBarData(
                    spots: _referralSpots,
                    isCurved: true,
                    color: AppColors.warning,
                    barWidth: 3,
                    dotData: FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: AppColors.warning.withOpacity(0.1),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        // Chart legend
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildLegendItem('Chats', AppColors.primaryBlue),
            _buildLegendItem('Fragments', AppColors.success),
            _buildLegendItem('Referrals', AppColors.warning),
          ],
        ),
      ],
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Future<void> _linkWallet() async {
    setState(() => _isWalletLoading = true);

    try {
      // Use the same dialog approach as pricing page to preserve context
      final walletConnected = await _showCardanoWalletDialog();

      if (walletConnected == true) {
        _showSuccess('Wallet linked successfully!');
        await _loadUserData(); // Refresh user data
      }
    } catch (e) {
      _showError('Failed to link wallet. Please try again.');
    } finally {
      setState(() => _isWalletLoading = false);
    }
  }

  Future<void> _unlinkWallet() async {
    final confirmed = await _showConfirmDialog(
      'Unlink Wallet',
      'Are you sure you want to unlink your wallet? This will remove premium access if you have it through your wallet.',
    );

    if (confirmed == true) {
      setState(() => _isWalletLoading = true);

      try {
        await _authService.disconnectCardanoWallet();
        _showSuccess('Wallet unlinked successfully');
        await _loadUserData(); // Refresh user data
      } catch (e) {
        _showError('Failed to unlink wallet. Please try again.');
      } finally {
        setState(() => _isWalletLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
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
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _isLoading 
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primaryBlue))
                  : _buildProfileContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 8),
          const Text(
            'Profile',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileContent() {
    if (_currentUser == null) {
      return const Center(
        child: Text(
          'No user data available',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile header
          Center(
            child: Column(
              children: [
                Container(
                  width: 100,
                  height: 100,
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
                          Icons.person,
                          size: 50,
                          color: Colors.white,
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _currentUser!.email,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getTierColor(_currentUser!.tier).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _getTierColor(_currentUser!.tier),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        '${_currentUser!.tier} USER',
                        style: TextStyle(
                          color: _getTierColor(_currentUser!.tier),
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (_currentUser!.tier.toUpperCase() == 'FREE') ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const PricingScreen()),
                          );
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.primaryBlue,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Manage Plan',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          _buildGamificationSection(),

          const SizedBox(height: 40),

          // Usage Statistics section (hidden for now)
          // _buildUsageStatsSection(),

          // const SizedBox(height: 32),

          // Affiliate Program section (hidden for now)
          // _buildAffiliateSection(),

          // const SizedBox(height: 32),

          // Activity Chart section (hidden for now)
          // _buildActivityChartSection(),

          // const SizedBox(height: 32),

          // Security Settings section
          _buildSecuritySection(),

          const SizedBox(height: 32),

          // Account details section
          _buildSection(
            title: 'Account Details',
            children: [
              _buildDetailRow('Email', _currentUser!.email),
              _buildDetailRow('Account Type', _currentUser!.tier),
              _buildDetailRow('Member Since', _formatDate(_currentUser!.createdAt)),
              if (_currentUser!.subscriptionStatus != null)
                _buildDetailRow('Subscription Status', _currentUser!.subscriptionStatus!),
              if (_currentUser!.tier != 'FREE' && _currentUser!.endedAt != null)
                _buildDetailRow(
                  'Subscription Expiry', 
                  _currentUser!.hasExpired 
                    ? 'Expired' 
                    : '${_currentUser!.daysLeft} days left'
                ),
            ],
          ),

          const SizedBox(height: 32),

          // Wallet section
          _buildWalletSection(),

          const SizedBox(height: 32),

          // Settings section
          _buildSection(
            title: 'Settings',
            children: [
              _buildDetailRow('App Version', '1.0.0'),
            ],
          ),

          const SizedBox(height: 32),

          // Actions section
          _buildSection(
            title: 'Actions',
            children: [
              _buildActionButton(
                icon: Icons.logout,
                title: 'Sign Out',
                color: Colors.red,
                onTap: _signOut,
              ),
            ],
          ),

          const SizedBox(height: 40),

          // App info
          Center(
            child: Column(
              children: [
                Text(
                  'Yuti',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version 1.0.0',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.3),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGamificationSection() {
    final s = _gamiState;
    if (s == null) {
      return const SizedBox.shrink();
    }

    final progress = s.xpForNextLevel == 0 ? 0.0 : (s.xpIntoLevel / s.xpForNextLevel).clamp(0.0, 1.0);

    return _buildSection(
      title: 'Progress',
      children: [
        Row(
          children: [
            _buildBadgeRow(s.level),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Level ${s.level}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      backgroundColor: Colors.white.withOpacity(0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${s.xpIntoLevel} / ${s.xpForNextLevel} XP', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text('Daily Quests', style: TextStyle(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _buildTaskTile('task_add_wallet', s.completedTasks.contains('task_add_wallet')),
        _buildTaskTile('task_first_swap', s.completedTasks.contains('task_first_swap')),
        _buildTaskTile('task_first_send', s.completedTasks.contains('task_first_send')),
      ],
    );
  }

  Widget _buildTaskTile(String taskId, bool done) {
    final label = GamificationService.taskIdToLabel[taskId] ?? taskId;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, color: done ? Colors.greenAccent : Colors.white70),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      subtitle: const Text('+10 XP', style: TextStyle(color: Colors.white70, fontSize: 12)),
      trailing: done ? const Text('Completed', style: TextStyle(color: Colors.greenAccent)) : const SizedBox.shrink(),
      dense: true,
      visualDensity: const VisualDensity(vertical: -1),
    );
  }

  Widget _buildBadgeRow(int level) {
    // Show up to 5 badges
    final icons = <IconData>[Icons.star_border, Icons.star_half, Icons.star, Icons.emoji_events, Icons.military_tech];
    final widgets = <Widget>[];
    for (int i = 1; i <= 5; i++) {
      final active = level >= i;
      widgets.add(Icon(
        icons[i - 1],
        color: active ? AppColors.primaryBlue : Colors.white24,
      ));
      if (i < 5) widgets.add(const SizedBox(width: 4));
    }
    return Row(children: widgets);
  }

  Widget _buildUsageStatsSection() {
    return _buildSection(
      title: 'Usage Statistics',
      children: [
        if (_isStatsLoading)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator(color: AppColors.primaryBlue)),
          )
        else ...[
          _buildStatRow(
            icon: Icons.chat_bubble_outline,
            label: 'Total Chats',
            value: _chatCount.toString(),
          ),
          _buildStatRow(
            icon: Icons.auto_awesome,
            label: 'Fragments',
            value: _fragmentCount.toString(),
          ),
          _buildStatRow(
            icon: Icons.people_outline,
            label: 'Referrals',
            value: _referralCount.toString(),
          ),
        ],
      ],
    );
  }

  Widget _buildStatRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: AppColors.primaryBlue,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAffiliateSection() {
    return _buildSection(
      title: 'Referral Program',
      children: [
        if (_isAffiliateLoading)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Center(child: CircularProgressIndicator(color: AppColors.primaryBlue)),
          )
        else if (_referralLink == null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Earn rewards by referring friends to Yuti!',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _createReferralLink,
                    icon: const Icon(Icons.card_giftcard, color: Colors.white),
                    label: const Text(
                      'Become an Affiliate',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          _buildDetailRow('Your Referral Link', _referralLink!),
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copyToClipboard(_referralLink!),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy Link'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryBlue,
                      side: BorderSide(color: AppColors.primaryBlue),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _showSuccess('Referral link copied to clipboard!');
  }

  Widget _buildSecuritySection() {
    return _buildSection(
      title: 'Security & Privacy',
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Security Overview
              Row(
                children: [
                  Icon(Icons.security, color: AppColors.primaryBlue, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Wallet Security',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Manage biometric authentication and backup verification',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: AppColors.textSecondary,
                    size: 16,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              // Security features quick preview
              Row(
                children: [
                  Icon(Icons.fingerprint, color: AppColors.success, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Biometric Protection',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.backup, color: AppColors.success, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Backup Verification',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        
        // Security Settings Button
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ElevatedButton.icon(
            onPressed: _openSecuritySettings,
            icon: Icon(Icons.security, size: 18),
            label: Text('Open Security Settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _openSecuritySettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const WalletSecuritySettings(),
      ),
    );
  }

  Future<void> _deleteLocalWallet() async {
    final confirmed = await _showConfirmDialog(
      'Delete Local Wallet',
      'This will remove your locally created/restored wallet from this device. You can create/restore/connect a new one later.',
    );

    if (confirmed == true) {
      setState(() => _isWalletLoading = true);
      try {
        final walletService = context.read<WalletService>();
        await walletService.deleteWallet();
        _showSuccess('Local wallet deleted');
        await _loadUserData();
      } catch (e) {
        _showError('Failed to delete local wallet. Please try again.');
      } finally {
        setState(() => _isWalletLoading = false);
      }
    }
  }

  Widget _buildWalletSection() {
    // Consider any wallet presence (local or external link) as “has wallet”
    final walletService = context.read<WalletService>();
    final cardano = CardanoWalletService();
    final hasLocalWallet = walletService.hasWallet;
    final hasExternalWallet = cardano.isConnected || ((_currentUser?.walletAddress != null && _currentUser!.walletAddress!.isNotEmpty));
    final hasWallet = hasLocalWallet || hasExternalWallet;

    return _buildSection(
      title: 'Cardano Wallet',
      children: [
        if (hasWallet) ...[
          // Wallet connected info
          if (_currentUser?.walletAddress != null && _currentUser!.walletAddress!.isNotEmpty)
            _buildDetailRow('Wallet Address', '${_currentUser!.walletAddress!.substring(0, 10)}...${_currentUser!.walletAddress!.substring(_currentUser!.walletAddress!.length - 6)}'),
          if (_currentUser?.stakeAddress != null && _currentUser!.stakeAddress!.isNotEmpty)
            _buildDetailRow('Stake Address', '${_currentUser!.stakeAddress!.substring(0, 10)}...${_currentUser!.stakeAddress!.substring(_currentUser!.stakeAddress!.length - 6)}'),
          if (_currentUser?.walletAddress == null || _currentUser!.walletAddress!.isEmpty)
            _buildDetailRow('Local Wallet', walletService.walletName ?? 'Active'),
          
          // Wallet actions
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Wallet Connected',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_currentUser?.walletAddress != null && _currentUser!.walletAddress!.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isWalletLoading ? null : _unlinkWallet,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.withOpacity(0.2),
                        foregroundColor: Colors.red,
                        side: BorderSide(color: Colors.red, width: 1),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: _isWalletLoading 
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                            ),
                          )
                        : const Text('Unlink Wallet'),
                    ),
                  ),
                if ((_currentUser?.walletAddress == null || _currentUser!.walletAddress!.isEmpty) && hasLocalWallet) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isWalletLoading ? null : _deleteLocalWallet,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.withOpacity(0.2),
                        foregroundColor: Colors.red,
                        side: BorderSide(color: Colors.red, width: 1),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: _isWalletLoading 
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                            ),
                          )
                        : const Text('Delete Local Wallet'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ] else ...[
          // No wallet connected
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(
                  Icons.account_balance_wallet_outlined,
                  color: Colors.white.withOpacity(0.5),
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(
                  'No Wallet Connected',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Connect your wallet to unlock premium features and verify ownership of premium assets.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isWalletLoading ? null : _linkWallet,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: _isWalletLoading 
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.account_balance_wallet, size: 18),
                            const SizedBox(width: 8),
                            Text('Connect Wallet'),
                          ],
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSection({required String title, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withOpacity(0.1),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Colors.white.withOpacity(0.1),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: AppColors.primaryBlue,
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: Colors.white.withOpacity(0.4),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              icon,
              color: color,
              size: 24,
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getTierColor(String tier) {
    switch (tier.toUpperCase()) {
      case 'PREMIUM':
        return Colors.amber;
      case 'FREE':
        return Colors.grey;
      default:
        return Colors.white;
    }
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Coming soon!'),
        backgroundColor: AppColors.primaryBlue,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool?> _showConfirmDialog(String title, String content) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.backgroundDark,
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          content,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Confirm',
              style: TextStyle(color: AppColors.primaryBlue),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.backgroundDark,
        title: const Text(
          'Sign Out',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.white.withOpacity(0.7)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Sign Out',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _authService.signOut();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/welcome');
      }
    }
  }

  Future<bool?> _showCardanoWalletDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CardanoWalletDialog(authService: _authService),
    );
  }
} 