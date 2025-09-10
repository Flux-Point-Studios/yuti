import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/cardano_wallet_service.dart';
import '../services/transaction_history_service.dart';
import '../services/address_book_service.dart';
import '../utils/app_colors.dart';
import '../widgets/glassmorphism_container.dart';
import '../models/transaction.dart';
import '../models/address_book_entry.dart';
import 'address_book_screen.dart';
import 'qr_scanner_screen.dart';
import '../services/gamification_service.dart';
import '../services/smart_wallet_service.dart';
import '../services/auth_service.dart';

class SendScreen extends StatefulWidget {
  final CardanoWalletService walletService;

  const SendScreen({
    Key? key,
    required this.walletService,
  }) : super(key: key);

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _addressController = TextEditingController();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _addressBookService = AddressBookService();
  final _transactionHistoryService = TransactionHistoryService();

  String _selectedAsset = 'ADA';
  List<Map<String, dynamic>> _availableTokens = [];
  double _estimatedFee = 0.17;
  bool _isLoading = false;
  String? _errorMessage;
  double _maxAmount = 0.0;

  @override
  void initState() {
    super.initState();
    _loadAvailableAssets();
    _addressController.addListener(_onAddressChanged);
  }

  @override
  void dispose() {
    _addressController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableAssets() async {
    try {
      final balance = await widget.walletService.getWalletBalance();
      final tokens = await widget.walletService.getTokenHoldings();
      
      setState(() {
        _maxAmount = (double.tryParse(balance?['ada']?.toString() ?? '0') ?? 0.0) / 1000000;
        _availableTokens = tokens ?? [];
      });
    } catch (e) {
      print('Error loading assets: $e');
    }
  }

  void _onAddressChanged() {
    // Check if address exists in address book and auto-fill name
    final entry = _addressBookService.getEntryByAddress(_addressController.text.trim());
    if (entry != null) {
      _descriptionController.text = 'Sent to ${entry.name}';
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAssetSelector(),
                      const SizedBox(height: 20),
                      _buildRecipientSection(),
                      const SizedBox(height: 20),
                      _buildAmountSection(),
                      const SizedBox(height: 20),
                      _buildDescriptionSection(),
                      const SizedBox(height: 20),
                      _buildFeeSection(),
                      const SizedBox(height: 30),
                      _buildSendButton(),
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
            'Send Assets',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetSelector() {
    return GlassmorphismContainer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select Asset',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedAsset,
              decoration: InputDecoration(
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
              dropdownColor: AppColors.backgroundDark,
              style: TextStyle(color: AppColors.textPrimary),
              items: [
                DropdownMenuItem(
                  value: 'ADA',
                  child: Row(
                    children: [
                      Icon(Icons.account_balance_wallet, color: AppColors.primaryBlue, size: 20),
                      const SizedBox(width: 8),
                      Text('ADA'),
                      const Spacer(),
                      Text(
                        'Balance: ${_maxAmount.toStringAsFixed(2)}',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                ..._availableTokens.map((token) => DropdownMenuItem(
                  value: token['asset_name'],
                  child: Row(
                    children: [
                      Icon(Icons.token, color: AppColors.primaryBlue, size: 20),
                      const SizedBox(width: 8),
                      Text(token['asset_name'] ?? 'Unknown'),
                      const Spacer(),
                      Text(
                        'Balance: ${token['quantity']}',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                )),
              ],
              onChanged: (value) async {
                setState(() {
                  _selectedAsset = value!;
                });
                
                if (_selectedAsset == 'ADA') {
                  try {
                    final balance = await widget.walletService.getWalletBalance();
                    final adaBalance = (double.tryParse(balance['ada']?.toString() ?? '0') ?? 0.0) / 1000000;
                    setState(() {
                      _maxAmount = adaBalance;
                    });
                  } catch (e) {
                    setState(() {
                      _maxAmount = 0.0;
                    });
                  }
                } else {
                  final token = _availableTokens.firstWhere((t) => t['asset_name'] == _selectedAsset);
                  setState(() {
                    _maxAmount = double.tryParse(token['quantity']?.toString() ?? '0') ?? 0.0;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecipientSection() {
    return GlassmorphismContainer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Recipient Address',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _showAddressBook,
                  icon: Icon(Icons.contact_page, color: AppColors.primaryBlue, size: 16),
                  label: Text(
                    'Address Book',
                    style: TextStyle(color: AppColors.primaryBlue, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressController,
              decoration: InputDecoration(
                hintText: 'addr1... or gmail address',
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
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: _pasteFromClipboard,
                      icon: Icon(Icons.paste, color: AppColors.primaryBlue),
                    ),
                    IconButton(
                      onPressed: _scanQRCode,
                      icon: Icon(Icons.qr_code_scanner, color: AppColors.primaryBlue),
                    ),
                  ],
                ),
              ),
              style: TextStyle(color: AppColors.textPrimary, fontSize: 12),
              maxLines: 3,
            ),
            const SizedBox(height: 6),
            Text(
              'Tip: Enter a Gmail to send to a Smart Wallet user',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountSection() {
    return GlassmorphismContainer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Amount',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _setMaxAmount,
                  child: Text(
                    'MAX',
                    style: TextStyle(color: AppColors.primaryBlue, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountController,
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
                suffixText: _selectedAsset,
                suffixStyle: TextStyle(color: AppColors.textSecondary),
              ),
              style: TextStyle(color: AppColors.textPrimary),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
            ),
            const SizedBox(height: 8),
            Text(
              'Available: ${_maxAmount.toStringAsFixed(_selectedAsset == 'ADA' ? 2 : 0)} $_selectedAsset',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDescriptionSection() {
    return GlassmorphismContainer(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Description (Optional)',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                hintText: 'Payment for...',
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
              style: TextStyle(color: AppColors.textPrimary),
              maxLines: 2,
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
                    'Transaction Fee',
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

  Widget _buildSendButton() {
    final isValid = _isFormValid();
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isValid && !_isLoading ? _sendTransaction : null,
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
                'Send $_selectedAsset',
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
    final address = _addressController.text.trim();
    final amount = double.tryParse(_amountController.text);
    
    return address.isNotEmpty &&
           _addressBookService.isValidCardanoAddress(address) &&
           amount != null &&
           amount > 0 &&
           amount <= _maxAmount;
  }

  void _setMaxAmount() {
    double maxSendable = _maxAmount;
    if (_selectedAsset == 'ADA') {
      // Subtract fee for ADA transactions
      maxSendable = _maxAmount - _estimatedFee;
      if (maxSendable < 0) maxSendable = 0;
    }
    _amountController.text = maxSendable.toStringAsFixed(_selectedAsset == 'ADA' ? 2 : 0);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) {
      _addressController.text = data!.text!;
    }
  }

  void _scanQRCode() {
    // Navigate to QR scanner with proper navigation
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const QRScannerScreen(
          title: 'Scan Recipient Address',
          hint: 'Scan the QR code of the recipient\'s wallet address',
        ),
      ),
    ).then((result) {
      if (result != null && result is String) {
        _addressController.text = result;
      }
    });
  }

  void _showAddressBook() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddressBookScreen(
          isSelectionMode: true,
          onAddressSelected: (entry) {
            _addressController.text = entry.address;
            _descriptionController.text = 'Sent to ${entry.name}';
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  Future<void> _sendTransaction() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      String address = _addressController.text.trim();
      // Resolve ADA Handle if entered
      if (!AddressBookService().isValidCardanoAddress(address)) {
        try {
          final res = await AddressBookService().resolveIfHandle(address);
          address = res['address'] ?? address;
        } catch (_) {}
      }
      // Resolve Smart Wallet email to address
      if (!AddressBookService().isValidCardanoAddress(address) && address.contains('@')) {
        try {
          final smartAddr = await _resolveSmartWalletAddress(address);
          if (smartAddr != null) {
            address = smartAddr;
          }
        } catch (_) {}
      }
      final amount = double.parse(_amountController.text);
      final description = _descriptionController.text.trim();

      // Real Smart Wallet submit flow
      final auth = AuthService();
      final user = auth.currentUser;
      if (user == null) throw Exception('Not signed in');

      final smart = SmartWalletService();
      final email = user.email;
      final paymentKeyHash = smart.derivePaymentKeyHashHex(email);

      // Value map: lovelace or multiasset (basic ADA only here)
      final value = <String, int>{
        'lovelace': (amount * 1000000).round(),
      };

      debugPrint('🔍 DEBUG: Building Smart Wallet tx to $address with $amount ADA');
      final built = await smart.buildSendFunds(
        email: email,
        paymentKeyHashHex: paymentKeyHash,
        recipientAddress: address,
        valueMap: value,
      );

      debugPrint('🔍 DEBUG: Built txId=${built.txId}, fee=${built.txFee}');
      final submitted = await smart.submitTransaction(txCborHex: built.txCborHex, notifyEmails: [email]);
      debugPrint('🔍 DEBUG: Submitted txId=${submitted.txId}');

      // Create transaction record for UI/history
      final transaction = Transaction(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: 'send',
        fromAddress: widget.walletService.currentAddress,
        toAddress: address,
        amount: amount,
        asset: _selectedAsset,
        tokenPolicyId: null,
        fee: double.tryParse(built.txFee) ?? _estimatedFee,
        status: 'confirmed',
        timestamp: DateTime.now(),
        description: description.isNotEmpty ? description : null,
        txHash: submitted.txId,
      );

      await _transactionHistoryService.addTransaction(transaction);
      await _addressBookService.updateLastUsed(address);

      _showSuccessDialog();
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to send transaction: $e';
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
              'Transaction Sent',
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ],
        ),
        content: Text(
          'Your transaction has been submitted successfully.',
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

  Future<String?> _resolveSmartWalletAddress(String email) async {
    try {
      final svc = SmartWalletService();
      return await svc.getWalletAddressByEmail(email);
    } catch (_) {
      return null;
    }
  }
}