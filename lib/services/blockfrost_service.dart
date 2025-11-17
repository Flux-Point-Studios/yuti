import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb;
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
      // Web: generic proxy first to avoid key in client and cut 404 noise
      if (kIsWeb) {
        final proxy = Uri.parse('/api/blockfrost-proxy?path=' + Uri.encodeComponent('addresses/$address'));
        final resp = await http.get(proxy);
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body);
          final amounts = data['amount'] as List;
          for (var amount in amounts) {
            if (amount['unit'] == 'lovelace') {
              return BigInt.parse(amount['quantity']);
            }
          }
          return BigInt.zero;
        }
        if (resp.statusCode == 404) return BigInt.zero; // never-seen address
        throw Exception('Failed to fetch balance: ${resp.statusCode}');
      }

      // Native: direct Blockfrost
      final headers = await _getHeaders();
      final url = Uri.https(_baseUrl, '/api/v0/addresses/$address');
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

  // Get aggregated ADA balance for a stake address (in lovelace)
  Future<BigInt> getAggregatedAdaForStakeAddress(String stakeAddress) async {
    try {
      if (kIsWeb) {
        final proxy = Uri.parse('/api/blockfrost-proxy?path=' + Uri.encodeComponent('accounts/$stakeAddress'));
        final resp = await http.get(proxy);
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body) as Map<String, dynamic>;
          final controlled = (data['controlled_amount'] ?? data['controlled'] ?? '0').toString();
          return BigInt.tryParse(controlled) ?? BigInt.zero;
        }
        if (resp.statusCode == 404) return BigInt.zero;
        throw Exception('Failed to fetch aggregated ADA: ${resp.statusCode}');
      }
      final headers = await _getHeaders();
      final url = Uri.https(_baseUrl, '/api/v0/accounts/$stakeAddress');
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final controlled = (data['controlled_amount'] ?? data['controlled'] ?? '0').toString();
        return BigInt.tryParse(controlled) ?? BigInt.zero;
      } else if (response.statusCode == 404) {
        return BigInt.zero;
      } else {
        throw Exception('Failed to fetch aggregated ADA: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching aggregated ADA: $e');
    }
  }

  // Get all assets (tokens) for an address
  Future<List<Map<String, dynamic>>> getAssets(String address) async {
    try {
      if (kIsWeb) {
        final proxy = Uri.parse('/api/blockfrost-proxy?path=' + Uri.encodeComponent('addresses/$address'));
        final resp = await http.get(proxy);
        if (resp.statusCode == 200) {
          final data = json.decode(resp.body);
          final amounts = data['amount'] as List;
          return amounts
              .where((asset) => asset['unit'] != 'lovelace')
              .map((asset) => asset as Map<String, dynamic>)
              .toList();
        }
        if (resp.statusCode == 404) return [];
        throw Exception('Failed to fetch assets: ${resp.statusCode}');
      }
      final headers = await _getHeaders();
      final url = Uri.https(_baseUrl, '/api/v0/addresses/$address');
      final response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final amounts = data['amount'] as List;
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
      if (kIsWeb) {
        final proxy = Uri.parse('/api/blockfrost-proxy?path=' + Uri.encodeComponent('addresses/$address/utxos'));
        final resp = await http.get(proxy);
        if (resp.statusCode == 200) {
          final utxos = json.decode(resp.body) as List;
          return utxos.map((utxo) => utxo as Map<String, dynamic>).toList();
        }
        if (resp.statusCode == 404) return [];
        throw Exception('Failed to fetch UTXOs: ${resp.statusCode}');
      }
      final headers = await _getHeaders();
      final url = Uri.https(_baseUrl, '/api/v0/addresses/$address/utxos');
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
      // 1) Prefer DB-Sync proxy if available
      if (kIsWeb) {
        try {
          final proxy = Uri.parse('/api/dbsync/transactions?address=${Uri.encodeComponent(address)}&page=$page');
          final resp = await http.get(proxy);
          if (resp.statusCode == 200) {
            final list = (json.decode(resp.body) as List).cast<Map<String, dynamic>>();
            return list;
          }
        } catch (_) {}
      } else {
        // On native, allow using WEB_API_BASE to reach the same serverless function
        final base = AppConfig().webApiBase.trim();
        if (base.isNotEmpty) {
          try {
            final normalized = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
            final url = Uri.parse('$normalized/api/dbsync/transactions?address=${Uri.encodeComponent(address)}&page=$page');
            final resp = await http.get(url);
            if (resp.statusCode == 200) {
              final list = (json.decode(resp.body) as List).cast<Map<String, dynamic>>();
              return list;
            }
          } catch (_) {}
        }
      }

      // 2) Fallback to Blockfrost
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
      final normalized = assetId.toLowerCase();
      // On web, prefer proxy first to avoid client key requirement and CORS
      if (kIsWeb) {
        final proxy = Uri.parse('/api/blockfrost-proxy?path=' + Uri.encodeComponent('assets/$normalized'));
        var resp = await http.get(proxy);
        if (resp.statusCode == 200) {
          return json.decode(resp.body);
        }
        // Fallback to path-style proxy if configured
        final alt = Uri.parse('/api/blockfrost/assets/$normalized');
        resp = await http.get(alt);
        if (resp.statusCode == 200) {
          return json.decode(resp.body);
        }
        throw Exception('Failed to fetch asset metadata (web): ${resp.statusCode}');
      }

      // Native: use direct Blockfrost with project_id header
      final url = Uri.https(_baseUrl, '/api/v0/assets/$normalized');
      final headers = await _getHeaders();
      final response = await http.get(url, headers: headers);
      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      throw Exception('Failed to fetch asset metadata: ${response.statusCode}');
    } catch (e) {
      // Defensive fallback so UI can continue with minimal data
      print('🔍 DEBUG: getAssetMetadata error for $assetId -> $e');
      return {
        'asset': assetId,
        'onchain_metadata': {},
        'metadata': {},
      };
    }
  }

  // Helper: attempt to decode a hex string to ASCII; return null if invalid
  String? _tryDecodeHexToAscii(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final cleaned = hex.trim();
    if (cleaned.length % 2 != 0) return null;
    try {
      final bytes = <int>[];
      for (int i = 0; i < cleaned.length; i += 2) {
        bytes.add(int.parse(cleaned.substring(i, i + 2), radix: 16));
      }
      return String.fromCharCodes(bytes);
    } catch (_) {
      return null;
    }
  }

  // Get display info (name, ticker, decimals) for an asset unit
  Future<Map<String, dynamic>> getAssetDisplayInfo(String unit) async {
    final meta = await getAssetMetadata(unit);
    final policyId = meta['policy_id'];
    final assetHex = meta['asset_name'];
    final fingerprint = meta['fingerprint'];
    final std = (meta['onchain_metadata_standard'] ?? '') as String;
    final isCip25 = std.startsWith('CIP25');
    final isCip68 = std.startsWith('CIP68');
    final isLabel222 = (assetHex is String) && assetHex.startsWith('000de140');
    final totalSupplyStr = (meta['quantity'] ?? '').toString();
    final isCip25Nft = isCip25 && totalSupplyStr == '1';
    final isNFT = (isCip68 && isLabel222) || isCip25Nft;

    final onchain = (meta['onchain_metadata'] ?? {}) as Map<String, dynamic>;
    final registry = (meta['metadata'] ?? {}) as Map<String, dynamic>;

    int? decimals;
    final decVal = registry['decimals'] ?? onchain['decimals'];
    if (decVal is int) {
      decimals = decVal;
    } else if (decVal is String) {
      decimals = int.tryParse(decVal);
    }

    final nameCandidate = registry['name'] ?? onchain['name'] ?? _tryDecodeHexToAscii(assetHex);
    final tickerCandidate = registry['ticker'] ?? onchain['ticker'];

    dynamic imageCandidate = onchain['image'] ?? onchain['img'];
    if (imageCandidate == null && onchain['files'] is List && (onchain['files'] as List).isNotEmpty) {
      imageCandidate = (onchain['files'] as List).first;
    }
    imageCandidate ??= registry['logo'];
    final imageUrl = _normalizeImageUrl(imageCandidate);

    return {
      'unit': unit,
      'policy_id': policyId,
      'asset_name': assetHex,
      'name': nameCandidate?.toString(),
      'ticker': tickerCandidate?.toString(),
      'decimals': decimals,
      'fingerprint': fingerprint,
      'image': imageUrl,
      'isNFT': isNFT,
    };
  }

  String? _normalizeImageUrl(dynamic raw) {
    dynamic v = raw;
    if (v == null) return null;
    if (v is List && v.isNotEmpty) v = v.first;
    if (v is Map) v = v['src'] ?? v['url'] ?? v['image'] ?? v['uri'] ?? v['link'];
    if (v is! String) v = v.toString();
    var s = (v as String).trim();
    if (s.isEmpty || s == '[]') return null;

    s = s
        .replaceFirst(RegExp(r'^ipfs://ipfs/'), 'ipfs://')
        .replaceFirst(RegExp(r'^https?://ipfs\.io/ipfs/'), 'ipfs://')
        .replaceFirst(RegExp(r'^https?://cloudflare-ipfs\.com/ipfs/'), 'ipfs://')
        .replaceFirst(RegExp(r'^https?://dweb\.link/ipfs/'), 'ipfs://');

    if (s.startsWith('ipfs://')) {
      final m = RegExp(r'^ipfs://([^/?#]+)(/.*)?$').firstMatch(s);
      if (m == null) return null;
      final cid = m.group(1)!;
      final rest = m.group(2) ?? '';
      final looksLikeCid = (cid.startsWith('Qm') && cid.length >= 46) ||
          (cid.startsWith('baf') && cid.length >= 40);
      if (!looksLikeCid) return null;
      return 'https://cloudflare-ipfs.com/ipfs/$cid$rest';
    }

    if (s.startsWith('ar://')) return 'https://arweave.net/${s.substring(5)}';
    if (s.startsWith('http://') || s.startsWith('https://')) return s;

    final cidOnly = RegExp(r'^(Qm[1-9A-HJ-NP-Za-km-z]{44,}|baf[0-9A-Za-z]{30,})$');
    if (cidOnly.hasMatch(s)) return 'https://cloudflare-ipfs.com/ipfs/$s';
    return null;
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
      // Canonical asset name for AGENT (hex) is '54616c6f73' => 'Talos'. If holdings use this
      // unit, prefer matching exactly policy+name; otherwise fall back to policy prefix.
      const agentAssetHex = '54616c6f73';
      final expectedAgentUnit = agentPolicy + agentAssetHex;
      final agentTokens = aggregatedAssets
          .where((asset) {
            final unit = asset['unit'].toString();
            if (unit == expectedAgentUnit) return true;
            // Fallback: allow policy prefix match to be tolerant of variants
            return unit.startsWith(agentPolicy);
          })
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
      if (kIsWeb) {
        final proxy = Uri.parse('/api/blockfrost-proxy?path=' + Uri.encodeComponent('accounts/$stakeAddress/addresses'));
        final resp = await http.get(proxy);
        if (resp.statusCode == 200) {
          final list = json.decode(resp.body) as List;
          return list.map<String>((e) => e['address'] as String).toList();
        }
        if (resp.statusCode == 404) return <String>[];
        return <String>[];
      }
      final headers = await _getHeaders();
      final url = Uri.https(_baseUrl, '/api/v0/accounts/$stakeAddress/addresses');
      var response = await http.get(url, headers: headers);
      if ((response.headers['content-type'] ?? '').contains('text/html') || response.statusCode != 200) {
        final alt = Uri.parse('/api/blockfrost-proxy?path=' + Uri.encodeComponent('accounts/$stakeAddress/addresses'));
        response = await http.get(alt);
      }
      if (response.statusCode == 200) {
        final list = json.decode(response.body) as List;
        return list.map<String>((e) => e['address'] as String).toList();
      }
      return <String>[];
    } catch (e) {
      return <String>[];
    }
  }

  /// Aggregate assets across all addresses controlled by a stake key (use Blockfrost aggregated endpoint)
  Future<List<Map<String, dynamic>>> getAggregatedAssetsForStakeAddress(String stakeAddress) async {
    // Return cached if fresh
    final cached = _stakeAssetsCache[stakeAddress];
    if (cached != null && DateTime.now().difference(cached.cachedAt) < _stakeAssetsTtl) {
      return cached.assets;
    }

    // Prefer aggregated endpoint with pagination
    List<Map<String, dynamic>> all = [];
    int page = 1;
    const int count = 100;
    while (true) {
      if (kIsWeb) {
        final proxy = Uri.parse('/api/blockfrost-proxy?path=' + Uri.encodeComponent('accounts/$stakeAddress/addresses/assets') + '&count=$count&page=$page&order=asc');
        final resp = await http.get(proxy);
        if (resp.statusCode == 404) break;
        if (resp.statusCode != 200) break;
        final chunk = (json.decode(resp.body) as List).cast<Map<String, dynamic>>();
        all.addAll(chunk);
        if (chunk.length < count) break;
      } else {
        final headers = await _getHeaders();
        final url = Uri.https(_baseUrl, '/api/v0/accounts/$stakeAddress/addresses/assets', {
          'count': '$count',
          'page': '$page',
          'order': 'asc',
        });
        final response = await http.get(url, headers: headers);
        if (response.statusCode != 200) {
          break;
        }
        final chunk = (json.decode(response.body) as List).cast<Map<String, dynamic>>();
        all.addAll(chunk);
        if (chunk.length < count) break;
      }
      page += 1;
      if (page > 1000) break; // guardrail
    }

    _stakeAssetsCache[stakeAddress] = _StakeAssetsCacheEntry(assets: all, cachedAt: DateTime.now());
    if (all.isNotEmpty) return all;

    // Manual per-address fallback
    final addresses = await _getAddressesForStakeAddress(stakeAddress);
    if (addresses.isEmpty) return <Map<String, dynamic>>[];

    final Map<String, BigInt> unitToQuantity = {};
    const int maxConcurrent = 4;
    int index = 0;
    Future<void> worker() async {
      while (true) {
        String? nextAddr;
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
        } catch (_) {}
      }
    }
    await Future.wait(List.generate(maxConcurrent, (_) => worker()));
    final aggregated = unitToQuantity.entries
        .map((e) => {
              'unit': e.key,
              'quantity': e.value.toString(),
            })
        .toList();
    _stakeAssetsCache[stakeAddress] = _StakeAssetsCacheEntry(assets: aggregated, cachedAt: DateTime.now());
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
