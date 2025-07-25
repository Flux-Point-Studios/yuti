import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/transaction_history_service.dart';
import '../utils/app_colors.dart';
import '../widgets/glassmorphism_container.dart';
import '../models/transaction.dart';

class TransactionsScreen extends StatefulWidget {
  const TransactionsScreen({Key? key}) : super(key: key);

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _transactionHistoryService = TransactionHistoryService();
  
  List<Transaction> _transactions = [];
  List<Transaction> _filteredTransactions = [];
  String _selectedFilter = 'All';
  String _selectedAsset = 'All';
  bool _isLoading = true;

  final List<String> _filterOptions = ['All', 'Send', 'Receive', 'Swap'];
  final List<String> _assetOptions = ['All', 'ADA'];

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() {
      _isLoading = true;
    });

    await _transactionHistoryService.initialize();
    
    setState(() {
      _transactions = _transactionHistoryService.transactions;
      _filteredTransactions = _transactions;
      _isLoading = false;
      
      // Build asset options from actual transactions
      final assets = <String>{'All', 'ADA'};
      for (final tx in _transactions) {
        if (tx.asset != 'ADA') {
          assets.add(tx.asset);
        }
      }
      _assetOptions.clear();
      _assetOptions.addAll(assets.toList()..sort());
    });
    
    _applyFilters();
  }

  void _applyFilters() {
    setState(() {
      _filteredTransactions = _transactions.where((tx) {
        // Type filter
        bool typeMatch = _selectedFilter == 'All' || 
                        (_selectedFilter == 'Send' && tx.type == 'send') ||
                        (_selectedFilter == 'Receive' && tx.type == 'receive') ||
                        (_selectedFilter == 'Swap' && tx.type == 'swap');
        
        // Asset filter
        bool assetMatch = _selectedAsset == 'All' || tx.asset == _selectedAsset;
        
        return typeMatch && assetMatch;
      }).toList();
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
              _buildFilters(),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _buildTransactionsList(),
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
            'Transactions',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: _loadTransactions,
            icon: Icon(
              Icons.refresh,
              color: AppColors.primaryBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: _buildFilterDropdown(
              label: 'Type',
              value: _selectedFilter,
              options: _filterOptions,
              onChanged: (value) {
                setState(() {
                  _selectedFilter = value!;
                });
                _applyFilters();
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: _buildFilterDropdown(
              label: 'Asset',
              value: _selectedAsset,
              options: _assetOptions,
              onChanged: (value) {
                setState(() {
                  _selectedAsset = value!;
                });
                _applyFilters();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.backgroundLight.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primaryBlue.withOpacity(0.3)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: AppColors.backgroundDark,
              style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              items: options.map((option) => DropdownMenuItem(
                value: option,
                child: Text(option),
              )).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionsList() {
    if (_filteredTransactions.isEmpty) {
      return _buildEmptyState();
    }

    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: _filteredTransactions.length,
      itemBuilder: (context, index) {
        final transaction = _filteredTransactions[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildTransactionItem(transaction),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: GlassmorphismContainer(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.receipt_long_outlined,
                size: 64,
                color: AppColors.textTertiary,
              ),
              const SizedBox(height: 16),
              Text(
                'No Transactions',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _selectedFilter != 'All' || _selectedAsset != 'All'
                    ? 'No transactions match your filters'
                    : 'Your transaction history will appear here',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionItem(Transaction transaction) {
    return GestureDetector(
      onTap: () => _showTransactionDetails(transaction),
      child: GlassmorphismContainer(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _buildTransactionIcon(transaction),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _getTransactionTitle(transaction),
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${transaction.isOutgoing ? '-' : '+'}${transaction.amount.toStringAsFixed(transaction.asset == 'ADA' ? 2 : 0)} ${transaction.asset}',
                          style: TextStyle(
                            color: transaction.isOutgoing ? AppColors.error : AppColors.success,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          _formatDate(transaction.timestamp),
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const Spacer(),
                        _buildStatusChip(transaction),
                      ],
                    ),
                    if (transaction.description != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        transaction.description!,
                        style: TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionIcon(Transaction transaction) {
    IconData icon;
    Color color;
    
    switch (transaction.type) {
      case 'send':
        icon = Icons.arrow_upward;
        color = AppColors.error;
        break;
      case 'receive':
        icon = Icons.arrow_downward;
        color = AppColors.success;
        break;
      case 'swap':
        icon = Icons.swap_horiz;
        color = AppColors.primaryBlue;
        break;
      default:
        icon = Icons.receipt;
        color = AppColors.textSecondary;
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Icon(
        icon,
        color: color,
        size: 24,
      ),
    );
  }

  Widget _buildStatusChip(Transaction transaction) {
    Color color;
    String text;
    
    if (transaction.isPending) {
      color = Colors.orange;
      text = 'Pending';
    } else if (transaction.isConfirmed) {
      color = AppColors.success;
      text = 'Confirmed';
    } else {
      color = AppColors.error;
      text = 'Failed';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _getTransactionTitle(Transaction transaction) {
    switch (transaction.type) {
      case 'send':
        return 'Sent ${transaction.asset}';
      case 'receive':
        return 'Received ${transaction.asset}';
      case 'swap':
        return 'Swapped Assets';
      default:
        return 'Transaction';
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final transactionDate = DateTime(date.year, date.month, date.day);

    if (transactionDate == today) {
      return 'Today ${_formatTime(date)}';
    } else if (transactionDate == yesterday) {
      return 'Yesterday ${_formatTime(date)}';
    } else {
      return '${date.day}/${date.month}/${date.year} ${_formatTime(date)}';
    }
  }

  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void _showTransactionDetails(Transaction transaction) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.backgroundDark,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.9,
          minChildSize: 0.5,
          builder: (context, scrollController) => SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textTertiary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                
                // Title
                Text(
                  'Transaction Details',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                
                // Transaction info
                _buildDetailItem('Type', _getTransactionTitle(transaction)),
                _buildDetailItem('Amount', '${transaction.isOutgoing ? '-' : '+'}${transaction.amount.toStringAsFixed(transaction.asset == 'ADA' ? 2 : 0)} ${transaction.asset}'),
                _buildDetailItem('Fee', '${transaction.fee.toStringAsFixed(2)} ADA'),
                _buildDetailItem('Status', transaction.status.toUpperCase()),
                _buildDetailItem('Date', _formatDate(transaction.timestamp)),
                
                if (transaction.fromAddress != null)
                  _buildDetailItem('From', transaction.fromAddress!, isAddress: true),
                
                if (transaction.toAddress != null)
                  _buildDetailItem('To', transaction.toAddress!, isAddress: true),
                
                if (transaction.txHash != null)
                  _buildDetailItem('Transaction Hash', transaction.txHash!, isAddress: true),
                
                if (transaction.description != null)
                  _buildDetailItem('Description', transaction.description!),
                
                if (transaction.tokenPolicyId != null)
                  _buildDetailItem('Token Policy ID', transaction.tokenPolicyId!, isAddress: true),
                
                const SizedBox(height: 20),
                
                // Close button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, {bool isAddress = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: isAddress ? () => _copyToClipboard(value) : null,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.backgroundLight.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primaryBlue.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontFamily: isAddress ? 'monospace' : null,
                      ),
                    ),
                  ),
                  if (isAddress) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.copy,
                      color: AppColors.primaryBlue,
                      size: 16,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Copied to clipboard'),
        backgroundColor: AppColors.primaryBlue,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}