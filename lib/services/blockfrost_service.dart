import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../config/secure_config.dart';

class BlockfrostService {
  final AppConfig _config = AppConfig();
  final SecureConfig _secureConfig = SecureConfig();

  // Cache API key after first fetch
  String? _cachedApiKey;

  // Singleton pattern
  static final BlockfrostService _instance = BlockfrostService._internal();
  factory BlockfrostService() => _instance;
  BlockfrostService._internal();

  // Get headers with secure API key
  Future<Map<String, String>> _getHeaders() async {
    // Use cached key if available
    _cachedApiKey ??= await _secureConfig.getBlockfrostApiKey();

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

      // Get stake address info for pool delegation check
      final stakeInfo = await getStakeAddressInfo(stakeAddress);
      final isActive = stakeInfo['active'] == true;
      final controlledAmountStr = stakeInfo['controlled_amount'] ?? '0';
      final controlledAmount = BigInt.parse(controlledAmountStr);
      final poolId = stakeInfo['pool_id'];

      // Check for stake pool delegation (highest priority after special access)
      const requiredPoolId =
          'pool1p00qq8zftf8m2ll0r9d24fx6tq7yzxzy5teltpswl7zew5m7nqp';
      final minStakeLovelace =
          BigInt.from(1000) * BigInt.from(1000000); // 1000 ADA in lovelace

      if (isActive &&
          poolId == requiredPoolId &&
          controlledAmount >= minStakeLovelace) {
        result['hasAccess'] = true;
        result['accessLevel'] = 'stake_pool';
        result['reason'] =
            'Delegated to required stake pool with sufficient stake';
        result['details'] = {
          'poolId': poolId,
          'stakeAmount': controlledAmountStr,
          'stakeAmountAda':
              (controlledAmount ~/ BigInt.from(1000000)).toString(),
        };
        return result;
      }

      // Get address associated with this stake address for token checks
      final addressInfo = await _getAddressFromStakeAddress(stakeAddress);
      if (addressInfo == null) {
        result['reason'] = 'No address found for stake address';
        return result;
      }

      // Get assets for the address
      final assets = await getAssets(addressInfo);

      // Check for T1 ADAM Launch Pass NFT
      const adamNftPolicy =
          'b46891456b77dbc77c16090fd92a37f087f9a68e953c56b00a20332f';
      final adamNft = assets
          .where((asset) => asset['unit'].toString().startsWith(adamNftPolicy))
          .toList();

      if (adamNft.isNotEmpty) {
        result['hasAccess'] = true;
        result['accessLevel'] = 't1_adam_nft';
        result['reason'] = 'Holds T1 ADAM Launch Pass NFT';
        result['details'] = {
          'nftCount': adamNft.length,
          'nfts': adamNft,
        };
        return result;
      }

      // Check for $SHARDS tokens (6 decimals, requires 3,500 tokens = 3,500,000,000 base units)
      const shardsPolicy =
          'ea153b5d4864af15a1079a94a0e2486d6376fa28aafad272d15b243a';
      final shardsTokens = assets
          .where((asset) => asset['unit'].toString().startsWith(shardsPolicy))
          .toList();

      if (shardsTokens.isNotEmpty) {
        final shardsBalance = shardsTokens.fold<BigInt>(
          BigInt.zero,
          (sum, token) => sum + BigInt.parse(token['quantity']),
        );
        final requiredShards = BigInt.from(3500000000); // 3,500 * 10^6

        if (shardsBalance >= requiredShards) {
          result['hasAccess'] = true;
          result['accessLevel'] = 'shards_tokens';
          result['reason'] = 'Holds sufficient \$SHARDS tokens';
          result['details'] = {
            'tokenBalance': shardsBalance.toString(),
            'tokenBalanceFormatted':
                (shardsBalance ~/ BigInt.from(1000000)).toString(),
            'requiredBalance': requiredShards.toString(),
          };
          return result;
        }
      }

      // Check for $AGENT tokens (0 decimals, requires 100,000 tokens)
      const agentPolicy =
          '97bbb7db0baef89caefce61b8107ac74c7a7340166b39d906f174bec';
      final agentTokens = assets
          .where((asset) => asset['unit'].toString().startsWith(agentPolicy))
          .toList();

      if (agentTokens.isNotEmpty) {
        final agentBalance = agentTokens.fold<BigInt>(
          BigInt.zero,
          (sum, token) => sum + BigInt.parse(token['quantity']),
        );
        final requiredAgent = BigInt.from(100000); // 100,000 tokens

        if (agentBalance >= requiredAgent) {
          result['hasAccess'] = true;
          result['accessLevel'] = 'agent_tokens';
          result['reason'] = 'Holds sufficient \$AGENT tokens';
          result['details'] = {
            'tokenBalance': agentBalance.toString(),
            'requiredBalance': requiredAgent.toString(),
          };
          return result;
        }
      }

      // If no access found, return detailed reason
      result['reason'] =
          'No qualifying assets found. Required: 1000+ ADA delegated to specific pool, or T1 ADAM NFT, or 3,500+ \$SHARDS, or 100,000+ \$AGENT tokens';
      result['details'] = {
        'stakeInfo': stakeInfo,
        'assetCount': assets.length,
        'checkedPolicies': [adamNftPolicy, shardsPolicy, agentPolicy],
      };

      return result;
    } catch (e) {
      return {
        'hasAccess': false,
        'accessLevel': 'error',
        'reason': 'Error checking premium access: $e',
        'details': {},
      };
    }
  }

  /// Helper method to get payment address from stake address
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
}
