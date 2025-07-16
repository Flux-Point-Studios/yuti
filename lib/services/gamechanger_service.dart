import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_web_auth/flutter_web_auth.dart';
import 'package:url_launcher/url_launcher.dart';

class GameChangerService {
  static const String _callbackScheme = 'bluelight';
  static const String _callbackHost = 'gamechanger-callback';
  static const String _gameChangerBaseUrl =
      'https://wallet.gamechanger.finance/api/2/run';
  static const String _gameChangerTestnetUrl =
      'https://preprod-wallet.gamechanger.finance/api/2/run';

  // Singleton pattern
  static final GameChangerService _instance = GameChangerService._internal();
  factory GameChangerService() => _instance;
  GameChangerService._internal();

  /// Generate the GameChanger connect script for requesting wallet information
  Map<String, dynamic> _generateConnectScript() {
    return {
      "type": "script",
      "title": "🚀 Connect with Bluelight?",
      "description":
          "About to share your basic public wallet information with Bluelight app",
      "exportAs": "connect",
      "returnURLPattern": "bluelight://gamechanger-callback?result={result}",
      "run": {
        "name": {"type": "getName"},
        "address": {"type": "getCurrentAddress"},
        "spendPubKey": {"type": "getSpendingPublicKey"},
        "stakePubKey": {"type": "getStakingPublicKey"},
        "addressInfo": {
          "type": "macro",
          "run": "{getAddressInfo(get('cache.address'))}"
        }
      }
    };
  }

  /// Encode the GCScript into a compressed GameChanger URL
  String _encodeScriptToUrl(Map<String, dynamic> script,
      {bool isMainnet = true}) {
    try {
      // Convert script to JSON string
      final jsonString = json.encode(script);

      // Compress using GZIP
      final jsonBytes = utf8.encode(jsonString);
      final compressedBytes = GZipEncoder().encode(jsonBytes);

      // Encode to base64url (remove padding)
      final encodedData =
          base64Url.encode(compressedBytes!).replaceAll('=', '');

      // Add transport header: 1- indicates gzip + base64url encoding
      final payload = '1-$encodedData';

      // Choose base URL based on network
      final baseUrl = isMainnet ? _gameChangerBaseUrl : _gameChangerTestnetUrl;

      // Create the GameChanger URL with transport header
      return '$baseUrl/$payload';
    } catch (e) {
      print('Error encoding script to URL: $e');
      throw Exception('Failed to generate GameChanger URL: $e');
    }
  }

  /// Generate the complete GameChanger connection URL with callback
  String generateConnectionUrl({bool isMainnet = true}) {
    final script = _generateConnectScript();
    return _encodeScriptToUrl(script, isMainnet: isMainnet);
  }

  /// Initiate the GameChanger wallet connection flow
  Future<GameChangerWalletData> connectWallet({bool isMainnet = true}) async {
    try {
      // Generate the connection URL
      final connectionUrl = generateConnectionUrl(isMainnet: isMainnet);

      // Use flutter_web_auth to handle the OAuth-style flow
      final resultUrl = await FlutterWebAuth.authenticate(
        url: connectionUrl,
        callbackUrlScheme: _callbackScheme,
      );

      // Parse and decode the result
      return _parseCallbackResult(resultUrl);
    } catch (e) {
      print('Error in GameChanger connection flow: $e');
      throw GameChangerException(
          'Failed to connect with GameChanger wallet: $e');
    }
  }

  /// Parse the callback URL and extract wallet data
  GameChangerWalletData _parseCallbackResult(String callbackUrl) {
    try {
      final uri = Uri.parse(callbackUrl);

      // Validate that this is a legitimate GameChanger callback
      if (uri.scheme != _callbackScheme) {
        throw Exception(
            'Invalid callback URL scheme: expected $_callbackScheme, got ${uri.scheme}');
      }

      if (uri.host != _callbackHost) {
        throw Exception(
            'Invalid callback URL host: expected $_callbackHost, got ${uri.host}');
      }

      // Extract the result parameter (could be in query or fragment)
      String? resultData = uri.queryParameters['result'];

      // If not in query params, check fragment
      if (resultData == null && uri.fragment.isNotEmpty) {
        final fragmentParts = uri.fragment.split('result=');
        if (fragmentParts.length > 1) {
          resultData = fragmentParts[1].split('&')[0];
        }
      }

      if (resultData == null) {
        throw Exception('No result data found in callback URL');
      }

      // URL decode the result data
      resultData = Uri.decodeComponent(resultData);

      // Decode the compressed data
      final decodedData = _decodeResultData(resultData);

      // Extract wallet information from the decoded JSON
      return _extractWalletData(decodedData);
    } catch (e) {
      throw GameChangerException('Failed to parse GameChanger response: $e');
    }
  }

