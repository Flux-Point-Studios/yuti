import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/cardano_wallet_service.dart';
import '../services/transaction_history_service.dart';
import '../utils/app_colors.dart';
import '../widgets/glassmorphism_container.dart';
import '../models/transaction.dart';

class SwapScreen extends StatefulWidget {
  final CardanoWalletService walletService;

  const SwapScreen({
    Key? key,
    required this.walletService,
  }) : super(key: key);

  @override
  State<SwapScreen> createState() => _SwapScreenState();
}

class _SwapScreenState extends State<SwapScreen> {
  final _fromAmountController = TextEditingController();
  final _transactionHistoryService = TransactionHistoryService();

  String _fromAsset = 'ADA';
  String _toAsset = 'USDC';
  List<Map<String, dynamic>> _availableTokens = [];
  double _estimatedFee = 0.5;
  double _exchangeRate = 0.45; // Example rate: 1 ADA = 0.45 USDC
  bool _isLoading = false;
  String? _errorMessage;
  double _maxFromAmount = 0.0;
  double _estimatedToAmount = 0.0;

  final List<String> _popularTokens = ['ADA', 'USDC', 'USDT', 'DJED', 'SHEN'];

  @override
  void initState() {
    super.initState();
    _loadAvailableAssets();
    _fromAmountController.addListener(_calculateToAmount);
  }

