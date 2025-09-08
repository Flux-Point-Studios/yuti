import 'package:bip39_plus/bip39_plus.dart' as bip39;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'cardano_wallet_service.dart';

class WalletService {
  static const _storage = FlutterSecureStorage();
  static const String _mnemonicKey = 'wallet_mnemonic';
  static const String _walletsKey = 'wallets';

  final CardanoWalletService _cardanoWalletService = CardanoWalletService();
  String? _currentMnemonic;
  List<Wallet> _wallets = [];

  List<Wallet> get wallets => List.from(_wallets);
  bool get hasWallet => _currentMnemonic != null;
  bool get isWalletLoaded => _currentMnemonic != null && _wallets.isNotEmpty;
  String? get walletName => _wallets.isNotEmpty ? _wallets.first.name : null;

  Future<void> initialize() async {
    await _loadMnemonic();
    await _loadWallets();
  }

  Future<void> _loadMnemonic() async {
    _currentMnemonic = await _storage.read(key: _mnemonicKey);
  }

  Future<void> _loadWallets() async {
    try {
      final walletsJson = await _storage.read(key: _walletsKey);
      if (walletsJson != null) {
        final walletsList = json.decode(walletsJson) as List;
        _wallets = walletsList.map((w) => Wallet.fromJson(w)).toList();
      }
    } catch (e) {
      print('Error loading wallets: $e');
    }
  }

  Future<String> createWallet() async {
    try {
      // Create wallet using real Cardano SDK via CardanoWalletService
      final success = await _cardanoWalletService.createWallet('Main Wallet');
      
      if (!success) {
        throw Exception('Failed to create Cardano wallet');
      }

      // Get the generated mnemonic from CardanoWalletService
      final mnemonic = await _cardanoWalletService.exportMnemonic();
      if (mnemonic == null) {
        throw Exception('Failed to retrieve wallet mnemonic');
      }

      // Store mnemonic in WalletService storage as well (for compatibility)
      await _storage.write(key: _mnemonicKey, value: mnemonic);
      _currentMnemonic = mnemonic;

      // Create wallet record with real Cardano address
      final realAddress = _cardanoWalletService.currentAddress;
      if (realAddress == null) {
        throw Exception('Failed to get wallet address');
      }

      final wallet = Wallet(
        id: 'wallet_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Main Wallet',
        address: realAddress,
        balance: 0.0,
        createdAt: DateTime.now(),
      );

      _wallets.add(wallet);
      await _saveWallets();

      return mnemonic;
    } catch (e) {
      throw Exception('Failed to create wallet: $e');
    }
  }

  Future<bool> restoreWallet(String mnemonic) async {
    try {
      // Validate mnemonic using bip39 package
      if (!bip39.validateMnemonic(mnemonic)) {
        throw Exception('Invalid mnemonic phrase');
      }

      // Create wallet using real Cardano SDK with provided mnemonic
      final success = await _cardanoWalletService.createWallet('Restored Wallet', mnemonic: mnemonic);
      
      if (!success) {
        throw Exception('Failed to restore Cardano wallet');
      }

      // Store mnemonic in WalletService storage as well (for compatibility)
      await _storage.write(key: _mnemonicKey, value: mnemonic);
      _currentMnemonic = mnemonic;

      // Create wallet record with real Cardano address
      final realAddress = _cardanoWalletService.currentAddress;
      if (realAddress == null) {
        throw Exception('Failed to get wallet address');
      }

      final wallet = Wallet(
        id: 'wallet_${DateTime.now().millisecondsSinceEpoch}',
        name: 'Restored Wallet',
        address: realAddress,
        balance: 0.0,
        createdAt: DateTime.now(),
      );

      _wallets.clear();
      _wallets.add(wallet);
      await _saveWallets();

      return true;
    } catch (e) {
      throw Exception('Failed to restore wallet: $e');
    }
  }

  Future<void> _saveWallets() async {
    try {
      final walletsJson = json.encode(_wallets.map((w) => w.toJson()).toList());
      await _storage.write(key: _walletsKey, value: walletsJson);
    } catch (e) {
      print('Error saving wallets: $e');
    }
  }

  // Random friendly wallet name generator
  String generateRandomWalletName() {
    const adjectives = [
      'Silver','Azure','Crimson','Golden','Quantum','Luminous','Nebula','Silent','Swift','Shadow',
    ];
    const nouns = [
      'Falcon','Vertex','Aurora','Comet','Sentinel','Harbor','Forge','Beacon','Atlas','Nova',
    ];
    final now = DateTime.now().millisecondsSinceEpoch;
    final adj = adjectives[now % adjectives.length];
    final noun = nouns[(now ~/ 7) % nouns.length];
    return '$adj $noun';
  }

  Future<void> renameWallet(String newName) async {
    if (_wallets.isEmpty) return;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;
    _wallets[0] = _wallets[0].copyWith(name: trimmed);
    await _saveWallets();
  }

  // Note: Dummy address generation removed - now using real Cardano SDK addresses

  Future<String> getReceiveAddress() async {
    // Return real Cardano address from CardanoWalletService if available
    if (_cardanoWalletService.isConnected && _cardanoWalletService.currentAddress != null) {
      return _cardanoWalletService.currentAddress!;
    }
    
    // Fallback to stored wallet address
    if (_wallets.isEmpty) {
      throw Exception('No wallet available');
    }
    return _wallets.first.address;
  }

  bool validateAddress(String address) {
    // Basic validation for Cardano addresses
    if (address.isEmpty) return false;

    // Shelley addresses (current era)
    if (address.startsWith('addr1') || address.startsWith('addr_test1')) {
      return address.length >= 50 && address.length <= 120;
    }

    // Byron addresses (legacy)
    if (address.startsWith('Ddz') || address.startsWith('Ae2')) {
      return address.length >= 50;
    }

    return false;
  }

  Future<void> deleteWallet() async {
    await _storage.delete(key: _mnemonicKey);
    await _storage.delete(key: _walletsKey);
    _currentMnemonic = null;
    _wallets.clear();
  }

  String? getMnemonic() {
    return _currentMnemonic;
  }

  List<String> getMnemonicWords() {
    return _currentMnemonic?.split(' ') ?? [];
  }

  // Mock balance update for demo
  Future<void> updateBalance(String walletId, double newBalance) async {
    final walletIndex = _wallets.indexWhere((w) => w.id == walletId);
    if (walletIndex != -1) {
      _wallets[walletIndex] =
          _wallets[walletIndex].copyWith(balance: newBalance);
      await _saveWallets();
    }
  }
}

class Wallet {
  final String id;
  final String name;
  final String address;
  final double balance;
  final DateTime createdAt;

  Wallet({
    required this.id,
    required this.name,
    required this.address,
    required this.balance,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'balance': balance,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Wallet.fromJson(Map<String, dynamic> json) {
    return Wallet(
      id: json['id'],
      name: json['name'],
      address: json['address'],
      balance: json['balance'].toDouble(),
      createdAt: DateTime.parse(json['createdAt']),
    );
  }

  Wallet copyWith({
    String? id,
    String? name,
    String? address,
    double? balance,
    DateTime? createdAt,
  }) {
    return Wallet(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      balance: balance ?? this.balance,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