  /// Decode the compressed result data from GameChanger
  Map<String, dynamic> _decodeResultData(String encodedData) {
    try {
      // Decode from base64url
      final compressedBytes = base64Url.decode(encodedData);

      // Decompress using GZIP
      final jsonBytes = GZipDecoder().decodeBytes(compressedBytes);

      // Convert to string and parse JSON
      final jsonString = utf8.decode(jsonBytes);
      return json.decode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      print('Error decoding result data: $e');
      throw Exception('Failed to decode GameChanger result data: $e');
    }
  }

  /// Extract wallet data from the decoded GameChanger response
  GameChangerWalletData _extractWalletData(Map<String, dynamic> resultData) {
    try {
      // The result should have an 'exports' field with our 'connect' data
      final exports = resultData['exports'] as Map<String, dynamic>?;
      if (exports == null) {
        throw Exception('No exports found in GameChanger response');
      }

      final connectData = exports['connect'] as Map<String, dynamic>?;
      if (connectData == null) {
        throw Exception('No connect data found in GameChanger response');
      }

      // Extract the required fields
      final walletName = connectData['name'] as String? ?? 'GameChanger Wallet';
      final address = connectData['address'] as String?;

      if (address == null) {
        throw Exception('No address found in GameChanger response');
      }

      // Extract stake address from addressInfo
      final addressInfo = connectData['addressInfo'] as Map<String, dynamic>?;
      final stakeAddress = addressInfo?['rewardAddress'] as String?;
      final networkId = addressInfo?['networkId'] as int? ?? 1;
      final network = addressInfo?['network'] as String? ?? 'mainnet';

      if (stakeAddress == null) {
        throw Exception('No stake address found in GameChanger response');
      }

      // Extract public keys if available
      final spendPubKey = connectData['spendPubKey'] as Map<String, dynamic>?;
      final stakePubKey = connectData['stakePubKey'] as Map<String, dynamic>?;

      return GameChangerWalletData(
        walletName: walletName,
        address: address,
        stakeAddress: stakeAddress,
        networkId: networkId,
        network: network,
        spendingPubKey: spendPubKey?['pubKeyHex'] as String?,
        stakingPubKey: stakePubKey?['pubKeyHex'] as String?,
        rawData: connectData,
      );
    } catch (e) {
      print('Error extracting wallet data: $e');
      throw Exception(
          'Failed to extract wallet data from GameChanger response: $e');
    }
  }

  /// Generate QR code URL for cross-device scanning
  String generateQrCodeUrl({bool isMainnet = true}) {
    return generateConnectionUrl(isMainnet: isMainnet);
  }

  /// Check if GameChanger is available on the device
  Future<bool> isGameChangerAvailable() async {
    try {
      // For now, we assume GameChanger is available since it's a web-based wallet
      // In the future, this could check for installed PWA or specific capabilities
      return true;
    } catch (e) {
      print('Error checking GameChanger availability: $e');
      return false;
    }
  }

  /// Launch GameChanger directly (for cases where flutter_web_auth is not needed)
  Future<bool> launchGameChangerDirect({bool isMainnet = true}) async {
    try {
      final url = generateConnectionUrl(isMainnet: isMainnet);
      final uri = Uri.parse(url);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
      return false;
    } catch (e) {
      print('Error launching GameChanger: $e');
      return false;
    }
  }
}

/// Data class for GameChanger wallet information
class GameChangerWalletData {
  final String walletName;
  final String address;
  final String stakeAddress;
  final int networkId;
  final String network;
  final String? spendingPubKey;
  final String? stakingPubKey;
  final Map<String, dynamic> rawData;

  const GameChangerWalletData({
    required this.walletName,
    required this.address,
    required this.stakeAddress,
    required this.networkId,
    required this.network,
    this.spendingPubKey,
    this.stakingPubKey,
    required this.rawData,
  });

  /// Validate that this wallet data is from the expected network
  bool isMainnet() => networkId == 1 && network == 'mainnet';

  /// Validate that this wallet data is from testnet
  bool isTestnet() => networkId == 0 && network.contains('test');

  @override
  String toString() {
    return 'GameChangerWalletData(name: $walletName, address: $address, stakeAddress: $stakeAddress, network: $network)';
  }
}

/// Custom exception for GameChanger-related errors
class GameChangerException implements Exception {
  final String message;

  const GameChangerException(this.message);

  @override
  String toString() => 'GameChangerException: $message';
}
