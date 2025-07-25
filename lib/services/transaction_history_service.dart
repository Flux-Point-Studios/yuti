import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/transaction.dart';

class TransactionHistoryService {
  static const _storage = FlutterSecureStorage();
  static const String _transactionsKey = 'wallet_transactions';

  // Singleton pattern
  static final TransactionHistoryService _instance = TransactionHistoryService._internal();
  factory TransactionHistoryService() => _instance;
  TransactionHistoryService._internal();

  List<Transaction> _transactions = [];
  
  List<Transaction> get transactions => List.unmodifiable(_transactions);

  /// Initialize and load existing transactions
  Future<void> initialize() async {
    await loadTransactions();
  }

  /// Load transactions from storage
  Future<void> loadTransactions() async {
    try {
      final transactionsJson = await _storage.read(key: _transactionsKey);
      if (transactionsJson != null) {
        final List<dynamic> transactionsList = json.decode(transactionsJson);
        _transactions = transactionsList
            .map((json) => Transaction.fromJson(json))
            .toList();
        
        // Sort by timestamp (newest first)
        _transactions.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      }
    } catch (e) {
      print('Error loading transactions: $e');
      _transactions = [];
    }
  }

  /// Save transactions to storage
  Future<void> _saveTransactions() async {
    try {
      final transactionsJson = json.encode(
        _transactions.map((tx) => tx.toJson()).toList(),
      );
      await _storage.write(key: _transactionsKey, value: transactionsJson);
    } catch (e) {
      print('Error saving transactions: $e');
    }
  }

  /// Add a new transaction
  Future<void> addTransaction(Transaction transaction) async {
    _transactions.insert(0, transaction); // Add to beginning (newest first)
    await _saveTransactions();
  }

  /// Update transaction status
  Future<void> updateTransactionStatus(String id, String status, {String? txHash}) async {
    final index = _transactions.indexWhere((tx) => tx.id == id);
    if (index != -1) {
      final transaction = _transactions[index];
      _transactions[index] = Transaction(
        id: transaction.id,
        type: transaction.type,
        fromAddress: transaction.fromAddress,
        toAddress: transaction.toAddress,
        amount: transaction.amount,
        asset: transaction.asset,
        tokenPolicyId: transaction.tokenPolicyId,
        fee: transaction.fee,
        status: status,
        timestamp: transaction.timestamp,
        txHash: txHash ?? transaction.txHash,
        description: transaction.description,
      );
      await _saveTransactions();
    }
  }

  /// Get transactions by type
  List<Transaction> getTransactionsByType(String type) {
    return _transactions.where((tx) => tx.type == type).toList();
  }

  /// Get pending transactions
  List<Transaction> getPendingTransactions() {
    return _transactions.where((tx) => tx.isPending).toList();
  }

  /// Get transactions for a specific asset
  List<Transaction> getTransactionsByAsset(String asset) {
    return _transactions.where((tx) => tx.asset == asset).toList();
  }

  /// Clear all transactions
  Future<void> clearTransactions() async {
    _transactions.clear();
    await _saveTransactions();
  }

  /// Get transaction by ID
  Transaction? getTransactionById(String id) {
    try {
      return _transactions.firstWhere((tx) => tx.id == id);
    } catch (e) {
      return null;
    }
  }
}