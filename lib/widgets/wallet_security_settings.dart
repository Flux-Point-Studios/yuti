import 'package:flutter/material.dart';
import '../services/cardano_wallet_service.dart';
import '../services/biometric_auth_service.dart';
import '../services/backup_verification_service.dart';
import '../widgets/glassmorphism_container.dart';
import '../utils/app_colors.dart';

class WalletSecuritySettings extends StatefulWidget {
  const WalletSecuritySettings({Key? key}) : super(key: key);

  @override
  State<WalletSecuritySettings> createState() => _WalletSecuritySettingsState();
}

class _WalletSecuritySettingsState extends State<WalletSecuritySettings> {
  final CardanoWalletService _walletService = CardanoWalletService();
  final BiometricAuthService _biometricService = BiometricAuthService();
  
  bool _isLoading = true;
  WalletSecurityStatus? _securityStatus;
  String _biometricType = 'Biometric Authentication';

  @override
  void initState() {
    super.initState();
    _loadSecurityStatus();
  }

  Future<void> _loadSecurityStatus() async {
    try {
      setState(() => _isLoading = true);
      
      final status = await _walletService.getSecurityStatus();
      final biometricType = await _walletService.getBiometricType();
      
      setState(() {
        _securityStatus = status;
        _biometricType = biometricType;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading security status: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        title: const Text('Wallet Security'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildSecurityContent(),
    );
  }

  Widget _buildSecurityContent() {
    if (_securityStatus == null) {
      return const Center(
        child: Text(
          'Unable to load security settings',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSecurityScore(),
          const SizedBox(height: 24),
          _buildBiometricSection(),
          const SizedBox(height: 24),
          _buildBackupSection(),
          const SizedBox(height: 24),
          _buildRecommendations(),
        ],
      ),
    );
  }

  Widget _buildSecurityScore() {
    final score = _securityStatus!.securityScore;
    final level = _securityStatus!.securityLevel;
    
    Color scoreColor;
    if (score >= 0.9) {
      scoreColor = Colors.green;
    } else if (score >= 0.7) {
      scoreColor = Colors.blue;
    } else if (score >= 0.5) {
      scoreColor = Colors.orange;
    } else {
      scoreColor = Colors.red;
    }

    return GlassmorphismContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.security, color: scoreColor, size: 24),
              const SizedBox(width: 12),
              const Text(
                'Security Overview',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Security Score Circle
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(
                    value: score,
                    strokeWidth: 8,
                    backgroundColor: AppColors.glassBackground,
                    valueColor: AlwaysStoppedAnimation(scoreColor),
                  ),
                ),
                Column(
                  children: [
                    Text(
                      '${(score * 100).toInt()}%',
                      style: TextStyle(
                        color: scoreColor,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      level,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricSection() {
    return GlassmorphismContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.fingerprint,
                color: _securityStatus!.biometricEnabled 
                    ? Colors.green 
                    : AppColors.textSecondary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _biometricType,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Switch(
                value: _securityStatus!.biometricEnabled,
                onChanged: _securityStatus!.biometricAvailable 
                    ? _toggleBiometric 
                    : null,
                activeColor: AppColors.primaryBlue,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _securityStatus!.biometricAvailable
                ? _securityStatus!.biometricEnabled
                    ? 'Wallet access is protected with $_biometricType'
                    : 'Enable $_biometricType for enhanced security'
                : '$_biometricType is not available on this device',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupSection() {
    return GlassmorphismContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.backup,
                color: _securityStatus!.backupVerified 
                    ? Colors.green 
                    : Colors.orange,
                size: 24,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Backup Verification',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!_securityStatus!.backupVerified)
                ElevatedButton(
                  onPressed: _startBackupVerification,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: AppColors.textPrimary,
                  ),
                  child: const Text('Verify'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _securityStatus!.backupVerified
                ? '✅ Your backup phrase has been verified'
                : _securityStatus!.verificationRequired
                    ? '⚠️ Please verify your backup phrase for wallet recovery'
                    : '❌ Backup verification failed. Please review your backup.',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          if (_securityStatus!.verificationAttempts > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Verification attempts: ${_securityStatus!.verificationAttempts}/3',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecommendations() {
    final recommendations = _securityStatus!.recommendations;
    
    return GlassmorphismContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb, color: AppColors.primaryBlue, size: 24),
              SizedBox(width: 12),
              Text(
                'Security Recommendations',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...recommendations.map((rec) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '• ',
                  style: TextStyle(color: AppColors.primaryBlue, fontSize: 16),
                ),
                Expanded(
                  child: Text(
                    rec,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Future<void> _toggleBiometric(bool enabled) async {
    try {
      if (enabled) {
        final success = await _walletService.setupBiometricAuth();
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$_biometricType enabled successfully'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to enable biometric authentication'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        await _walletService.disableBiometricAuth();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$_biometricType disabled'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      
      await _loadSecurityStatus(); // Refresh status
    } catch (e) {
      print('Error toggling biometric: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error updating biometric settings'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _startBackupVerification() async {
    try {
      final challenge = await _walletService.createBackupChallenge();
      if (challenge == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to create backup verification challenge'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      // Navigate to backup verification screen
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => BackupVerificationScreen(challenge: challenge),
        ),
      );

      if (result == true) {
        await _loadSecurityStatus(); // Refresh status
      }
    } catch (e) {
      print('Error starting backup verification: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error starting backup verification'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

// Backup Verification Screen
class BackupVerificationScreen extends StatefulWidget {
  final BackupVerificationChallenge challenge;

  const BackupVerificationScreen({
    Key? key,
    required this.challenge,
  }) : super(key: key);

  @override
  State<BackupVerificationScreen> createState() => _BackupVerificationScreenState();
}

class _BackupVerificationScreenState extends State<BackupVerificationScreen> {
  final CardanoWalletService _walletService = CardanoWalletService();
  final Map<int, TextEditingController> _controllers = {};
  final Map<int, String> _answers = {};
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    for (final challenge in widget.challenge.challenges) {
      _controllers[challenge.position] = TextEditingController();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        title: const Text('Verify Backup'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GlassmorphismContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Backup Verification',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Please enter the words at the specified positions from your backup phrase:',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            Expanded(
              child: ListView.builder(
                itemCount: widget.challenge.challenges.length,
                itemBuilder: (context, index) {
                  final challenge = widget.challenge.challenges[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: GlassmorphismContainer(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Word #${challenge.position}',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _controllers[challenge.position],
                            onChanged: (value) {
                              _answers[challenge.position] = value;
                            },
                            decoration: InputDecoration(
                              hintText: 'Enter word ${challenge.position}',
                              hintStyle: const TextStyle(color: AppColors.textSecondary),
                              filled: true,
                              fillColor: AppColors.glassBackground,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppColors.glassBorder),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(color: AppColors.glassBorder),
                              ),
                            ),
                            style: const TextStyle(color: AppColors.textPrimary),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isVerifying ? null : _verifyBackup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: AppColors.textPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isVerifying
                    ? const CircularProgressIndicator(color: AppColors.textPrimary)
                    : const Text(
                        'Verify Backup',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _verifyBackup() async {
    setState(() => _isVerifying = true);

    try {
      final result = await _walletService.verifyBackupChallenge(
        widget.challenge,
        _answers,
      );

      if (result == null) {
        throw Exception('Failed to verify backup');
      }

      if (result.isVerified) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('🎉 Backup verification successful!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true); // Return success
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${result.correctAnswers}/${result.totalQuestions} correct. Please check your backup.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Error verifying backup: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error verifying backup'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isVerifying = false);
    }
  }
} 