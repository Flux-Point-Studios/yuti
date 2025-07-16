import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:hex/hex.dart';
import '../config/app_config.dart';
import '../config/secure_config.dart';
import 'blockfrost_service.dart';

enum WalletConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
}

class CardanoWalletService {
  static const _storage = FlutterSecureStorage();
  static const String _mnemonicKey = 'cardano_wallet_mnemonic';
  static const String _walletNameKey = 'cardano_wallet_name';
  static const String _isConnectedKey = 'cardano_wallet_connected';

  final AppConfig _config = AppConfig();
  final SecureConfig _secureConfig = SecureConfig();
  final BlockfrostService _blockfrostService = BlockfrostService();

  // Singleton pattern
  static final CardanoWalletService _instance =
      CardanoWalletService._internal();
  factory CardanoWalletService() => _instance;
  CardanoWalletService._internal();

  // Wallet state
  WalletConnectionStatus _connectionStatus =
      WalletConnectionStatus.disconnected;
  String? _currentAddress;
  String? _stakeAddress;
  String? _walletName;
  String? _mnemonic;
  bool _isMainnet = true;

  // Premium access state
  bool _premiumAccess = false;
  Map<String, dynamic> _premiumAccessDetails = {};

  // Getters
  WalletConnectionStatus get connectionStatus => _connectionStatus;
  String? get currentAddress => _currentAddress;
  String? get stakeAddress => _stakeAddress;
  String? get walletName => _walletName;
  bool get isMainnet => _isMainnet;
  bool get isConnected => _connectionStatus == WalletConnectionStatus.connected;
  bool get hasPremiumAccess => _premiumAccess;
  Map<String, dynamic> get premiumAccessDetails => _premiumAccessDetails;

  /// Initialize the wallet service
  Future<void> initialize() async {
    try {
      // Check if we have a stored wallet
      final isConnected = await _storage.read(key: _isConnectedKey);
      if (isConnected == 'true') {
        await _restoreWallet();
      }
    } catch (e) {
      print('Error initializing wallet service: $e');
    }
  }

  /// Create a new wallet with mnemonic (simplified version for premium access checking)
  Future<bool> createWallet(String walletName, {String? mnemonic}) async {
    try {
      _connectionStatus = WalletConnectionStatus.connecting;

      // Clean up any existing external wallet data
      await _storage.delete(key: 'external_wallet_address');
      await _storage.delete(key: 'external_wallet_stake_address');

      // For now, we'll store the mnemonic and generate a dummy address
      // In a real implementation, you'd use the proper Cardano SDK
      _mnemonic = mnemonic ?? _generateDummyMnemonic();
      _walletName = walletName;

      // Generate dummy addresses for testing
      // In a real implementation, you'd derive these from the mnemonic
      _currentAddress = _generateDummyAddress();
      _stakeAddress = _generateDummyStakeAddress();

      // Store wallet data securely
      await _storage.write(key: _mnemonicKey, value: _mnemonic);
      await _storage.write(key: _walletNameKey, value: walletName);
      await _storage.write(key: _isConnectedKey, value: 'true');

      _connectionStatus = WalletConnectionStatus.connected;

      // Check premium access
      await _checkPremiumAccess();

      return true;
    } catch (e) {
      print('Error creating wallet: $e');
      _connectionStatus = WalletConnectionStatus.error;
      return false;
    }
  }

  /// Restore wallet from stored mnemonic or external wallet data
  Future<bool> _restoreWallet() async {
    try {
      final walletName = await _storage.read(key: _walletNameKey);
      if (walletName == null) {
        return false;
      }

      _connectionStatus = WalletConnectionStatus.connecting;

      // Check if this is an external wallet (no mnemonic stored)
      final externalAddress =
          await _storage.read(key: 'external_wallet_address');
      final externalStakeAddress =
          await _storage.read(key: 'external_wallet_stake_address');

      if (externalAddress != null && externalStakeAddress != null) {
        // Restore external wallet
        _walletName = walletName;
        _currentAddress = externalAddress;
        _stakeAddress = externalStakeAddress;
        _mnemonic = null; // External wallet - no mnemonic

        print('Restored external wallet: $walletName');
      } else {
        // Restore mnemonic-based wallet
        final mnemonic = await _storage.read(key: _mnemonicKey);
        if (mnemonic == null) {
          return false;
        }

        _mnemonic = mnemonic;
        _walletName = walletName;
        _currentAddress = _generateDummyAddress();
        _stakeAddress = _generateDummyStakeAddress();

        print('Restored mnemonic-based wallet: $walletName');
      }

      _connectionStatus = WalletConnectionStatus.connected;

      // Check premium access
      await _checkPremiumAccess();

      return true;
    } catch (e) {
      print('Error restoring wallet: $e');
      _connectionStatus = WalletConnectionStatus.error;
      return false;
    }
  }

