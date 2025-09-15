import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../services/auth_service.dart';
import '../services/cardano_wallet_service.dart';
import '../services/wallet_service.dart';
import '../services/transaction_history_service.dart';
import '../services/address_book_service.dart';
import '../utils/app_colors.dart';
import '../widgets/glassmorphism_container.dart';
import '../widgets/wallet_security_settings.dart';
import 'send_screen.dart';
import 'swap_screen.dart';
import 'transactions_screen.dart';
import 'address_book_screen.dart';
import '../services/blockfrost_service.dart'; // Added import for BlockfrostService
import '../services/asset_cache_service.dart';
import '../config/app_config.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../widgets/cardano_wallet_dialog.dart';

class WalletScreen extends StatefulWidget {
  final AuthService authService;

  const WalletScreen({
    Key? key,
    required this.authService,
  }) : super(key: key);

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final CardanoWalletService _walletService = CardanoWalletService();
  final WalletService _localWalletService = WalletService();
  final TransactionHistoryService _transactionHistoryService = TransactionHistoryService();
  final AddressBookService _addressBookService = AddressBookService();
  final BlockfrostService _blockfrostService = BlockfrostService(); // Added BlockfrostService
  final AssetCacheService _assetCache = AssetCacheService();
  
  bool _isLoading = false;
  Map<String, dynamic>? _walletBalance;
  List<Map<String, dynamic>>? _tokenHoldings;
  List<Map<String, dynamic>> _tokensOnly = [];
  List<Map<String, dynamic>> _nftsOnly = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _walletService.initialize().then((_) async {
      await _ensureWalletConnectedFromUser();
      await _loadWalletData();
    });
    _localWalletService.initialize().then((_) {
      debugPrint('🔍 DEBUG: WalletScreen init - local wallet name: ${_localWalletService.walletName}');
      setState(() {});
    });
  }

  Future<void> _initializeServices() async {
    await _transactionHistoryService.initialize();
    await _addressBookService.initialize();
  }

  Future<void> _ensureWalletConnectedFromUser() async {
    try {
      if (_walletService.isConnected) return;
      final user = widget.authService.currentUser;
      final address = user?.walletAddress;
      final stake = user?.stakeAddress ?? '';
      if (address != null && address.isNotEmpty) {
        final ok = await _walletService.connectExternalWallet('Smart Wallet (${user!.email})', address, stake);
        if (ok && mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _loadWalletData() async {
    if (!_walletService.isConnected) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final balance = await _walletService.getWalletBalance();
      final rows = await _walletService.getTokenHoldings();

      // Resolve display info once per unique unit
      final units = <String>{
        for (final r in rows)
          ((r['unit'] ?? r['unit_id'] ?? r['unit'])?.toString() ?? '').toLowerCase()
      }..removeWhere((e) => e.isEmpty);

      final Map<String, Map<String, dynamic>> infoByUnit = {};
      for (final u in units) {
        try {
          final info = await _assetCache.getDisplayInfoWithCache(u);
          infoByUnit[u] = info;
        } catch (_) {}
      }

      // Enrich and split
      final enriched = <Map<String, dynamic>>[];
      final tokensOnly = <Map<String, dynamic>>[];
      final nftsOnly = <Map<String, dynamic>>[];
      for (final r in rows) {
        final unit = ((r['unit'] ?? r['unit_id'] ?? r['unit'])?.toString() ?? '').toLowerCase();
        final info = infoByUnit[unit] ?? const {};
        final e = {...r, ...info};
        enriched.add(e);
        if (e['isNFT'] == true) {
          nftsOnly.add(e);
        } else {
          tokensOnly.add(e);
        }
      }

      // Sort for nicer UX
      tokensOnly.sort((a, b) => ((a['ticker'] ?? a['name'] ?? '') as String)
          .toLowerCase()
          .compareTo(((b['ticker'] ?? b['name'] ?? '') as String).toLowerCase()));
      nftsOnly.sort((a, b) => ((a['name'] ?? '') as String)
          .toLowerCase()
          .compareTo(((b['name'] ?? '') as String).toLowerCase()));

      setState(() {
        _walletBalance = balance;
        _tokenHoldings = enriched;
        _tokensOnly = tokensOnly;
        _nftsOnly = nftsOnly;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load wallet data: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.darkGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(
                child: _walletService.isConnected
                    ? _buildWalletContent()
                    : _buildNotConnectedState(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    debugPrint('🔍 DEBUG: WalletScreen header - local wallet name: ${_localWalletService.walletName}');
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.arrow_back,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'Wallet',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () async {
              await _ensureWalletConnectedFromUser();
              await _loadWalletData();
            },
            icon: Icon(
              Icons.refresh,
              color: AppColors.primaryBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotConnectedState() {
    return Center(
      child: GlassmorphismContainer(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_balance_wallet_outlined,
                size: 64,
                color: AppColors.primaryBlue,
              ),
              const SizedBox(height: 16),
              Text(
                'No Wallet Connected',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in with Google to connect your Smart Wallet',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () async {
                  await _ensureWalletConnectedFromUser();
                  await _loadWalletData();
                  if (!_walletService.isConnected && mounted) {
                    Navigator.of(context).pop(); // Open Smart Wallet dialog upstream
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Connect Smart Wallet'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWalletContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double tabHeight = (constraints.maxHeight * 0.45).clamp(320.0, 560.0);
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWalletInfo(),
                const SizedBox(height: 20),
                _buildBalanceCard(),
                const SizedBox(height: 20),
                _buildActionButtons(),
                const SizedBox(height: 20),
                _buildAssetsTabs(height: tabHeight),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAssetsTabs({double? height}) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TabBar(
            labelColor: AppColors.primaryBlue,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primaryBlue,
            tabs: const [
              Tab(text: 'Tokens'),
              Tab(text: 'NFTs'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: height ?? 420,
            child: TabBarView(
              children: [
                _buildTokensListScrollable(),
                _buildNftsListScrollable(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTokensListScrollable() {
    final tokens = _tokensOnly;
    return SingleChildScrollView(
      child: tokens.isEmpty
          ? _emptyAssets('No tokens found')
          : GlassmorphismContainer(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tokens', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ...tokens.map((t) => _buildTokenItem(t)),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildNftsListScrollable() {
    final nfts = _nftsOnly;
    return SingleChildScrollView(
      child: nfts.isEmpty
          ? _emptyAssets('No NFTs found')
          : GlassmorphismContainer(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NFTs', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    ...nfts.map((n) => _buildNftItemEnriched(n)),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildNftItemEnriched(Map<String, dynamic> item) {
    final unit = (item['unit'] ?? item['unit_id'] ?? '').toString();
    final policy = (item['policy_id'] ?? '').toString();
    final displayName = (item['name']?.toString() ?? _decodeHex((item['asset_name'] ?? '').toString()) ?? 'NFT');
    final imageUrl = (item['image'] as String?);
    return GestureDetector(
      onTap: () => _researchAsset(unit, displayName),
      onLongPress: () => _researchAsset(unit, displayName),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primaryBlue.withOpacity(0.25)),
              ),
              clipBehavior: Clip.antiAlias,
              child: (imageUrl != null && imageUrl.isNotEmpty)
                  ? Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.image, color: AppColors.primaryBlue, size: 24))
                  : const Icon(Icons.image, color: AppColors.primaryBlue, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'Policy: ${policy.isNotEmpty ? policy.substring(0, policy.length.clamp(0, 8)) : ''}...',
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Text(
              '#1',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  String? _decodeHex(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    try {
      final bytes = <int>[];
      for (int i = 0; i < hex.length; i += 2) {
        bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
      return String.fromCharCodes(bytes);
    } catch (_) {
      return null;
    }
  }

  Widget _emptyAssets(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text, style: TextStyle(color: AppColors.textSecondary)),
      ),
    );
  }

  Widget _buildWalletInfo() {
    return GlassmorphismContainer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  color: AppColors.primaryBlue,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  _localWalletService.walletName ?? 'Connected Wallet',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _showRenameDialog,
                  child: Icon(Icons.edit, size: 16, color: AppColors.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _walletService.currentAddress ?? '',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () async {
                    if (_walletService.currentAddress != null) {
                      await Clipboard.setData(
                        ClipboardData(text: _walletService.currentAddress!),
                      );
                      _showCopyConfirmation('Address copied!');
                    }
                  },
                  icon: Icon(
                    Icons.copy,
                    color: AppColors.primaryBlue,
                    size: 16,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog() {
    final controller = TextEditingController(text: _localWalletService.walletName ?? 'Generated Wallet');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.backgroundDark,
        title: const Text('Rename Wallet', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Enter wallet name',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: AppColors.primaryBlue)),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () {
                  final random = _localWalletService.generateRandomWalletName();
                  controller.text = random;
                },
                icon: const Icon(Icons.shuffle, color: AppColors.primaryBlue, size: 16),
                label: const Text('Random name', style: TextStyle(color: AppColors.primaryBlue)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = controller.text;
              await _localWalletService.renameWallet(newName);
              await _walletService.setWalletName(newName);
              debugPrint('🔍 DEBUG: Renamed wallet to "$newName". Local name: ${_localWalletService.walletName}, Cardano name: ${_walletService.walletName}');
              if (mounted) setState(() {});
              Navigator.pop(context);
              _showCopyConfirmation('Wallet name updated');
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue, foregroundColor: Colors.white),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard() {
    return GlassmorphismContainer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Balance',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            if (_isLoading)
              const CircularProgressIndicator()
            else if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: TextStyle(color: AppColors.error),
              )
            else if (_walletBalance != null) ...[
              Text(
                '${((double.tryParse(_walletBalance!['ada']?.toString() ?? '0') ?? 0.0) / 1000000).toStringAsFixed(2)} ADA',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_walletService.hasPremiumAccess) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.success.withOpacity(0.3)),
                  ),
                  child: Text(
                    'Premium Access',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ] else
              Text(
                '-- ADA',
                style: TextStyle(
                  color: AppColors.textTertiary,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        // Primary actions row
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                icon: Icons.call_received,
                label: 'Receive',
                onTap: _showReceiveDialog,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                icon: Icons.send,
                label: 'Send',
                onTap: _handleSendAction,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                icon: Icons.swap_horiz,
                label: 'Swap',
                onTap: _handleSwapAction,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Secondary actions row
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                icon: Icons.receipt_long,
                label: 'Txns',
                onTap: _openTransactions,
                color: AppColors.primaryBlue.withOpacity(0.8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                icon: Icons.contact_page,
                label: 'Address Book',
                onTap: _openAddressBook,
                color: AppColors.primaryBlue.withOpacity(0.8),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionButton(
                icon: Icons.security,
                label: 'Security',
                onTap: _openSecuritySettings,
                color: AppColors.primaryBlue.withOpacity(0.8),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Settings row
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                icon: Icons.settings,
                label: 'Settings',
                onTap: _openWalletSettings,
                color: AppColors.textSecondary.withOpacity(0.6),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(child: SizedBox()), // Empty space
            const SizedBox(width: 12),
            const Expanded(child: SizedBox()), // Empty space for symmetry
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: GlassmorphismContainer(
        child: Container(
          height: 100,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: color ?? AppColors.primaryBlue,
                size: 24,
              ),
              const SizedBox(height: 8),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTokensList() {
    return GlassmorphismContainer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tokens',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...(_tokenHoldings ?? []).map((token) => _buildTokenItem(token)),
          ],
        ),
      ),
    );
  }

  Widget _buildTokenItem(Map<String, dynamic> token) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _assetCache.getDisplayInfoWithCache(token['unit'] ?? token['unit_id'] ?? token['unit']),
      builder: (context, snap) {
        final display = snap.data;
        if (display?['isNFT'] == true) {
          return const SizedBox.shrink();
        }
        String name = (display?['name']?.toString() ?? token['asset_name']?.toString() ?? '').trim();
        if (name.isEmpty) {
          // Try to decode from unit hex
          final unit = (token['unit'] ?? token['unit_id'] ?? token['unit'])?.toString() ?? '';
          if (unit.length > 56) {
            final hex = unit.substring(56);
            name = _decodeHex(hex) ?? 'Unknown Token';
          } else {
            name = 'Unknown Token';
          }
        }
        final decimals = (display?['decimals'] as int?) ?? 0;
        final qtyStr = token['quantity']?.toString() ?? '0';
        String human = qtyStr;
        try {
          final v = BigInt.parse(qtyStr).toDouble();
          human = (v / (decimals == 0 ? 1 : (pow10(decimals)))).toStringAsFixed(decimals.clamp(0, 8));
        } catch (_) {}
        return GestureDetector(
          onTap: () => _researchAsset(token['unit'] ?? token['unit_id'] ?? token['unit'], name.toString()),
          onLongPress: () => _researchAsset(token['unit'] ?? token['unit_id'] ?? token['unit'], name.toString()),
          child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: (display?['image'] is String && (display!['image'] as String).isNotEmpty)
                ? Image.network(display!['image'], fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.token, color: AppColors.primaryBlue, size: 20))
                : Icon(Icons.token, color: AppColors.primaryBlue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.toString(),
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Policy: ${(display?['policy_id'] ?? token['policy_id'] ?? '')}'.substring(0, (display?['policy_id'] ?? token['policy_id'] ?? '').toString().length.clamp(0, 8)) + '...',
                  style: TextStyle(
                    color: AppColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            human,
            style: TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
        ));
      },
    );
  }

  void _showReceiveDialog() {
    final address = _walletService.currentAddress;
    if (address == null) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.backgroundDark,
        title: Text(
          'Receive Assets',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: QrImageView(
                data: address,
                version: QrVersions.auto,
                size: 200,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Scan QR code or copy address below:',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.backgroundLight.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primaryBlue.withOpacity(0.3)),
              ),
              child: SelectableText(
                address,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: address));
              _showCopyConfirmation('Address copied!');
            },
            child: Text(
              'Copy Address',
              style: TextStyle(color: AppColors.primaryBlue),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _handleSendAction() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SendScreen(walletService: _walletService),
      ),
    ).then((_) => _loadWalletData()); // Refresh wallet data when returning
  }

  void _handleSwapAction() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SwapScreen(walletService: _walletService),
      ),
    ).then((_) => _loadWalletData()); // Refresh wallet data when returning
  }

  void _showCopyConfirmation(String message) {
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
                  message,
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
    
    Future.delayed(const Duration(seconds: 2), () {
      overlayEntry.remove();
    });
  }

  /// Open wallet security settings
  void _openSecuritySettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const WalletSecuritySettings(),
      ),
    );
  }

  /// Open wallet general settings
  void _openWalletSettings() {
    // For now, show a simple dialog with wallet settings
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.backgroundDark,
        title: const Text(
          'Wallet Settings',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.backup, color: AppColors.primaryBlue),
              title: const Text(
                'Export Mnemonic',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: const Text(
                'Backup your wallet seed phrase',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _exportMnemonic();
              },
            ),
            ListTile(
              leading: const Icon(Icons.info, color: AppColors.primaryBlue),
              title: const Text(
                'Wallet Info',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: const Text(
                'View wallet details and debug info',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _walletService.debugWalletStorage();
                _showCopyConfirmation('Debug info printed to console');
              },
            ),
            const Divider(height: 24, color: Color(0x22FFFFFF)),
            ListTile(
              leading: Icon(Icons.link_off, color: _walletService.isConnected ? Colors.redAccent : AppColors.textSecondary.withOpacity(0.6)),
              title: Text(
                'Disconnect Wallet',
                style: TextStyle(color: _walletService.isConnected ? Colors.redAccent : AppColors.textSecondary),
              ),
              subtitle: Text(
                _walletService.isConnected ? 'Remove linked wallet from this account' : 'No wallet linked',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              enabled: _walletService.isConnected,
              onTap: () async {
                Navigator.pop(context);
                await _disconnectWalletFlow();
              },
            ),
            ListTile(
              leading: const Icon(Icons.download, color: AppColors.primaryBlue),
              title: const Text(
                'Import/Restore Wallet',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: const Text(
                'Use a mnemonic to restore a wallet',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _openManualWalletConnect();
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline, color: AppColors.primaryBlue),
              title: const Text(
                'Create New Wallet',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: const Text(
                'Generate a new wallet in-app',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              onTap: () async {
                Navigator.pop(context);
                await _openManualWalletConnect();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Close',
              style: TextStyle(color: AppColors.primaryBlue),
            ),
          ),
        ],
      ),
    );
  }

  /// Open transactions screen
  void _openTransactions() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const TransactionsScreen(),
      ),
    );
  }

  /// Open address book screen
  void _openAddressBook() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AddressBookScreen(),
      ),
    );
  }

  /// Export wallet mnemonic with security check
  Future<void> _exportMnemonic() async {
    try {
      final mnemonic = await _walletService.exportMnemonic();
      if (mnemonic == null) {
        _showCopyConfirmation('Failed to export mnemonic - authentication required');
        return;
      }

      // Show mnemonic in a secure dialog
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.backgroundDark,
          title: const Text(
            '🔐 Wallet Backup Phrase',
            style: TextStyle(color: AppColors.textPrimary),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '⚠️ KEEP THIS SAFE! Anyone with this phrase can access your wallet.',
                style: TextStyle(
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.glassBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: SelectableText(
                  mnemonic,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: mnemonic));
                Navigator.pop(context);
                _showCopyConfirmation('Mnemonic copied to clipboard');
              },
              child: const Text(
                'Copy',
                style: TextStyle(color: AppColors.primaryBlue),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Close',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      print('Error exporting mnemonic: $e');
      _showCopyConfirmation('Error exporting mnemonic');
    }
  }

  String? _coerceImageUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    var v = raw;
    // Some on-chain metadata stores as list ["ipfs://..."]
    if (v.startsWith('[')) {
      try {
        final arr = v.replaceAll('[', '').replaceAll(']', '').replaceAll('"', '').split(',');
        if (arr.isNotEmpty) v = arr.first.trim();
      } catch (_) {}
    }
    if (v.startsWith('ipfs://')) {
      return 'https://ipfs.io/ipfs/' + v.substring('ipfs://'.length);
    }
    if (v.startsWith('ar://')) {
      return 'https://arweave.net/' + v.substring('ar://'.length);
    }
    if (v.startsWith('http')) return v;
    return null;
  }

  double pow10(int n) => List.generate(n, (_) => 10).fold<double>(1, (a, b) => a * b);

  Future<void> _researchAsset(String unit, String displayName) async {
    try {
      // Loading modal
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.backgroundDark,
          title: Text('T Insights — $displayName', style: const TextStyle(color: AppColors.textPrimary)),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                SizedBox(height: 6),
                CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryBlue)),
                SizedBox(height: 12),
                Text('Fetching latest info…', style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      );

      final cacheKey = 'research:$unit';
      final cached = await _assetCache.getResearch(cacheKey);
      if (cached != null && mounted) {
        Navigator.of(context).pop();
        await _showInsightsDialog(displayName, cached['summary']?.toString() ?? '');
        return;
      }

      final app = AppConfig();
      final endpoint = app.tBackendUrl + '/chat';
      final url = Uri.parse(endpoint);
      final headers = {'Content-Type': 'application/json'};
      final body = jsonEncode({
        'message': 'Give a brief overview (max 6 lines) about Cardano asset "$displayName" with unit "$unit". Include what it is, notable utility, and any relevant resources. Use bullet points.',
        'session_id': 'wallet_insights',
        'context': {'asset_unit': unit, 'asset_name': displayName},
      });
      final resp = await http.post(url, headers: headers, body: body);
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final reply = data['reply']?.toString() ?? 'No info available.';
        await _assetCache.cacheResearch(cacheKey, {'summary': reply});
        if (!mounted) return;
        Navigator.of(context).pop();
        await _showInsightsDialog(displayName, reply);
      } else {
        if (!mounted) return;
        Navigator.of(context).pop();
        _showCopyConfirmation('Unable to fetch insights (${resp.statusCode})');
      }
    } catch (_) {
      if (mounted) Navigator.of(context).maybePop();
    }
  }

  Future<void> _showInsightsDialog(String title, String content) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundDark,
        title: Text('T Insights — $title', style: const TextStyle(color: AppColors.textPrimary)),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Text(
              content,
              style: const TextStyle(color: AppColors.textPrimary),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: content));
              Navigator.of(ctx).pop();
              _showCopyConfirmation('Insights copied');
            },
            child: const Text('Copy', style: TextStyle(color: AppColors.primaryBlue)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close', style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  Future<void> _disconnectWalletFlow() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundDark,
        title: const Text(
          'Disconnect Wallet',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: const Text(
          'Are you sure you want to disconnect your linked wallet? You can import or create a new one afterwards.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Disconnect', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await widget.authService.disconnectCardanoWallet();
        if (mounted) {
          setState(() {});
          _showCopyConfirmation('Wallet disconnected');
          await _loadWalletData();
        }
      } catch (e) {
        _showCopyConfirmation('Failed to disconnect wallet');
      }
    }
  }

  Future<void> _openManualWalletConnect() async {
    // If already connected, confirm replacement
    if (_walletService.isConnected) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.backgroundDark,
          title: const Text('Replace Wallet', style: TextStyle(color: AppColors.textPrimary)),
          content: const Text(
            'Importing or creating a new wallet will replace your current linked wallet. Continue?',
            style: TextStyle(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Replace', style: TextStyle(color: AppColors.primaryBlue)),
            ),
          ],
        ),
      );
      if (replace != true) return;
      await widget.authService.disconnectCardanoWallet();
    }

    final connected = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => CardanoWalletDialog(
        authService: widget.authService,
        manualOnly: true,
      ),
    );

    if (connected == true) {
      await _ensureWalletConnectedFromUser();
      await _loadWalletData();
      if (mounted) _showCopyConfirmation('Wallet connected');
    }
  }
} 