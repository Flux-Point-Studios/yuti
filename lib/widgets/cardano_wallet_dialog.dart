import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/auth_service.dart';
import '../services/gamechanger_service.dart';
import '../utils/app_colors.dart';

class CardanoWalletDialog extends StatefulWidget {
  final AuthService authService;

  const CardanoWalletDialog({
    Key? key,
    required this.authService,
  }) : super(key: key);

  @override
  State<CardanoWalletDialog> createState() => _CardanoWalletDialogState();
}

enum ConnectionMode { mnemonic, gameChanger }

class _CardanoWalletDialogState extends State<CardanoWalletDialog> {
  final TextEditingController _mnemonicController = TextEditingController();
  final TextEditingController _walletNameController = TextEditingController();
  final GameChangerService _gameChangerService = GameChangerService();

  bool _isLoading = false;
  bool _isObscured = true;
  bool _showQrCode = false;
  String? _errorMessage;
  String? _qrCodeUrl;
  ConnectionMode _connectionMode = ConnectionMode.mnemonic;

  @override
  void initState() {
    super.initState();
    print('🔍 DEBUG: CardanoWalletDialog initState() called');
    print('🔍 DEBUG: Initial connection mode: $_connectionMode');
    print('🔍 DEBUG: Initial loading state: $_isLoading');
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
            _buildContent(),
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
            'Connect your Cardano wallet to verify premium access based on your token holdings and stake pool delegation.',
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
          _buildConnectionModeSelector(),
          const SizedBox(height: 20),
          if (_connectionMode == ConnectionMode.mnemonic) ...[
            _buildWalletNameField(),
            const SizedBox(height: 16),
            _buildMnemonicField(),
          ] else ...[
            _buildGameChangerSection(),
          ],
          const SizedBox(height: 16),
          _buildPremiumAccessInfo(),
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
          'Mnemonic Phrase (12 or 24 words)',
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
            hintText: 'Enter your 12 or 24 word mnemonic phrase',
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
        Row(
          children: [
            Expanded(
              child: _buildModeOption(
                mode: ConnectionMode.gameChanger,
                title: 'GameChanger Wallet',
                subtitle: 'Secure connection (Recommended)',
                icon: Icons.link,
                isSelected: _connectionMode == ConnectionMode.gameChanger,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildModeOption(
                mode: ConnectionMode.mnemonic,
                title: 'Recovery Phrase',
                subtitle: 'Import with 12/24 words',
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
                    Icons.security,
                    color: AppColors.primaryBlue,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Secure GameChanger Connection',
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
                'Connect securely using GameChanger wallet without entering your recovery phrase. Your private keys never leave your wallet.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _connectWithGameChanger,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text(
                        'Connect Wallet',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _showQrCodeForGameChanger,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white.withOpacity(0.5),
                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: Icon(Icons.qr_code,
                        size: 18, color: Colors.white.withOpacity(0.5)),
                    label: Text(
                      'QR Code',
                      style: TextStyle(
                          fontSize: 14, color: Colors.white.withOpacity(0.5)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_showQrCode && _qrCodeUrl != null) ...[
          const SizedBox(height: 16),
          _buildQrCodeSection(),
        ],
      ],
    );
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
          Text(
            'Your wallet will be checked for:\n'
            '• Stake pool delegation (1000+ ADA)\n'
            '• T1 ADAM Launch Pass NFT\n'
            '• \$SHARDS tokens (3,500+)\n'
            '• \$AGENT tokens (100,000+)\n'
            '• Legacy and special access tokens',
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error,
            color: Colors.red,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: const TextStyle(
                color: Colors.red,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
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
          if (_connectionMode == ConnectionMode.mnemonic)
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
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _showQrCode = false;
    });

    try {
      // Use GameChanger service to connect wallet
      final walletData =
          await _gameChangerService.connectWallet(isMainnet: true);

      // Validate network (ensure it's mainnet for production)
      if (!walletData.isMainnet()) {
        throw Exception(
            'Please use a mainnet wallet. Testnet wallets are not supported.');
      }

      // Connect external wallet in AuthService
      final success = await widget.authService.connectCardanoWalletExternal(
        walletData.walletName,
        walletData.address,
        walletData.stakeAddress,
      );

      if (!success) {
        throw Exception('Failed to connect wallet. Please try again.');
      }

      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceFirst('Exception: ', '');
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

      if (words.length != 12 && words.length != 24) {
        print('🔍 DEBUG: Invalid word count - throwing exception');
        throw Exception(
            'Mnemonic must be 12 or 24 words. Found ${words.length} words.');
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
}
