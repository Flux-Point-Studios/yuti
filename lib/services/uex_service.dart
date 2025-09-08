import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../config/secure_config.dart';

// UEX swap service for token exchanges
// Based on research document's UEX integration approach
class UEXService {
  final AppConfig _config = AppConfig();
  final SecureConfig _secureConfig = SecureConfig();
  
  // Singleton pattern
  static final UEXService _instance = UEXService._internal();
  factory UEXService() => _instance;
  UEXService._internal();
  
  // UEX API endpoints
  String get _baseUrl => _config.uexApiUrl;
  
  // UEX Swap (DEX) API base
  String get _swapApiBase => _config.uexSwapApiUrl;

  // Get available trading pairs
  Future<List<Map<String, dynamic>>> getAvailablePairs() async {
    try {
      final url = Uri.parse('$_baseUrl/pairs');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['pairs'] ?? []);
      } else {
        throw Exception('Failed to fetch trading pairs');
      }
    } catch (e) {
      throw Exception('Error fetching pairs: $e');
    }
  }
  
  // Get token information
  Future<Map<String, dynamic>> getTokenInfo(String tokenSymbol) async {
    try {
      final url = Uri.parse('$_baseUrl/tokens/$tokenSymbol');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to fetch token info');
      }
    } catch (e) {
      throw Exception('Error fetching token info: $e');
    }
  }
  
  // Get swap quote
  Future<SwapQuote> getSwapQuote({
    required String fromToken,
    required String toToken,
    required String amount,
    required bool isFromAmount, // true if amount is for fromToken
  }) async {
    try {
      // Get credentials
      final credentials = await _secureConfig.getUEXCredentials();
      
      final url = Uri.parse('$_baseUrl/swap/quote');
      final body = {
        'from_token': fromToken,
        'to_token': toToken,
        'amount': amount,
        'is_from_amount': isFromAmount,
      };
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Client-Id': credentials['clientId']!,
          'X-Secret-Key': credentials['secretKey']!,
        },
        body: json.encode(body),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return SwapQuote.fromJson(data);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Failed to get swap quote');
      }
    } catch (e) {
      throw Exception('Error getting swap quote: $e');
    }
  }
  
  // Create swap transaction
  Future<Map<String, dynamic>> createSwapTransaction({
    required String fromToken,
    required String toToken,
    required String fromAmount,
    required String toAmount,
    required String userAddress,
    required double slippageTolerance,
  }) async {
    try {
      final credentials = await _secureConfig.getUEXCredentials();
      
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
        headers: {
          'Content-Type': 'application/json',
          'X-Client-Id': credentials['clientId']!,
          'X-Secret-Key': credentials['secretKey']!,
        },
        body: json.encode(body),
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Failed to create swap');
      }
    } catch (e) {
      throw Exception('Error creating swap: $e');
    }
  }
  
  // Submit signed swap transaction
  Future<String> submitSwapTransaction(String signedTxHex) async {
    try {
      final credentials = await _secureConfig.getUEXCredentials();
      
      final url = Uri.parse('$_baseUrl/swap/submit');
      final body = {
        'signed_tx': signedTxHex,
      };
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'X-Client-Id': credentials['clientId']!,
          'X-Secret-Key': credentials['secretKey']!,
        },
        body: json.encode(body),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['tx_hash'];
      } else {
        final error = json.decode(response.body);
        throw Exception(error['message'] ?? 'Failed to submit swap');
      }
    } catch (e) {
      throw Exception('Error submitting swap: $e');
    }
  }
  
  // Get swap status
  Future<SwapStatus> getSwapStatus(String txHash) async {
    try {
      final url = Uri.parse('$_baseUrl/swap/status/$txHash');
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return SwapStatus.fromJson(data);
      } else {
        throw Exception('Failed to get swap status');
      }
    } catch (e) {
      throw Exception('Error getting swap status: $e');
    }
  }
  
  // Get price chart data
  Future<List<PricePoint>> getPriceHistory({
    required String tokenPair,
    required String interval, // '1h', '1d', '1w', '1m'
    int? limit,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/price/history').replace(
        queryParameters: {
          'pair': tokenPair,
          'interval': interval,
          if (limit != null) 'limit': limit.toString(),
        },
      );
      
      final response = await http.get(url);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final prices = data['prices'] as List;
        return prices.map((p) => PricePoint.fromJson(p)).toList();
      } else {
        throw Exception('Failed to get price history');
      }
    } catch (e) {
      throw Exception('Error getting price history: $e');
    }
  }

  /// Query UEXSwap DEX histories
  /// filters example:
  /// [
  ///   {"filterType":"STATUS","values":["PENDING","LIMIT","MEMPOOL"]},
  ///   {"filterType":"ADDRESS","values":["addr1..."]}
  /// ]
  Future<Map<String, dynamic>> getDexHistories({
    required int page,
    required String token,
    required List<Map<String, dynamic>> filters,
  }) async {
    final url = Uri.parse('$_swapApiBase/dex/histories');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'page': page,
        'token': token,
        'filters': filters,
      }),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }

    throw Exception('DEX histories failed: ${response.statusCode} - ${response.body}');
  }

  /// Poll swap status by watching a deposit or destination address on UEXSwap
  /// Emits status updates until terminal state (COMPLETED/FAILED/CANCELED) or timeout
  Stream<Map<String, dynamic>> watchSwapStatusByAddress({
    required String watchAddress,
    required String token,
    Duration pollInterval = const Duration(seconds: 6),
    Duration timeout = const Duration(minutes: 15),
  }) async* {
    final stopwatch = Stopwatch()..start();
    String lastState = '';

    while (stopwatch.elapsed < timeout) {
      try {
        final result = await getDexHistories(
          page: 1,
          token: token,
          filters: [
            { 'filterType': 'ADDRESS', 'values': [watchAddress] },
          ],
        );

        // Expected shape: { data: { items: [...] } } (be tolerant to variations)
        final data = result['data'] ?? result;
        final List items = (data['items'] ?? data['histories'] ?? []) as List;

        // Pick the most recent relevant item, if any
        if (items.isNotEmpty) {
          final Map<String, dynamic> latest = Map<String, dynamic>.from(items.first);
          final String status = (latest['status'] ?? latest['state'] ?? 'UNKNOWN').toString().toUpperCase();

          if (status != lastState) {
            lastState = status;
            yield {
              'status': status, // e.g., PENDING, MEMPOOL, COMPLETED, FAILED
              'item': latest,
            };
          }

          if (status == 'COMPLETED' || status == 'SUCCESS' || status == 'FILLED') {
            break;
          }
          if (status == 'FAILED' || status == 'CANCELED' || status == 'EXPIRED') {
            break;
          }
        } else {
          // Emit a heartbeat if no items found, once
          if (lastState != 'NO_DATA') {
            lastState = 'NO_DATA';
            yield { 'status': 'NO_DATA' };
          }
        }
      } catch (e) {
        // Emit error once, then continue polling
        if (lastState != 'ERROR') {
          lastState = 'ERROR';
          yield { 'status': 'ERROR', 'error': e.toString() };
        }
      }

      await Future.delayed(pollInterval);
    }

    stopwatch.stop();
  }

  // Merchant API: Obtain OAuth2 access token for payments
  Future<String> _fetchPaymentToken() async {
    final creds = await _secureConfig.getUEXCredentials();
    final url = Uri.parse('$_baseUrl/merchant/oauth2/token');
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'client_id': creds['clientId'],
        'secret_key': creds['secretKey'],
      }),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final token = data['data']?['access_token'];
      if (token is String && token.isNotEmpty) {
        return token;
      }
      throw Exception('Token not found in response');
    } else {
      throw Exception('Failed to get UEX token: ${response.statusCode}');
    }
  }

  // Merchant API: Generate checkout/payment URL
  Future<String> generatePaymentUrl({
    required String orderId,
    required String itemName,
    required int amountCents,
    required String successUrl,
    required String failureUrl,
  }) async {
    final token = await _fetchPaymentToken();
    final url = Uri.parse('$_baseUrl/merchant/generate-payment-url');

    final body = {
      'order': orderId,
      'item_name': itemName,
      'amount': amountCents.toString(),
      'success_url': successUrl,
      'failure_url': failureUrl,
    };

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final redirectUrl = data['data']?['redirect_url'];
      if (redirectUrl is String && redirectUrl.isNotEmpty) {
        return redirectUrl;
      }
      throw Exception('No redirect_url in response');
    } else {
      throw Exception('Payment URL generation failed: ${response.statusCode} - ${response.body}');
    }
  }
}