  /// Connect to existing wallet via mnemonic
  Future<bool> connectWallet(String mnemonic, String walletName) async {
    return await createWallet(walletName, mnemonic: mnemonic);
  }

  /// Connect external wallet (e.g., from GameChanger) without storing mnemonic
  Future<bool> connectExternalWallet(
      String walletName, String address, String stakeAddress) async {
    try {
      _connectionStatus = WalletConnectionStatus.connecting;

      // Validate inputs
      if (walletName.isEmpty || address.isEmpty || stakeAddress.isEmpty) {
        throw Exception('Invalid wallet data provided');
      }

      // Validate address formats (basic check)
      if (!_validateAddress(address) || !_validateStakeAddress(stakeAddress)) {
        throw Exception('Invalid address format');
      }

      // Clean up any existing mnemonic-based wallet data
      await _storage.delete(key: _mnemonicKey);

      // Set wallet data without storing mnemonic
      _walletName = walletName;
      _currentAddress = address;
      _stakeAddress = stakeAddress;
      _mnemonic = null; // External wallet - no mnemonic stored

      // Store wallet connection info (but not mnemonic)
      await _storage.write(key: _walletNameKey, value: walletName);
      await _storage.write(key: _isConnectedKey, value: 'true');
      await _storage.write(key: 'external_wallet_address', value: address);
      await _storage.write(
          key: 'external_wallet_stake_address', value: stakeAddress);

      _connectionStatus = WalletConnectionStatus.connected;

      // Check premium access
      await _checkPremiumAccess();

      print('External wallet connected successfully: $walletName');
      print('Address: $address');
      print('Stake Address: $stakeAddress');

      return true;
    } catch (e) {
      print('Error connecting external wallet: $e');
      _connectionStatus = WalletConnectionStatus.error;
      return false;
    }
  }

  /// Disconnect wallet
  Future<void> disconnectWallet() async {
    try {
      // Clear stored data (both mnemonic and external wallet data)
      await _storage.delete(key: _mnemonicKey);
      await _storage.delete(key: _walletNameKey);
      await _storage.delete(key: _isConnectedKey);
      await _storage.delete(key: 'external_wallet_address');
      await _storage.delete(key: 'external_wallet_stake_address');

      // Reset state
      _mnemonic = null;
      _walletName = null;
      _currentAddress = null;
      _stakeAddress = null;
      _connectionStatus = WalletConnectionStatus.disconnected;
      _premiumAccess = false;
      _premiumAccessDetails = {};
    } catch (e) {
      print('Error disconnecting wallet: $e');
    }
  }

  /// Get wallet UTXOs (simplified - delegates to BlockfrostService)
  Future<List<Map<String, dynamic>>> getWalletUtxos() async {
    if (_currentAddress == null) {
      throw Exception('Wallet not connected');
    }

    try {
      return await _blockfrostService.getUtxos(_currentAddress!);
    } catch (e) {
      print('Error getting wallet UTXOs: $e');
      throw Exception('Failed to get wallet UTXOs: $e');
    }
  }

  /// Get wallet balance (simplified - delegates to BlockfrostService)
  Future<Map<String, dynamic>> getWalletBalance() async {
    if (_currentAddress == null) {
      throw Exception('Wallet not connected');
    }

    try {
      final adaBalance =
          await _blockfrostService.getAdaBalance(_currentAddress!);
      final assets = await _blockfrostService.getAssets(_currentAddress!);

      return {
        'ada': adaBalance.toString(),
        'assets': assets,
      };
    } catch (e) {
      print('Error getting wallet balance: $e');
      throw Exception('Failed to get wallet balance: $e');
    }
  }

  /// Check premium access based on stake pool delegation and token holdings
  Future<void> _checkPremiumAccess() async {
    if (_stakeAddress == null) {
      _premiumAccess = false;
      return;
    }

    try {
      // Use the actual Blockfrost service to check premium access
      _premiumAccessDetails =
          await _blockfrostService.checkPremiumAccess(_stakeAddress!);
      _premiumAccess = _premiumAccessDetails['hasAccess'] ?? false;

      print(
          'Premium access check completed: ${_premiumAccess ? "GRANTED" : "DENIED"}');
      if (_premiumAccess) {
        print('Access level: ${_premiumAccessDetails['accessLevel']}');
        print('Reason: ${_premiumAccessDetails['reason']}');
      }
    } catch (e) {
      print('Error checking premium access: $e');
      _premiumAccess = false;
      _premiumAccessDetails = {
        'hasAccess': false,
        'accessLevel': 'error',
        'reason': 'Error checking premium access: $e',
        'details': {},
      };
    }
  }

