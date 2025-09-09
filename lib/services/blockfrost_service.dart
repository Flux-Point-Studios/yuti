import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../config/secure_config.dart';

class BlockfrostService {
  final AppConfig _config = AppConfig();
  final SecureConfig _secureConfig = SecureConfig();

  // Simple in-memory cache for aggregated stake assets
  final Map<String, _StakeAssetsCacheEntry> _stakeAssetsCache = {};
  static const Duration _stakeAssetsTtl = Duration(seconds: 45);

  // Cache API key after first fetch
  String? _cachedApiKey;

  // Singleton pattern
  static final BlockfrostService _instance = BlockfrostService._internal();
  factory BlockfrostService() => _instance;
  BlockfrostService._internal();

  // Get headers with secure API key
  Future<Map<String, String>> _getHeaders() async {
    // Use cached key if available
    if (_cachedApiKey == null) {
      _cachedApiKey = await _secureConfig.getBlockfrostApiKey();
      print('🔍 DEBUG: Blockfrost API key loaded successfully (${_cachedApiKey!.length} chars)');
    }

    return {
      'project_id': _cachedApiKey!,
    };
  }

  // Get base URL based on network
  String get _baseUrl => _config.isMainnet
      ? 'cardano-mainnet.blockfrost.io'
      : 'cardano-testnet.blockfrost.io';

  // Get ADA balance for an address (in lovelace)
  Future<BigInt> getAdaBalance(String address) async {
    try {
      final url = Uri.https(_baseUrl, '/api/v0/addresses/$address');
      final headers = await _getHeaders();
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final amounts = data['amount'] as List;

        // Find lovelace amount
        for (var amount in amounts) {
          if (amount['unit'] == 'lovelace') {
            return BigInt.parse(amount['quantity']);
          }
        }
        return BigInt.zero;
      } else if (response.statusCode == 404) {
        // Address not found or has no UTXOs
        return BigInt.zero;
      } else {
        throw Exception('Failed to fetch balance: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching balance: $e');
    }
  }

  // Get all assets (tokens) for an address
  Future<List<Map<String, dynamic>>> getAssets(String address) async {
    try {
      final url = Uri.https(_baseUrl, '/api/v0/addresses/$address');
      final headers = await _getHeaders();
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final amounts = data['amount'] as List;

        // Filter out lovelace and return other assets
        return amounts
            .where((asset) => asset['unit'] != 'lovelace')
            .map((asset) => asset as Map<String, dynamic>)
            .toList();
      } else if (response.statusCode == 404) {
        return [];
      } else {
        throw Exception('Failed to fetch assets: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching assets: $e');
    }
  }

  // Get UTXOs for an address
  Future<List<Map<String, dynamic>>> getUtxos(String address) async {
    try {
      final url = Uri.https(_baseUrl, '/api/v0/addresses/$address/utxos');
      final headers = await _getHeaders();
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final utxos = json.decode(response.body) as List;
        return utxos.map((utxo) => utxo as Map<String, dynamic>).toList();
      } else if (response.statusCode == 404) {
        return [];
      } else {
        throw Exception('Failed to fetch UTXOs: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching UTXOs: $e');
    }
  }

  // Get transaction history for an address
  Future<List<Map<String, dynamic>>> getTransactions(String address,
      {int page = 1}) async {
    try {
      final url =
          Uri.https(_baseUrl, '/api/v0/addresses/$address/transactions', {
        'page': page.toString(),
        'order': 'desc',
      });
      final headers = await _getHeaders();
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final txs = json.decode(response.body) as List;
        return txs.map((tx) => tx as Map<String, dynamic>).toList();
      } else if (response.statusCode == 404) {
        return [];
      } else {
        throw Exception('Failed to fetch transactions: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching transactions: $e');
    }
  }

  // Get detailed transaction info
  Future<Map<String, dynamic>> getTransactionDetails(String txHash) async {
    try {
      final url = Uri.https(_baseUrl, '/api/v0/txs/$txHash');
      final headers = await _getHeaders();
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception(
            'Failed to fetch transaction details: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching transaction details: $e');
    }
  }

