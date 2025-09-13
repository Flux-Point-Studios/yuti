import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cardano_flutter_sdk/cardano_flutter_sdk.dart';
import 'package:cardano_dart_types/cardano_dart_types.dart';
import '../services/auth_service.dart';
import '../services/gamechanger_service.dart';
import '../screens/gamechanger_callback_screen.dart';
import '../utils/app_colors.dart';
import '../config/app_config.dart';
import '../services/blockfrost_service.dart';
import '../screens/smart_wallet_activation_screen.dart';
import '../services/smart_wallet_service.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

class CardanoWalletDialog extends StatefulWidget {
  final AuthService authService;
  final bool smartWalletOnly;

  const CardanoWalletDialog({
    Key? key,
    required this.authService,
    this.smartWalletOnly = false,
  }) : super(key: key);

  @override
  State<CardanoWalletDialog> createState() => _CardanoWalletDialogState();
}

enum ConnectionMode { mnemonic, gameChanger, smartWallet, createNew }

class _CardanoWalletDialogState extends State<CardanoWalletDialog> {
  final TextEditingController _mnemonicController = TextEditingController();
  final TextEditingController _walletNameController = TextEditingController();
  final GameChangerService _gameChangerService = GameChangerService();
  final BlockfrostService _blockfrost = BlockfrostService();

  BigInt? _requiredAgent;
  double? _agentPerAda;
  double? _adaUsd;
  bool _loadingRequiredAgent = false;

  bool _isLoading = false;
  bool _isObscured = true;
  bool _showQrCode = false;
  String? _errorMessage;
  String? _qrCodeUrl;
  ConnectionMode _connectionMode = ConnectionMode.smartWallet;
  
  // Security state for mnemonic display
  bool _hasAcknowledgedSecurityWarning = false;

  @override
  void initState() {
    super.initState();
    print('🔍 DEBUG: CardanoWalletDialog initState() called');
    print('🔍 DEBUG: Initial connection mode: $_connectionMode');
    print('🔍 DEBUG: Initial loading state: $_isLoading');
    _loadRequiredAgent();
  }
  
  Future<void> _loadRequiredAgent() async {
    try {
      setState(() => _loadingRequiredAgent = true);
      print('🔍 DEBUG: Loading required AGENT amount (fixed threshold: 100000)');
      final required = BigInt.from(100000);
      final double? adaUsd = null;
      // agentPerAda not used with fixed threshold
      setState(() {
        _agentPerAda = null;
        _adaUsd = adaUsd;
        _requiredAgent = required;
        _loadingRequiredAgent = false;
      });
      print('🔍 DEBUG: Dialog required AGENT tokens (fixed): ' + required.toString());
    } catch (e) {
      print('🔍 DEBUG: Failed to load required AGENT amount: ' + e.toString());
      if (mounted) setState(() => _loadingRequiredAgent = false);
    }
  }

