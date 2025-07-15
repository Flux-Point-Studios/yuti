import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'wallet_service.dart';
import 'blockfrost_service.dart';

// Transaction builder that follows the research document's approach
class TransactionBuilder {
  final WalletService _walletService;
  final BlockfrostService _blockfrostService;
  final AppConfig _config = AppConfig();
  
  // Cardano protocol parameters (mainnet values)
  static const int MIN_FEE_A = 44; // Linear fee coefficient A
  static const int MIN_FEE_B = 155381; // Linear fee coefficient B
  static const int MIN_UTXO_VALUE = 1000000; // 1 ADA minimum UTXO
  
  TransactionBuilder(this._walletService, this._blockfrostService);
  
  // Build a payment transaction following research guidance
  Future<Map<String, dynamic>> buildPaymentTransaction({
    required String toAddress,
    required BigInt amountLovelace,
  }) async {
    try {
      // Step 1: Get sender address
      final fromAddress = await _walletService.getReceiveAddress();
      
      // Step 2: Fetch UTXOs for the sender address
      final utxos = await _blockfrostService.getUtxos(fromAddress);
      if (utxos.isEmpty) {
        throw Exception('No UTXOs available');
      }
      
      // Step 3: Select UTXOs (simple largest-first selection)
      final selectedUtxos = _selectUtxos(utxos, amountLovelace);
      
      // Step 4: Calculate total input value
      BigInt totalInput = BigInt.zero;
      for (var utxo in selectedUtxos) {
        totalInput += _getUtxoValue(utxo);
      }
      
      // Step 5: Estimate transaction fee
      final estimatedFee = _estimateFee(selectedUtxos.length, 2); // 2 outputs (payment + change)
      
      // Step 6: Calculate change
      final change = totalInput - amountLovelace - estimatedFee;
      if (change < BigInt.zero) {
        throw Exception('Insufficient funds (need ${amountLovelace + estimatedFee} lovelace, have $totalInput)');
      }
      
      // Step 7: Build transaction structure
      final transaction = {
        'inputs': selectedUtxos.map((utxo) => {
          'tx_hash': utxo['tx_hash'],
          'output_index': utxo['output_index'] ?? utxo['tx_index'],
          'amount': _getUtxoValue(utxo).toString(),
        }).toList(),
        'outputs': [
          {
            'address': toAddress,
            'amount': amountLovelace.toString(),
          },
        ],
        'fee': estimatedFee.toString(),
        'metadata': null,
      };
      
      // Add change output if needed
      if (change > BigInt.from(MIN_UTXO_VALUE)) {
        (transaction['outputs'] as List).add({
          'address': fromAddress, // Send change back to sender
          'amount': change.toString(),
        });
      } else if (change > BigInt.zero) {
        // If change is dust, add it to fee
        transaction['fee'] = (estimatedFee + change).toString();
      }
      
      return transaction;
    } catch (e) {
      throw Exception('Failed to build transaction: $e');
    }
  }
  
  // Select UTXOs using largest-first algorithm
  List<Map<String, dynamic>> _selectUtxos(
    List<Map<String, dynamic>> utxos,
    BigInt targetAmount,
  ) {
    // Sort UTXOs by value (largest first)
    final sortedUtxos = List<Map<String, dynamic>>.from(utxos);
    sortedUtxos.sort((a, b) {
      final aValue = _getUtxoValue(a);
      final bValue = _getUtxoValue(b);
      return bValue.compareTo(aValue);
    });
    
    // Select UTXOs until we have enough
    final selected = <Map<String, dynamic>>[];
    BigInt accumulated = BigInt.zero;
    
    // Add estimated fee buffer (overestimate for safety)
    final targetWithFee = targetAmount + BigInt.from(200000); // ~0.2 ADA for fees
    
    for (var utxo in sortedUtxos) {
      if (accumulated >= targetWithFee) break;
      
      selected.add(utxo);
      accumulated += _getUtxoValue(utxo);
    }
    
    if (accumulated < targetWithFee) {
      throw Exception('Insufficient funds in UTXOs');
    }
    
    return selected;
  }
  
  // Get lovelace value from UTXO
  BigInt _getUtxoValue(Map<String, dynamic> utxo) {
    final amounts = utxo['amount'] as List<dynamic>;
    for (var amount in amounts) {
      if (amount['unit'] == 'lovelace') {
        return BigInt.parse(amount['quantity']);
      }
    }
    return BigInt.zero;
  }
  
  // Estimate transaction fee using Cardano's linear fee formula
  BigInt _estimateFee(int numInputs, int numOutputs) {
    // Simplified fee calculation based on research
    // Real calculation needs exact transaction size in bytes
    
    // Estimate transaction size
    // Base transaction ~300 bytes
    // Each input ~100 bytes  
    // Each output ~50 bytes
    final estimatedSize = 300 + (numInputs * 100) + (numOutputs * 50);
    
    // Linear fee formula: fee = minFeeA * size + minFeeB
    final fee = (MIN_FEE_A * estimatedSize) + MIN_FEE_B;
    
    return BigInt.from(fee);
  }
  
  // Submit transaction to Blockfrost
  Future<String> submitTransaction(String signedTxHex) async {
    final url = Uri.https(
      _config.isMainnet 
        ? 'cardano-mainnet.blockfrost.io'
        : 'cardano-testnet.blockfrost.io',
      '/api/v0/tx/submit',
    );
    
    // Convert hex to bytes
    final bytes = _hexToBytes(signedTxHex);
    
    final response = await http.post(
      url,
      headers: {
        'project_id': _config.blockfrostApiKey,
        'Content-Type': 'application/cbor',
      },
      body: bytes,
    );
    
    if (response.statusCode == 200) {
      // Response body contains the transaction hash
      return response.body.replaceAll('"', ''); // Remove quotes
    } else {
      final error = response.body;
      throw Exception('Transaction submission failed: $error');
    }
  }
  
  // Convert hex string to bytes
  Uint8List _hexToBytes(String hex) {
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(bytes);
  }
  
  // Validate Cardano address format
  bool validateAddress(String address) {
    // Use wallet service's validation
    return _walletService.validateAddress(address);
  }
} 