  /// Get stake pool information
  Future<Map<String, dynamic>?> getStakePoolInfo() async {
    if (_stakeAddress == null) {
      return null;
    }

    try {
      // Get stake address info which includes pool delegation
      final stakeInfo =
          await _blockfrostService.getStakeAddressInfo(_stakeAddress!);

      if (stakeInfo['active'] == true && stakeInfo['pool_id'] != null) {
        return {
          'poolId': stakeInfo['pool_id'],
          'isActive': stakeInfo['active'],
          'controlledAmount': stakeInfo['controlled_amount'],
          'rewardsSum': stakeInfo['rewards_sum'],
          'withdrawalsSum': stakeInfo['withdrawals_sum'],
        };
      }

      return {
        'poolId': null,
        'isActive': false,
        'message': 'Stake address not delegated to any pool'
      };
    } catch (e) {
      print('Error getting stake pool info: $e');
      return null;
    }
  }

  /// Get token holdings
  Future<List<Map<String, dynamic>>> getTokenHoldings() async {
    if (_currentAddress == null) {
      return [];
    }

    try {
      return await _blockfrostService.getAssets(_currentAddress!);
    } catch (e) {
      print('Error getting token holdings: $e');
      return [];
    }
  }

  /// Get transaction history
  Future<List<Map<String, dynamic>>> getTransactionHistory() async {
    if (_currentAddress == null) {
      return [];
    }

    try {
      return await _blockfrostService.getTransactions(_currentAddress!);
    } catch (e) {
      print('Error getting transaction history: $e');
      return [];
    }
  }

  /// Export wallet mnemonic (for backup)
  Future<String?> exportMnemonic() async {
    try {
      return await _storage.read(key: _mnemonicKey);
    } catch (e) {
      print('Error exporting mnemonic: $e');
      return null;
    }
  }

  /// Switch network
  Future<void> switchNetwork(bool isMainnet) async {
    _isMainnet = isMainnet;

    // Reinitialize wallet with new network
    if (isConnected) {
      await _checkPremiumAccess();
    }
  }

  /// Generate dummy mnemonic for testing
  String _generateDummyMnemonic() {
    // In a real implementation, use proper BIP39 mnemonic generation
    const words = [
      'abandon',
      'ability',
      'able',
      'about',
      'above',
      'absent',
      'absorb',
      'abstract',
      'absurd',
      'abuse',
      'access',
      'accident',
      'account',
      'accuse',
      'achieve',
      'acid',
      'acoustic',
      'acquire',
      'across',
      'act',
      'action',
      'actor',
      'actress',
      'actual'
    ];

    final random = DateTime.now().millisecondsSinceEpoch;
    final selectedWords = <String>[];

    for (int i = 0; i < 24; i++) {
      selectedWords.add(words[random % words.length]);
    }

    return selectedWords.join(' ');
  }

  /// Generate dummy address for testing
  String _generateDummyAddress() {
    // Generate a dummy Cardano address for testing
    final random = DateTime.now().millisecondsSinceEpoch;
    final hash = sha256.convert(utf8.encode(random.toString()));
    final hex = HEX.encode(hash.bytes);

    // Create a dummy Cardano address format
    return 'addr1${hex.substring(0, 56)}';
  }

  /// Generate dummy stake address for testing
  String _generateDummyStakeAddress() {
    // Generate a dummy stake address for testing
    final random = DateTime.now().millisecondsSinceEpoch + 1;
    final hash = sha256.convert(utf8.encode(random.toString()));
    final hex = HEX.encode(hash.bytes);

    // Create a dummy stake address format
    return 'stake1${hex.substring(0, 56)}';
  }

  /// Validate Cardano address format (basic validation)
  bool _validateAddress(String address) {
    if (address.isEmpty) return false;

    // Basic Cardano address validation
    // Mainnet addresses start with 'addr1' and testnet with 'addr_test1'
    if (address.startsWith('addr1') || address.startsWith('addr_test1')) {
      // Check minimum length (Cardano addresses are typically ~100 characters)
      return address.length >= 50 && address.length <= 130;
    }

    return false;
  }

  /// Validate Cardano stake address format (basic validation)
  bool _validateStakeAddress(String stakeAddress) {
    if (stakeAddress.isEmpty) return false;

    // Basic stake address validation
    // Mainnet stake addresses start with 'stake1' and testnet with 'stake_test1'
    if (stakeAddress.startsWith('stake1') ||
        stakeAddress.startsWith('stake_test1')) {
      // Check minimum length (stake addresses are typically ~60 characters)
      return stakeAddress.length >= 50 && stakeAddress.length <= 80;
    }

    return false;
  }
}