  String _formatWithCommas(BigInt value) {
    final s = value.toString();
    final out = StringBuffer();
    int count = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      out.write(s[i]);
      count++;
      if (count == 3 && i != 0) {
        out.write(',');
        count = 0;
      }
    }
    return out.toString().split('').reversed.join();
  }

  @override
  void dispose() {
    print('🔍 DEBUG: CardanoWalletDialog dispose() called');
    _mnemonicController.dispose();
    _walletNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: AppColors.backgroundDark,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primaryBlue.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                child: _buildContent(),
              ),
            ),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primaryBlue.withOpacity(0.1),
            Colors.transparent,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet,
                color: AppColors.primaryBlue,
                size: 32,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Connect Cardano Wallet',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: Colors.white.withOpacity(0.7)),
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Connect your Cardano wallet to verify premium access via \$AGENT token holdings (dynamic \$ value).',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!widget.smartWalletOnly) _buildConnectionModeSelector(),
          if (!widget.smartWalletOnly) const SizedBox(height: 20),
          if (widget.smartWalletOnly) ...[
            _buildSmartWalletSection(),
          ] else if (_connectionMode == ConnectionMode.mnemonic) ...[
            _buildWalletNameField(),
            const SizedBox(height: 16),
            _buildMnemonicField(),
          ] else if (_connectionMode == ConnectionMode.smartWallet) ...[
            _buildSmartWalletSection(),
          ],
          const SizedBox(height: 16),
          if (!widget.smartWalletOnly) _buildPremiumAccessInfo(),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            _buildErrorMessage(),
          ],
        ],
      ),
    );
  }

  Widget _buildWalletNameField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Wallet Name',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _walletNameController,
          style: const TextStyle(color: Colors.white),
          onChanged: (text) {
            print('🔍 DEBUG: Wallet name field changed: "${text}"');
            print(
                '🔍 DEBUG: Wallet name controller text: "${_walletNameController.text}"');
          },
          decoration: InputDecoration(
            hintText: 'Enter a name for your wallet',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            filled: true,
            fillColor: Colors.white.withOpacity(0.1),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primaryBlue),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMnemonicField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mnemonic Phrase (12, 15, 18, 21, or 24 words)',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _mnemonicController,
          style: const TextStyle(color: Colors.white),
          obscureText: _isObscured,
          maxLines: _isObscured ? 1 : 3,
          onChanged: (text) {
            print('🔍 DEBUG: Mnemonic field changed: "${text}"');
            print('🔍 DEBUG: Text length: ${text.length}');
            print('🔍 DEBUG: Controller text: "${_mnemonicController.text}"');
          },
          decoration: InputDecoration(
            hintText: 'Enter your mnemonic phrase (12-24 words)',
            hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
            filled: true,
            fillColor: Colors.white.withOpacity(0.1),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primaryBlue),
            ),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    _isObscured ? Icons.visibility : Icons.visibility_off,
                    color: Colors.white.withOpacity(0.7),
                  ),
                  onPressed: () {
                    setState(() {
                      _isObscured = !_isObscured;
                    });
                  },
                ),
                IconButton(
                  icon: Icon(
                    Icons.paste,
                    color: Colors.white.withOpacity(0.7),
                  ),
                  onPressed: _pasteFromClipboard,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Connection Method',
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 12),
        // Only Smart Wallet and Import
        Row(
          children: [
            Expanded(
              child: _buildModeOption(
                mode: ConnectionMode.smartWallet,
                title: 'Smart Wallet',
                subtitle: 'Seedless with Google Login',
                icon: Icons.lock_open,
                isSelected: _connectionMode == ConnectionMode.smartWallet,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildModeOption(
                mode: ConnectionMode.mnemonic,
                title: 'Import / Restore',
                subtitle: 'Use 12-24 word phrase',
                icon: Icons.vpn_key,
                isSelected: _connectionMode == ConnectionMode.mnemonic,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildModeOption({
    required ConnectionMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    bool isFullWidth = false,
  }) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _connectionMode = mode;
          _errorMessage = null;
          _showQrCode = false;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryBlue.withOpacity(0.2)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryBlue
                : Colors.white.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected
                  ? AppColors.primaryBlue
                  : Colors.white.withOpacity(0.7),
              size: 24,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameChangerSection() {
    // Hidden in Smart Wallet-only UI
    return const SizedBox.shrink();
  }

  Widget _buildQrCodeSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          const Text(
            'Scan with GameChanger Wallet',
            style: TextStyle(
              color: Colors.black,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.orange.withOpacity(0.3)),
            ),
            child: Text(
              '⚠️ QR scanning must be done on the same device where this app is running',
              style: TextStyle(
                color: Colors.orange.shade700,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          QrImageView(
            data: _qrCodeUrl!,
            version: QrVersions.auto,
            size: 200.0,
            backgroundColor: Colors.white,
          ),
          const SizedBox(height: 12),
          Text(
            'Open GameChanger wallet on this device and scan this QR code',
            style: TextStyle(
              color: Colors.black.withOpacity(0.7),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPremiumAccessInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.info,
                color: Colors.blue,
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Premium Access Requirements',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final usdTarget = AppConfig().premiumUsdPrice;
              final amountStr = _requiredAgent != null
                  ? _formatWithCommas(_requiredAgent!)
                  : (_loadingRequiredAgent ? 'calculating…' : 'unavailable');
              final ratesStr = (_agentPerAda != null && _adaUsd != null)
                  ? ' (rates: ${NumberFormat('0.######').format(_agentPerAda!)} AGENT/ADA, ${NumberFormat('0.####').format(_adaUsd!)} USD/ADA)'
                  : '';
              return Text(
                'Your wallet will be checked for:\n'
                '• ' + amountStr + ' \$AGENT tokens (≈\$' + usdTarget.toStringAsFixed(0) + ' USD, stake-wide)' + ratesStr,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 12,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildErrorMessage() {
    final isChromeBrowserIssue = _errorMessage != null && 
        _errorMessage!.contains('Chrome Default Browser Issue');
        
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isChromeBrowserIssue 
                ? Colors.orange.withOpacity(0.1) 
                : Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isChromeBrowserIssue 
                  ? Colors.orange.withOpacity(0.3)
                  : Colors.red.withOpacity(0.3)
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isChromeBrowserIssue ? Icons.settings : Icons.error,
                color: isChromeBrowserIssue ? Colors.orange : Colors.red,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: isChromeBrowserIssue ? Colors.orange : Colors.red,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Show retry button for Chrome browser issue
        if (isChromeBrowserIssue) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : () {
                setState(() {
                  _errorMessage = null; // Clear error message
                });
                _connectWithGameChanger(); // Retry connection
              },
              icon: Icon(Icons.refresh, size: 16),
              label: Text('Retry After Switching to Safari'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed:
                  _isLoading ? null : () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.white.withOpacity(0.3)),
                ),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          if (!widget.smartWalletOnly && _connectionMode == ConnectionMode.mnemonic)
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : () {
                        print('🔍 DEBUG: Connect Wallet button pressed');
                        print('🔍 DEBUG: _isLoading state: $_isLoading');
                        print('🔍 DEBUG: _connectionMode: $_connectionMode');
                        print(
                            '🔍 DEBUG: Mnemonic field text: "${_mnemonicController.text}"');
                        print(
                            '🔍 DEBUG: Wallet name field text: "${_walletNameController.text}"');
                        _connectWallet();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Connect Wallet',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    print('🔍 DEBUG: _pasteFromClipboard() called');
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      print('🔍 DEBUG: Clipboard data: ${clipboardData?.text}');
      if (clipboardData?.text != null) {
        print(
            '🔍 DEBUG: Setting mnemonic controller text to: "${clipboardData!.text!}"');
        _mnemonicController.text = clipboardData!.text!;
        print(
            '🔍 DEBUG: Controller text after paste: "${_mnemonicController.text}"');
      } else {
        print('🔍 DEBUG: No clipboard data available');
      }
    } catch (e) {
      print('🔍 DEBUG: Error pasting from clipboard: $e');
    }
  }

  Future<void> _connectWithGameChanger() async {
    print('🔍 DEBUG: _connectWithGameChanger() called');
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _showQrCode = false;
    });

    try {
      print('🔍 DEBUG: Attempting GameChanger connection...');

      // Use GameChanger service to connect wallet
      final walletData =
          await _gameChangerService.connectWallet(isMainnet: true);

      print('🔍 DEBUG: GameChanger connection successful');
      print('🔍 DEBUG: Wallet data: ${walletData.toString()}');

      // Validate network (ensure it's mainnet for production)
      if (!walletData.isMainnet()) {
        print('🔍 DEBUG: Network validation failed - not mainnet');
        throw Exception(
            'Please use a mainnet wallet. Testnet wallets are not supported.');
      }

      print('🔍 DEBUG: Network validation passed');

      // Connect external wallet in AuthService
      final success = await widget.authService.connectCardanoWalletExternal(
        walletData.walletName,
        walletData.address,
        walletData.stakeAddress,
      );

      print('🔍 DEBUG: AuthService connection result: $success');

      if (!success) {
        throw Exception('Failed to connect wallet. Please try again.');
      }

      print('🔍 DEBUG: GameChanger connection flow completed successfully');
      Navigator.of(context).pop(true);
    } catch (e) {
      print('🔍 DEBUG: GameChanger connection error: $e');

      // Handle special Android fallback redirect signal
      if (e.toString().contains('REDIRECT_TO_CALLBACK_SCREEN')) {
        print('🔍 DEBUG: Android fallback redirect signal detected - navigating to callback screen');
        
        setState(() {
          _isLoading = false;
        });
        
        // Navigate to callback screen for Android fallback only
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => const GameChangerCallbackScreen(),
          ),
        ).then((result) {
          // If callback screen returns with success, close this dialog
          if (result == true) {
            Navigator.of(context).pop(true);
          }
        });
        return;
      }

      // Enhanced error handling with specific focus on cancellation
      String errorMessage = _parseErrorMessage(e);

      setState(() {
        _errorMessage = errorMessage;
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _showQrCodeForGameChanger() async {
    setState(() {
      _errorMessage = null;
    });

    try {
      // Generate QR code URL for GameChanger
      final qrUrl = _gameChangerService.generateQrCodeUrl(isMainnet: true);

      setState(() {
        _qrCodeUrl = qrUrl;
        _showQrCode = true;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to generate QR code: ${e.toString()}';
      });
    }
  }

  Future<void> _connectWallet() async {
    print('🔍 DEBUG: _connectWallet() called');
    print('🔍 DEBUG: Current connection mode: $_connectionMode');
    print('🔍 DEBUG: _isLoading before: $_isLoading');
    print('🔍 DEBUG: _errorMessage before: $_errorMessage');

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    print('🔍 DEBUG: _isLoading after setState: $_isLoading');

    try {
      final mnemonic = _mnemonicController.text.trim();
      final walletName = _walletNameController.text.trim();

      print(
          '🔍 DEBUG: Raw mnemonic controller text length: ${_mnemonicController.text.length}');
      print(
          '🔍 DEBUG: Raw mnemonic controller text: "${_mnemonicController.text}"');
      print('🔍 DEBUG: Trimmed mnemonic length: ${mnemonic.length}');
      print('🔍 DEBUG: Trimmed mnemonic: "$mnemonic"');
      print('🔍 DEBUG: Wallet name: "$walletName"');

      if (mnemonic.isEmpty) {
        print('🔍 DEBUG: Mnemonic is empty - throwing exception');
        throw Exception('Please enter your mnemonic phrase');
      }

      if (walletName.isEmpty) {
        print('🔍 DEBUG: Wallet name is empty - throwing exception');
        throw Exception('Please enter a wallet name');
      }

      // Clean and validate mnemonic format (robust whitespace handling)
      final cleanMnemonic = mnemonic
          .trim() // Remove leading/trailing whitespace
          .replaceAll(RegExp(r'\s+'),
              ' '); // Replace multiple whitespace with single space

      print('🔍 DEBUG: Clean mnemonic: "$cleanMnemonic"');
      print('🔍 DEBUG: Clean mnemonic length: ${cleanMnemonic.length}');

      final words = cleanMnemonic
          .split(' ') // Split on single spaces
          .where((word) => word.isNotEmpty) // Remove any empty strings
          .toList();

      print('🔍 DEBUG: Split into ${words.length} words');
      print('🔍 DEBUG: Words: $words');

      for (int i = 0; i < words.length; i++) {
        print('🔍 DEBUG: Word $i: "${words[i]}" (length: ${words[i].length})');
      }

      // Valid BIP39 mnemonic word counts: 12, 15, 18, 21, 24
      final validWordCounts = [12, 15, 18, 21, 24];
      if (!validWordCounts.contains(words.length)) {
        print('🔍 DEBUG: Invalid word count - throwing exception');
        throw Exception(
            'Mnemonic must be 12, 15, 18, 21, or 24 words. Found ${words.length} words.');
      }

      print(
          '🔍 DEBUG: Mnemonic validation passed - attempting wallet connection');

      // Connect the Cardano wallet with cleaned mnemonic
      final success = await widget.authService
          .connectCardanoWallet(cleanMnemonic, walletName);

      print('🔍 DEBUG: Wallet connection result: $success');

      if (success) {
        print('🔍 DEBUG: Wallet connection successful - closing dialog');
        Navigator.of(context).pop(true);
      } else {
        print('🔍 DEBUG: Wallet connection failed - throwing exception');
        throw Exception(
            'Failed to connect wallet. Please check your mnemonic phrase.');
      }
    } catch (e) {
      print('🔍 DEBUG: Exception caught: $e');
      print('🔍 DEBUG: Exception type: ${e.runtimeType}');
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
      print('🔍 DEBUG: Error message set to: $_errorMessage');
    } finally {
      print('🔍 DEBUG: Setting _isLoading to false');
      setState(() {
        _isLoading = false;
      });
      print('🔍 DEBUG: _isLoading after finally: $_isLoading');
    }
  }

  Widget _buildCreateNewWalletSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.primaryBlue.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                Icons.security,
                color: AppColors.primaryBlue,
                size: 32,
              ),
              const SizedBox(height: 12),
              Text(
                'Generate New Wallet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Create a brand new Cardano wallet with a secure recovery phrase. You\'ll receive a 24-word recovery phrase that you must keep safe.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _generateNewWallet,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text(
                        'Generate Wallet',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _generateNewWallet() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Generate new 24-word mnemonic using Cardano SDK
      final newMnemonicWords = WalletFactory.generateNewMnemonic(
        wordsCount: MnemonicsWordsCount.w24,
      );
      final newMnemonic = newMnemonicWords.join(' ');
      
      // Connect the wallet using the real mnemonic
      final success = await widget.authService.connectCardanoWallet(
        newMnemonic, 
        'Generated Wallet',
      );
      
      if (success) {
        // Show the mnemonic to the user for backup before closing
        if (mounted) {
          await _showMnemonicBackupDialog(newMnemonic);
        }
        
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } else {
        setState(() {
          _errorMessage = 'Failed to create wallet. Please try again.';
        });
      }
      
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to generate wallet: ${e.toString()}';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildSmartWalletSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primaryBlue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primaryBlue.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.lock_open,
                    color: AppColors.primaryBlue,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Seedless Smart Wallet (Google)',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in with Google to access your seedless Smart Wallet. If it’s new, we’ll guide you through activation.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isLoading ? null : _connectWithSmartWallet,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.login, size: 18),
                  label: Text(
                    _isLoading ? 'Connecting…' : 'Continue with Google',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _connectWithSmartWallet() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _showQrCode = false;
    });

    try {
      print('🔍 DEBUG: Starting Smart Wallet Google flow…');
      final smart = SmartWalletService();

      if (kIsWeb) {
                 final url = await smart.buildGoogleAuthUrlWeb(useZkFoldRedirect: false);
         _showToast('Redirecting to Google…');
         await launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault);
         setState(() { _isLoading = false; });
         return;
      }

      final auth = await smart.continueWithGoogle();
      print('🔍 DEBUG: Google login ok for ${auth.email}');

      // Attempt in-app activation path first
      var address = await smart.getWalletAddressByEmail(auth.email);
      if (address == null || address.isEmpty) {
        print('🔍 DEBUG: No address yet; attempting in-app activation…');
        _showToast('Activating Smart Wallet… this can take a few minutes');
        final activated = await smart.activateSeedlessWallet(idToken: auth.idToken, email: auth.email);
        if (activated != null && activated.isNotEmpty) {
          address = activated;
        }
      }

      if (address == null || address.isEmpty) {
        print('🔍 DEBUG: In-app activation not complete; opening embedded activation page');
        final activated = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (context) => SmartWalletActivationScreen(email: auth.email),
          ),
        );
        if (activated == true) {
          address = await smart.getWalletAddressByEmail(auth.email);
        }
      }

      if (address == null || address.isEmpty) {
        throw Exception('Smart Wallet not activated yet. Please finish activation.');
      }

      final walletName = 'Smart Wallet (${auth.email})';
      final success = await widget.authService.connectCardanoWalletExternal(
        walletName,
        address,
        '',
      );

      if (!success) {
        throw Exception('Failed to connect Smart Wallet');
      }

      _showToast('Smart Wallet connected');
      Navigator.of(context).pop(true);
    } catch (e) {
      print('🔍 DEBUG: Smart Wallet connection error: $e');
      setState(() {
        _errorMessage = e.toString();
      });
      _showToast('Smart Wallet error: ${e.toString()}');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Show mnemonic backup dialog to user with security warning
  Future<void> _showMnemonicBackupDialog(String mnemonic) async {
    // Reset security acknowledgment for each new dialog
    _hasAcknowledgedSecurityWarning = false;
    
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: AppColors.backgroundDark,
              title: Text(
                'Backup Your Wallet',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_hasAcknowledgedSecurityWarning) ...[
                      // Security Warning Section
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.error.withOpacity(0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.security,
                                  color: AppColors.error,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'SECURITY WARNING',
                                  style: TextStyle(
                                    color: AppColors.error,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Before revealing your seed phrase:\n\n'
                              '• Ensure you are in a private location\n'
                              '• Make sure no one can see your screen\n'
                              '• Check for cameras or recording devices\n'
                              '• Never share this phrase with anyone\n\n'
                              'Anyone with access to these words can steal your funds!',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Center(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _hasAcknowledgedSecurityWarning = true;
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          ),
                          child: const Text('I Understand - Show Seed Phrase'),
                        ),
                      ),
                    ] else ...[
                      // Mnemonic Display Section
                      Text(
                        'IMPORTANT: Save these 24 words in a safe place. This is the only way to recover your wallet!',
                        style: TextStyle(
                          color: AppColors.primaryBlue,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundLight.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.primaryBlue.withOpacity(0.3)),
                        ),
                        child: SelectableText(
                          mnemonic,
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '• Write down these words in order\n• Keep them safe and private\n• Never share them with anyone\n• You will need them to restore your wallet',
                        style: TextStyle(
                          color: AppColors.textSecondary.withOpacity(0.8),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Enhanced Security Features info
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBlue.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.primaryBlue.withOpacity(0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.security,
                                  color: AppColors.primaryBlue,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Enhanced Security Features',
                                  style: TextStyle(
                                    color: AppColors.primaryBlue,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '🔐 Biometric authentication available\n✅ Backup verification system\n🔑 On-demand key derivation',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Access Security Settings from your wallet after setup.',
                              style: TextStyle(
                                color: AppColors.primaryBlue.withOpacity(0.8),
                                fontSize: 10,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: _hasAcknowledgedSecurityWarning ? [
                TextButton(
                  onPressed: () async {
                    // Copy to clipboard
                    await Clipboard.setData(ClipboardData(text: mnemonic));
                    
                    // Show confirmation with overlay to ensure visibility
                    _showCopyConfirmation(context);
                  },
                  child: Text(
                    'Copy',
                    style: TextStyle(color: AppColors.primaryBlue),
                  ),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('I\'ve Saved It'),
                ),
              ] : [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Show copy confirmation with overlay to ensure visibility above modal
  void _showCopyConfirmation(BuildContext context) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).size.height * 0.1,
        left: 0,
        right: 0,
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryBlue.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Mnemonic copied to clipboard',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    
    overlay.insert(overlayEntry);
    
    // Remove after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      overlayEntry.remove();
    });
  }

  /// Parse error message to provide user-friendly feedback
  String _parseErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();
    
    // Handle Chrome default browser issue (iOS-specific)
    if (errorString.contains('chrome_default_browser_issue')) {
      return '''🚨 Chrome Default Browser Issue Detected

The GameChanger connection failed because Chrome is your default browser. 

✅ SOLUTION:
1. Go to iOS Settings → Safari → Default Browser App
2. Select "Safari" (temporarily)
3. Return to Yuti and try connecting again
4. You should see "Return to Yuti" instead of "Done"

📱 WHY: iOS ASWebAuthenticationSession requires Safari for custom URL callbacks. Chrome blocks the return to Yuti.

After connecting, you can switch back to Chrome as default.''';
    }

    // Handle regular cancellation
    if (errorString.contains('canceled') || 
        errorString.contains('cancelled') ||
        errorString.contains('user canceled') ||
        errorString.contains('connection cancelled by user')) {
      return 'Connection cancelled. No worries - you can try connecting again anytime.';
    }

    // Handle specific GameChanger errors
    if (errorString.contains('unknown request') ||
        errorString.contains('failed to decode') ||
        errorString.contains('gamechangerexception')) {
      return '''Connection failed. Try these steps:

• Ensure GameChanger wallet is unlocked
• Disable other wallet extensions (VeWorld, Eternl, etc.)
• Use an incognito browser window
• Make sure wallet is on mainnet network''';
    }

    // Handle network errors
    if (errorString.contains('network') || errorString.contains('testnet')) {
      return 'Please ensure your wallet is connected to the Cardano mainnet.';
    }

    // Handle permission errors
    if (errorString.contains('permission') || errorString.contains('access')) {
      return 'Permission denied. Please ensure GameChanger wallet is unlocked and accessible.';
    }

    // Generic error handling
    final cleanedError = error.toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('GameChangerException: ', '')
        .replaceFirst('PlatformException(CANCELED, ', '')
        .replaceFirst(', null, null)', '');

    return 'Connection failed: $cleanedError';
  }

  void _showToast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: AppColors.primaryBlue,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
 }