// Data models
class SwapQuote {
  final String fromToken;
  final String toToken;
  final String fromAmount;
  final String toAmount;
  final double exchangeRate;
  final double priceImpact;
  final double fee;
  final DateTime expiresAt;
  
  SwapQuote({
    required this.fromToken,
    required this.toToken,
    required this.fromAmount,
    required this.toAmount,
    required this.exchangeRate,
    required this.priceImpact,
    required this.fee,
    required this.expiresAt,
  });
  
  factory SwapQuote.fromJson(Map<String, dynamic> json) {
    return SwapQuote(
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

class SwapStatus {
  final String txHash;
  final String status; // 'pending', 'confirmed', 'failed'
  final String? errorMessage;
  final int? confirmations;
  final DateTime timestamp;
  
  SwapStatus({
    required this.txHash,
    required this.status,
    this.errorMessage,
    this.confirmations,
    required this.timestamp,
  });
  
  factory SwapStatus.fromJson(Map<String, dynamic> json) {
    return SwapStatus(
      txHash: json['tx_hash'],
      status: json['status'],
      errorMessage: json['error_message'],
      confirmations: json['confirmations'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

class PricePoint {
  final DateTime timestamp;
  final double price;
  final double volume;
  
  PricePoint({
    required this.timestamp,
    required this.price,
    required this.volume,
  });
  
  factory PricePoint.fromJson(Map<String, dynamic> json) {
    return PricePoint(
      timestamp: DateTime.parse(json['timestamp']),
      price: json['price'].toDouble(),
      volume: json['volume'].toDouble(),
    );
  }
} 