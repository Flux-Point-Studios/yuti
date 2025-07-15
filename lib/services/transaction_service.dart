import 'wallet_service.dart';
import 'blockfrost_service.dart';

class TransactionService {
  final WalletService _walletService;
  final BlockfrostService _blockfrostService;
  
  TransactionService(this._walletService, this._blockfrostService);
  
  // Build a simple payment transaction (demo version)
  Future<Map<String, dynamic>> buildPaymentTransaction({
    required String toAddress,
    required double adaAmount,
  }) async {
    try {
      // For demo purposes, return a mock transaction object
      final fromAddress = await _walletService.getReceiveAddress();
      
      return {
        'from': fromAddress,
        'to': toAddress,
        'amount': adaAmount,
        'fee': 0.17, // Average transaction fee
        'status': 'pending',
        'timestamp': DateTime.now().toIso8601String(),
        'txHash': _generateMockTxHash(),
      };
    } catch (e) {
      throw Exception('Failed to build transaction: $e');
    }
  }
  
  // Estimate transaction fee
  Future<double> estimateFee({
    required String toAddress,
    required double adaAmount,
  }) async {
    // Simple fee estimation
    return 0.17; // Average Cardano transaction fee
  }
  
  // Submit transaction (demo version)
  Future<String> submitTransaction(Map<String, dynamic> transaction) async {
    // For demo, just return the mock tx hash
    return transaction['txHash'] ?? _generateMockTxHash();
  }
  
  String _generateMockTxHash() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'tx_demo_$timestamp';
  }
} 