  // Get asset metadata
  Future<Map<String, dynamic>> getAssetMetadata(String assetId) async {
    try {
      final url = Uri.https(_baseUrl, '/api/v0/assets/$assetId');
      final headers = await _getHeaders();
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception(
            'Failed to fetch asset metadata: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching asset metadata: $e');
    }
  }

  // Submit transaction
  Future<String> submitTransaction(List<int> txBytes) async {
    try {
      final url = Uri.https(_baseUrl, '/api/v0/tx/submit');
      final headers = await _getHeaders();
      final response = await http.post(
        url,
        headers: {
          ...headers,
          'Content-Type': 'application/cbor',
        },
        body: txBytes,
      );

      if (response.statusCode == 200) {
        return response.body; // Returns transaction hash
      } else {
        final error = response.body;
        throw Exception('Transaction submission failed: $error');
      }
    } catch (e) {
      throw Exception('Error submitting transaction: $e');
    }
  }

  // Get current protocol parameters (needed for transaction building)
  Future<Map<String, dynamic>> getProtocolParameters() async {
    try {
      final url = Uri.https(_baseUrl, '/api/v0/epochs/latest/parameters');
      final headers = await _getHeaders();
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception(
            'Failed to fetch protocol parameters: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching protocol parameters: $e');
    }
  }

  // Get network info
  Future<Map<String, dynamic>> getNetworkInfo() async {
    try {
      final url = Uri.https(_baseUrl, '/api/v0/network');
      final headers = await _getHeaders();
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to fetch network info: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching network info: $e');
    }
  }

  // Premium access checking methods

  /// Check if stake address is delegated to the required pool with minimum stake
  Future<Map<String, dynamic>> getStakeAddressInfo(String stakeAddress) async {
    try {
      final url = Uri.https(_baseUrl, '/api/v0/accounts/$stakeAddress');
      final headers = await _getHeaders();
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        return {'active': false, 'controlled_amount': '0'};
      } else {
        throw Exception(
            'Failed to fetch stake address info: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching stake address info: $e');
    }
  }

  /// Check premium access based on Cardevia V2 requirements
  Future<Map<String, dynamic>> checkPremiumAccess(String stakeAddress) async {
    try {
      final result = {
        'hasAccess': false,
        'accessLevel': 'none',
        'reason': '',
        'details': <String, dynamic>{},
      };

      // Aggregate all assets across every address controlled by this stake key
      print('🔍 DEBUG: Premium check - aggregating assets for stake: ' + stakeAddress);
      final aggregatedAssets = await getAggregatedAssetsForStakeAddress(stakeAddress);
      print('🔍 DEBUG: Premium check - aggregated asset count: ' + aggregatedAssets.length.toString());

      // AGENT policy
      const agentPolicy = '97bbb7db0baef89caefce61b8107ac74c7a7340166b39d906f174bec';
      final agentTokens = aggregatedAssets
          .where((asset) => asset['unit'].toString().startsWith(agentPolicy))
          .toList();

      final agentBalance = agentTokens.isNotEmpty
          ? agentTokens.fold<BigInt>(
              BigInt.zero,
              (sum, token) => sum + BigInt.parse(token['quantity']),
            )
          : BigInt.zero;

      print('🔍 DEBUG: Premium check - AGENT balance (raw): ' + agentBalance.toString());

      // Hardcoded holder requirement: 100,000 AGENT (assumed 0 decimals)
      final requiredAgent = BigInt.from(100000);

      print('🔍 DEBUG: Premium check - required AGENT tokens (fixed): ' + requiredAgent.toString());

      if (agentBalance >= requiredAgent) {
        result['hasAccess'] = true;
        result['accessLevel'] = 'agent_tokens_fixed_threshold';
        result['reason'] = 'Holds >= ' + requiredAgent.toString() + ' \$AGENT tokens (stake-wide)';
        result['details'] = {
          'tokenBalance': agentBalance.toString(),
          'requiredBalance': requiredAgent.toString(),
        };
        return result;
      }

      // Deny with diagnostic details
      result['reason'] = 'Requires >= ' + requiredAgent.toString() + ' \$AGENT tokens (stake-wide).';
      result['details'] = {
        'tokenBalance': agentBalance.toString(),
        'requiredBalance': requiredAgent.toString(),
      };

      return result;
    } catch (e) {
      return {
        'hasAccess': false,
        'accessLevel': 'error',
        'reason': 'Error checking premium access: ' + e.toString(),
        'details': {},
      };
    }
  }

