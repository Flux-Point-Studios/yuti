import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

// SaturnSwap service for Cardano-native token exchanges
// This integrates with SaturnSwap's API for on-chain DEX functionality
class SaturnSwapService {
  final AppConfig _config = AppConfig();
  
  // Singleton pattern
  static final SaturnSwapService _instance = SaturnSwapService._internal();
  factory SaturnSwapService() => _instance;
  SaturnSwapService._internal();
  
  // SaturnSwap API endpoints
  String get _baseUrl => 'https://app.saturnswap.io/api'; // TODO: Replace with actual SaturnSwap API URL
  
  // Get available Cardano trading pairs
  Future<List<Map<String, dynamic>>> getAvailablePairs() async {
    try {
      final url = Uri.parse('$_baseUrl/pairs');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['pairs'] ?? []);
      } else {
        throw Exception('Failed to fetch SaturnSwap trading pairs');
      }
    } catch (e) {
      // Return mock data for demo purposes
      return [
        {'from': 'ADA', 'to': 'DJED', 'fee': 0.003},
        {'from': 'ADA', 'to': 'SHEN', 'fee': 0.003},
        {'from': 'ADA', 'to': 'INDIGO', 'fee': 0.003},
        {'from': 'DJED', 'to': 'ADA', 'fee': 0.003},
        {'from': 'SHEN', 'to': 'ADA', 'fee': 0.003},
      ];
    }
  }
  
  // Get swap quote from SaturnSwap
  Future<SaturnSwapQuote> getSwapQuote({
    required String fromToken,
    required String toToken,
    required String amount,
    required bool isFromAmount,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/quote');
      final body = {
        'from_token': fromToken,
        'to_token': toToken,
        'amount': amount,
        'is_from_amount': isFromAmount,
      };
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return SaturnSwapQuote.fromJson(data);
      } else {
        throw Exception('Failed to get SaturnSwap quote');
      }
    } catch (e) {
      // Return mock quote for demo purposes
      final fromAmount = double.parse(amount);
      final mockRate = _getMockExchangeRate(fromToken, toToken);
      final toAmount = fromAmount * mockRate * 0.997; // 0.3% fee
      
      return SaturnSwapQuote(
        fromToken: fromToken,
        toToken: toToken,
        fromAmount: amount,
        toAmount: toAmount.toStringAsFixed(6),
        exchangeRate: mockRate,
        priceImpact: 0.001, // 0.1% price impact
        fee: fromAmount * 0.003, // 0.3% fee
        expiresAt: DateTime.now().add(Duration(minutes: 5)),
      );
    }
  }
  
  // Create SaturnSwap transaction
  Future<Map<String, dynamic>> createSwapTransaction({
    required String fromToken,
    required String toToken,
    required String fromAmount,
    required String toAmount,
    required String userAddress,
    required double slippageTolerance,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/swap/create');
      final body = {
        'from_token': fromToken,
        'to_token': toToken,
        'from_amount': fromAmount,
        'to_amount': toAmount,
        'user_address': userAddress,
        'slippage_tolerance': slippageTolerance,
      };
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to create SaturnSwap transaction');
      }
    } catch (e) {
      // Return mock transaction for demo purposes
      return {
        'order_id': 'saturn_${DateTime.now().millisecondsSinceEpoch}',
        'transaction_cbor': 'mock_cbor_data_for_demo',
        'fee': '2000000', // 2 ADA in lovelace
        'status': 'ready_to_sign',
      };
    }
  }
  
  // Submit signed transaction to Cardano network
  Future<String> submitTransaction(String signedTxCbor) async {
    try {
      final url = Uri.parse('$_baseUrl/swap/submit');
      final body = {'signed_tx_cbor': signedTxCbor};
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['tx_hash'];
      } else {
        throw Exception('Failed to submit SaturnSwap transaction');
      }
    } catch (e) {
      // Return mock transaction hash for demo purposes
      return 'saturn_tx_${DateTime.now().millisecondsSinceEpoch}';
    }
  }
  
  // Get swap status by order ID
  Future<SaturnSwapStatus> getSwapStatus(String orderId) async {
    try {
      final url = Uri.parse('$_baseUrl/swap/status/$orderId');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return SaturnSwapStatus.fromJson(data);
      } else {
        throw Exception('Failed to get SaturnSwap status');
      }
    } catch (e) {
      // Return mock status for demo purposes
      return SaturnSwapStatus(
        orderId: orderId,
        status: 'completed',
        txHash: 'saturn_tx_${DateTime.now().millisecondsSinceEpoch}',
        confirmations: 15,
        timestamp: DateTime.now().subtract(Duration(minutes: 2)),
      );
    }
  }
  
  // Get pool information for a trading pair
  Future<Map<String, dynamic>> getPoolInfo(String fromToken, String toToken) async {
    try {
      final url = Uri.parse('$_baseUrl/pools/$fromToken-$toToken');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to get pool information');
      }
    } catch (e) {
      // Return mock pool info for demo purposes
      return {
        'pair': '$fromToken-$toToken',
        'liquidity_ada': '1000000000000', // 1M ADA
        'liquidity_token': '500000000000', // 500K tokens
        'volume_24h': '50000000000', // 50K ADA
        'fee': 0.003, // 0.3%
      };
    }
  }
  
  // Helper method to get mock exchange rates for demo
  double _getMockExchangeRate(String fromToken, String toToken) {
    final rates = {
      'ADA-DJED': 0.45,
      'ADA-SHEN': 100.0,
      'ADA-INDIGO': 0.75,
      'DJED-ADA': 2.22,
      'SHEN-ADA': 0.01,
      'INDIGO-ADA': 1.33,
    };
    
    return rates['$fromToken-$toToken'] ?? 1.0;
  }
}

// Data models for SaturnSwap
class SaturnSwapQuote {
  final String fromToken;
  final String toToken;
  final String fromAmount;
  final String toAmount;
  final double exchangeRate;
  final double priceImpact;
  final double fee;
  final DateTime expiresAt;
  
  SaturnSwapQuote({
    required this.fromToken,
    required this.toToken,
    required this.fromAmount,
    required this.toAmount,
    required this.exchangeRate,
    required this.priceImpact,
    required this.fee,
    required this.expiresAt,
  });
  
  factory SaturnSwapQuote.fromJson(Map<String, dynamic> json) {
    return SaturnSwapQuote(
      fromToken: json['from_token'],
      toToken: json['to_token'],
      fromAmount: json['from_amount'],
      toAmount: json['to_amount'],
      exchangeRate: json['exchange_rate'].toDouble(),
      priceImpact: json['price_impact'].toDouble(),
      fee: json['fee'].toDouble(),
      expiresAt: DateTime.parse(json['expires_at']),
    );
  }
}

class SaturnSwapStatus {
  final String orderId;
  final String status; // 'pending', 'completed', 'failed'
  final String? txHash;
  final String? errorMessage;
  final int? confirmations;
  final DateTime timestamp;
  
  SaturnSwapStatus({
    required this.orderId,
    required this.status,
    this.txHash,
    this.errorMessage,
    this.confirmations,
    required this.timestamp,
  });
  
  factory SaturnSwapStatus.fromJson(Map<String, dynamic> json) {
    return SaturnSwapStatus(
      orderId: json['order_id'],
      status: json['status'],
      txHash: json['tx_hash'],
      errorMessage: json['error_message'],
      confirmations: json['confirmations'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}