  @override
  void dispose() {
    _fromAmountController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableAssets() async {
    try {
      final balance = await widget.walletService.getWalletBalance();
      final tokens = await widget.walletService.getTokenHoldings();
      
      setState(() {
        _maxFromAmount = (double.tryParse(balance?['ada']?.toString() ?? '0') ?? 0.0) / 1000000;
        _availableTokens = tokens ?? [];
      });
    } catch (e) {
      print('Error loading assets: $e');
    }
  }

  void _calculateToAmount() {
    final fromAmount = double.tryParse(_fromAmountController.text) ?? 0.0;
    setState(() {
      _estimatedToAmount = fromAmount * _exchangeRate;
    });
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFromSection(),
                      const SizedBox(height: 16),
                      _buildSwapButton(),
                      const SizedBox(height: 16),
                      _buildToSection(),
                      const SizedBox(height: 20),
                      _buildExchangeInfo(),
                      const SizedBox(height: 20),
                      _buildFeeSection(),
                      const SizedBox(height: 30),
                      _buildSwapActionButton(),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        _buildErrorMessage(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
            'Swap Assets',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _refreshRates,
            icon: Icon(
              Icons.refresh,
              color: AppColors.primaryBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFromSection() {
    return GlassmorphismContainer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'From',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _setMaxFromAmount,
                  child: Text(
                    'MAX',
                    style: TextStyle(color: AppColors.primaryBlue, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _fromAmountController,
                    decoration: InputDecoration(
                      hintText: '0.00',
                      hintStyle: TextStyle(color: AppColors.textTertiary),
                      filled: true,
                      fillColor: AppColors.backgroundLight.withOpacity(0.1),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.primaryBlue.withOpacity(0.3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.primaryBlue.withOpacity(0.3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.primaryBlue),
                      ),
                    ),
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 18),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildAssetSelector(_fromAsset, true),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Available: ${_getAvailableBalance(_fromAsset).toStringAsFixed(_fromAsset == 'ADA' ? 2 : 0)} $_fromAsset',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToSection() {
    return GlassmorphismContainer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'To (estimated)',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundLight.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primaryBlue.withOpacity(0.3)),
                    ),
                    child: Text(
                      _estimatedToAmount.toStringAsFixed(_toAsset == 'ADA' ? 2 : 6),
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildAssetSelector(_toAsset, false),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwapButton() {
    return Center(
      child: GestureDetector(
        onTap: _swapAssets,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primaryBlue,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primaryBlue.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.swap_vert,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }

  Widget _buildAssetSelector(String selectedAsset, bool isFrom) {
    return GestureDetector(
      onTap: () => _showAssetSelector(isFrom),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.backgroundLight.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primaryBlue.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primaryBlue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                selectedAsset,
                style: TextStyle(
                  color: AppColors.primaryBlue,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                selectedAsset,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExchangeInfo() {
    return GlassmorphismContainer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  'Exchange Rate',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Text(
                  '1 $_fromAsset = ${_exchangeRate.toStringAsFixed(6)} $_toAsset',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Minimum Received',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Text(
                  '${(_estimatedToAmount * 0.98).toStringAsFixed(_toAsset == 'ADA' ? 2 : 6)} $_toAsset',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Price Impact',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Text(
                  '< 0.1%',
                  style: TextStyle(
                    color: AppColors.success,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeeSection() {
    return GlassmorphismContainer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: AppColors.primaryBlue, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Network Fee',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '~${_estimatedFee.toStringAsFixed(2)} ADA',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwapActionButton() {
    final isValid = _isFormValid();
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isValid && !_isLoading ? _executeSwap : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: isValid ? AppColors.primaryBlue : AppColors.textTertiary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: _isLoading
            ? const CircularProgressIndicator(color: Colors.white)
            : Text(
                'Swap $_fromAsset to $_toAsset',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: AppColors.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  bool _isFormValid() {
    final amount = double.tryParse(_fromAmountController.text);
    return amount != null &&
           amount > 0 &&
           amount <= _getAvailableBalance(_fromAsset) &&
           _fromAsset != _toAsset;
  }

  double _getAvailableBalance(String asset) {
    if (asset == 'ADA') {
      return _maxFromAmount;
    } else {
      final token = _availableTokens.firstWhere(
        (t) => t['asset_name'] == asset,
        orElse: () => {'quantity': '0'},
      );
      return double.tryParse(token['quantity']?.toString() ?? '0') ?? 0.0;
    }
  }

  void _setMaxFromAmount() {
    double maxAmount = _getAvailableBalance(_fromAsset);
    if (_fromAsset == 'ADA') {
      // Reserve some ADA for fees
      maxAmount = maxAmount - _estimatedFee;
      if (maxAmount < 0) maxAmount = 0;
    }
    _fromAmountController.text = maxAmount.toStringAsFixed(_fromAsset == 'ADA' ? 2 : 0);
  }

  void _swapAssets() {
    setState(() {
      final temp = _fromAsset;
      _fromAsset = _toAsset;
      _toAsset = temp;
      
      // Update exchange rate (simplified)
      _exchangeRate = 1 / _exchangeRate;
      _fromAmountController.clear();
      _estimatedToAmount = 0.0;
    });
  }

  void _refreshRates() {
    // Simulate rate refresh
    setState(() {
      _exchangeRate = _exchangeRate * (0.95 + (0.1 * (DateTime.now().millisecond / 1000)));
    });
    _calculateToAmount();
  }

  void _showAssetSelector(bool isFrom) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.backgroundDark,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Select Asset',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ..._popularTokens.map((asset) => ListTile(
              leading: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  asset,
                  style: TextStyle(
                    color: AppColors.primaryBlue,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                asset,
                style: TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: Text(
                'Balance: ${_getAvailableBalance(asset).toStringAsFixed(asset == 'ADA' ? 2 : 0)}',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              onTap: () {
                setState(() {
                  if (isFrom) {
                    _fromAsset = asset;
                  } else {
                    _toAsset = asset;
                  }
                });
                Navigator.pop(context);
                _calculateToAmount();
              },
            )),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _executeSwap() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final amount = double.parse(_fromAmountController.text);

      // Create transaction record
      final transaction = Transaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: 'swap',
        fromAddress: widget.walletService.currentAddress,
        toAddress: widget.walletService.currentAddress,
        amount: amount,
        asset: '$_fromAsset → $_toAsset',
        fee: _estimatedFee,
        status: 'pending',
        timestamp: DateTime.now(),
        description: 'Swapped ${amount.toStringAsFixed(_fromAsset == 'ADA' ? 2 : 0)} $_fromAsset to ${_estimatedToAmount.toStringAsFixed(_toAsset == 'ADA' ? 2 : 6)} $_toAsset',
      );

      // Add to transaction history
      await _transactionHistoryService.addTransaction(transaction);

      // Simulate swap execution
      await Future.delayed(const Duration(seconds: 3));

      // Update transaction status
      await _transactionHistoryService.updateTransactionStatus(
        transaction.id,
        'confirmed',
        txHash: 'swap_tx_${DateTime.now().millisecondsSinceEpoch}',
      );

      // Show success and navigate back
      _showSuccessDialog();
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to execute swap: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.backgroundDark,
        title: Row(
          children: [
            Icon(Icons.check_circle, color: AppColors.success),
            const SizedBox(width: 8),
            Text(
              'Swap Executed',
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ],
        ),
        content: Text(
          'Your swap has been submitted successfully.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Go back to wallet
            },
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
}