  // Helper method to get payment address from stake address (first address)
  Future<String?> _getAddressFromStakeAddress(String stakeAddress) async {
    try {
      final url =
          Uri.https(_baseUrl, '/api/v0/accounts/$stakeAddress/addresses');
      final headers = await _getHeaders();
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final addresses = json.decode(response.body) as List;
        if (addresses.isNotEmpty) {
          return addresses.first['address'];
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Helper: get all addresses for a stake address
  Future<List<String>> _getAddressesForStakeAddress(String stakeAddress) async {
    try {
      final url = Uri.https(_baseUrl, '/api/v0/accounts/$stakeAddress/addresses');
      final headers = await _getHeaders();
      final response = await http.get(url, headers: headers);
      if (response.statusCode == 200) {
        final list = json.decode(response.body) as List;
        return list.map<String>((e) => e['address'] as String).toList();
      }
      return <String>[];
    } catch (e) {
      return <String>[];
    }
  }

  /// Aggregate assets across all addresses controlled by a stake key
  Future<List<Map<String, dynamic>>> getAggregatedAssetsForStakeAddress(String stakeAddress) async {
    // Return cached if fresh
    final cached = _stakeAssetsCache[stakeAddress];
    if (cached != null && DateTime.now().difference(cached.cachedAt) < _stakeAssetsTtl) {
      return cached.assets;
    }

    final addresses = await _getAddressesForStakeAddress(stakeAddress);
    if (addresses.isEmpty) return <Map<String, dynamic>>[];

    final Map<String, BigInt> unitToQuantity = {};

    // Parallelize with a small concurrency cap (e.g., 4)
    const int maxConcurrent = 4;
    int index = 0;
    Future<void> worker() async {
      while (true) {
        String? nextAddr;
        // Synchronized take next
        if (index < addresses.length) {
          nextAddr = addresses[index];
          index += 1;
        } else {
          break;
        }
        try {
          final assets = await getAssets(nextAddr);
          for (final asset in assets) {
            final unit = asset['unit'] as String;
            final qty = BigInt.parse(asset['quantity'] as String);
            unitToQuantity[unit] = (unitToQuantity[unit] ?? BigInt.zero) + qty;
          }
        } catch (_) {
          // Ignore individual address errors
        }
      }
    }

    // Launch workers
    final workers = List.generate(maxConcurrent, (_) => worker());
    await Future.wait(workers);

    // Convert back to list format
    final aggregated = unitToQuantity.entries
        .map((e) => {
              'unit': e.key,
              'quantity': e.value.toString(),
            })
        .toList();

    // Cache result
    _stakeAssetsCache[stakeAddress] = _StakeAssetsCacheEntry(
      assets: aggregated,
      cachedAt: DateTime.now(),
    );

    return aggregated;
  }

  /// Read Charli3 AGENT/ADA price from an oracle feed address by parsing latest datum
  Future<double?> getAgentPerAdaFromCharli3(String feedAddress) async {
    try {
      final headers = await _getHeaders();

      // Preferred: read latest UTXOs at the feed address and parse inline datum directly
      final addrUtxosUrl = Uri.https(_baseUrl, '/api/v0/addresses/$feedAddress/utxos', {
        'order': 'desc',
        'page': '1',
      });
      final addrUtxosResp = await http.get(addrUtxosUrl, headers: headers);
      if (addrUtxosResp.statusCode == 200) {
        final list = json.decode(addrUtxosResp.body) as List;
        print('🔍 DEBUG: Charli3 - address utxos count: ${list.length}');
        for (final utxo in list) {
          final inlineDatum = utxo['inline_datum'];
          if (inlineDatum != null) {
            // JSON value path
            final jsonVal = inlineDatum['json_value'];
            if (jsonVal != null) {
              final rate = _extractAgentPerAdaFromJsonDatum(jsonVal);
              if (rate != null) {
                print('🔍 DEBUG: Charli3 - extracted agentPerAda from address utxos json: $rate');
                return rate;
              }
            }
          }
        }
      } else {
        print('🔍 DEBUG: Charli3 - address utxos fetch failed: ${addrUtxosResp.statusCode}');
      }

      // Fallback: use latest transaction to the address, then read its outputs
      final txsUrl = Uri.https(_baseUrl, '/api/v0/addresses/$feedAddress/transactions', {
        'order': 'desc',
        'page': '1'
      });
      final txsResp = await http.get(txsUrl, headers: headers);
      if (txsResp.statusCode != 200) return null;
      final txs = json.decode(txsResp.body) as List;
      if (txs.isEmpty) return null;
      final latestTxHash = txs.first['tx_hash'] as String;

      final utxosUrl = Uri.https(_baseUrl, '/api/v0/txs/$latestTxHash/utxos');
      final utxosResp = await http.get(utxosUrl, headers: headers);
      if (utxosResp.statusCode != 200) return null;
      final utxos = json.decode(utxosResp.body) as Map<String, dynamic>;
      final outputs = (utxos['outputs'] as List).cast<Map<String, dynamic>>();
      for (final o in outputs) {
        if ((o['address'] as String?) == feedAddress) {
          final inlineDatum = o['inline_datum'];
          if (inlineDatum != null) {
            if (inlineDatum['json_value'] != null) {
              final jsonVal = inlineDatum['json_value'];
              final rate = _extractAgentPerAdaFromJsonDatum(jsonVal);
              if (rate != null) {
                print('🔍 DEBUG: Charli3 - extracted agentPerAda from tx outputs json: $rate');
                return rate;
              }
            }
          }
        }
      }

      // If only bytes are present, CBOR decode would be required. Not implemented in this client.
      return null;
    } catch (_) {
      return null;
    }
  }

  double? _extractAgentPerAdaFromJsonDatum(dynamic jsonVal) {
    try {
      if (jsonVal is Map<String, dynamic>) {
        // Common Charli3 pattern: { rate: { numerator: X, denominator: Y } } or flat fields
        if (jsonVal.containsKey('rate')) {
          final rate = jsonVal['rate'];
          if (rate is Map && rate['numerator'] != null && rate['denominator'] != null) {
            final numerator = (rate['numerator'] as num).toDouble();
            final denominator = (rate['denominator'] as num).toDouble();
            if (denominator != 0) return numerator / denominator; // AGENT per ADA
          }
        }
        // Fallback: direct fields
        if (jsonVal['agent_per_ada'] != null) {
          return (jsonVal['agent_per_ada'] as num).toDouble();
        }
        if (jsonVal['price'] != null) {
          return (jsonVal['price'] as num).toDouble();
        }

        // Charli3 oracle-datum standard (CDDL-style inline JSON via Blockfrost):
        // Structure like: { "fields": [ { "fields": [ { "map": [ {"k":{"int":0}, "v":{"int":334136}}, ... ] } ], "constructor": 2 } ], "constructor": 0 }
        if (jsonVal.containsKey('fields')) {
          // Walk the nested structure to find a 'map' node containing entries {k:{int:N}, v:{...}}
          double? fromMapNode(Map<String, dynamic> mapNode) {
            try {
              final entries = (mapNode['map'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
              num? priceInt;
              num? precision;
              for (final entry in entries) {
                final k = entry['k'] as Map<String, dynamic>?;
                final v = entry['v'] as Map<String, dynamic>?;
                final keyIdx = k?['int'] as int?;
                if (keyIdx == null || v == null) continue;
                // Extract numeric 'int' from value if present
                num? valInt = v['int'] as num?;
                if (keyIdx == 0 && valInt != null) {
                  priceInt = valInt;
                } else if (keyIdx == 3 && valInt != null) {
                  precision = valInt;
                }
              }
              if (priceInt != null) {
                double adaPerAgent = priceInt!.toDouble();
                if (precision != null && precision! > 0) {
                  adaPerAgent = adaPerAgent / math.pow(10, precision!.toDouble());
                }
                if (adaPerAgent == 0) return null;
                // Charli3 price map key 0 is quote per 1 base.
                // For AGENT/ADA, that's ADA per AGENT. We need AGENT per ADA.
                return 1.0 / adaPerAgent;
              }
            } catch (_) {}
            return null;
          }

          // Search recursively for any object containing a 'map'
          double? search(dynamic node) {
            if (node is Map<String, dynamic>) {
              if (node.containsKey('map')) {
                final r = fromMapNode(node);
                if (r != null) return r;
              }
              for (final v in node.values) {
                final r = search(v);
                if (r != null) return r;
              }
            } else if (node is List) {
              for (final item in node) {
                final r = search(item);
                if (r != null) return r;
              }
            }
            return null;
          }

          final parsed = search(jsonVal);
          if (parsed != null) return parsed;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Get ADA price in USD (simple Coingecko API)
  Future<double?> getAdaUsdPrice() async {
    try {
      final url = Uri.parse('https://api.coingecko.com/api/v3/simple/price?ids=cardano&vs_currencies=usd');
      final resp = await http.get(url);
      if (resp.statusCode != 200) return null;
      final data = json.decode(resp.body) as Map<String, dynamic>;
      final usd = data['cardano']?['usd'];
      if (usd is num) return usd.toDouble();
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Compute required AGENT amount given a USD target, using Charli3 AGENT/ADA and ADA/USD
  Future<BigInt?> computeRequiredAgentForUsd(double usdTarget, {String? feedAddress}) async {
    final feed = feedAddress ?? AppConfig().charli3AgentAdaFeedAddress;
    double? agentPerAda;
    // On web, use serverless proxy to support CBOR decoding if needed
    try {
      // ignore: avoid_web_libraries_in_flutter
      if (identical(0, 0)) {
        // Trick: no import of dart:html; use kIsWeb at call sites to prefer proxy in UI. Here we still try direct first.
      }
      agentPerAda = await getAgentPerAdaFromCharli3(feed);
    } catch (_) {}
    // If still null, try proxy endpoint (works across platforms)
    if (agentPerAda == null) {
      try {
        final proxyUrl = Uri.parse('/api/oracle/agent-per-ada?feed=$feed');
        final resp = await http.get(proxyUrl);
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          agentPerAda = (data['agentPerAda'] as num?)?.toDouble();
          print('🔍 DEBUG: Charli3 via proxy agentPerAda: ${agentPerAda?.toString()}');
        } else {
          print('🔍 DEBUG: Oracle proxy error status: ${resp.statusCode} body: ${resp.body}');
        }
      } catch (e) {
        print('🔍 DEBUG: Oracle proxy fetch error: $e');
      }
    }
    final adaUsd = await getAdaUsdPrice();
    if (agentPerAda == null || adaUsd == null || adaUsd == 0) return null;
    // usdTarget USD * (1 ADA / adaUsd USD) = ADA required
    final adaRequired = usdTarget / adaUsd;
    // AGENT required = adaRequired * (AGENT per ADA)
    final agentRequired = adaRequired * agentPerAda;
    // AGENT has 0 decimals per current assumption; adjust if decimals differ
    return BigInt.from(agentRequired.ceil());
  }
}

class _StakeAssetsCacheEntry {
  final List<Map<String, dynamic>> assets;
  final DateTime cachedAt;
  _StakeAssetsCacheEntry({required this.assets, required this.cachedAt});
}
