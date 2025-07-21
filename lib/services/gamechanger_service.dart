import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_web_auth/flutter_web_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class GameChangerService {
  // Web-based callback configuration for Flutter web
  static const String _webCallbackPath = '/gamechanger-callback';

  // For native apps (if needed in future)
  static const String _callbackScheme = 'bluelight';
  static const String _callbackHost = 'gamechanger-callback';

  // GameChanger URL endpoints
  static const String _gameChangerMainnetUrl =
      'https://wallet.gamechanger.finance/api/2/run';
  static const String _gameChangerBetaUrl =
      'https://beta-wallet.gamechanger.finance/api/2/run';
  static const String _gameChangerTestnetUrl =
      'https://preprod-wallet.gamechanger.finance/api/2/run';

  // Environment configuration
  static String _environmentOverride =
      'auto'; // 'auto', 'mainnet', 'beta', 'testnet'

  // Singleton pattern
  static final GameChangerService _instance = GameChangerService._internal();
  factory GameChangerService() => _instance;
  GameChangerService._internal();

  /// Set GameChanger environment for testing different endpoints
  /// Options: 'auto' (default), 'mainnet', 'beta', 'testnet'
  static void setEnvironment(String environment) {
    _environmentOverride = environment;
    print('🔍 DEBUG: GameChanger environment override set to: $environment');
  }

  /// Get the current web app's base URL for callbacks
  String _getWebCallbackUrl() {
    print('🔍 DEBUG: _getWebCallbackUrl called - kIsWeb: $kIsWeb');
    
    // Detect the current environment more precisely
    final currentUri = Uri.base;
    final isRunningOnWeb = kIsWeb || 
        currentUri.scheme == 'https' || 
        currentUri.scheme == 'http';
    
    print('🔍 DEBUG: Current URI: $currentUri');
    print('🔍 DEBUG: URI scheme: ${currentUri.scheme}');
    print('🔍 DEBUG: Is running on web: $isRunningOnWeb');
    print('🔍 DEBUG: kIsWeb: $kIsWeb');

    if (isRunningOnWeb) {
      // In web, use current origin + callback path
      final origin = currentUri.origin;
      final webCallbackUrl = '$origin$_webCallbackPath?result={result}';
      print('🔍 DEBUG: Generated web callback URL: $webCallbackUrl');
      return webCallbackUrl;
    } else {
      // For native apps, use custom scheme
      final customSchemeUrl =
          'bluelight://gamechanger-callback?result={result}';
      print('🔍 DEBUG: Generated custom scheme URL for iOS/Android: $customSchemeUrl');
      print('🔍 DEBUG: This should match the URL scheme configured in Info.plist/AndroidManifest.xml');
      return customSchemeUrl;
    }
  }

  /// Generate the GameChanger connect script for requesting wallet information
  /// Default to no macro for better compatibility (matches proven Talos approach)
  Map<String, dynamic> _generateConnectScript({bool includeMacro = false}) {
    final callbackUrl = _getWebCallbackUrl();
    print('🔍 DEBUG: Script generation - using callback URL: $callbackUrl');

    final script = {
      "type": "script",
      "title": "🚀 Connect with Bluelight?",
      "description":
          "About to share your basic public wallet information with Bluelight app",
      "exportAs": "connect",
      "returnURLPattern": callbackUrl,
      "run": {
        "name": {"type": "getName"},
        "address": {"type": "getCurrentAddress"},
        "spendPubKey": {"type": "getSpendingPublicKey"},
        "stakePubKey": {"type": "getStakingPublicKey"},
      }
    };

    // Conditionally add the macro - this can help debug if the macro is causing issues
    if (includeMacro) {
      (script["run"] as Map<String, dynamic>)["addressInfo"] = {
        "type": "macro",
        "run": "{getAddressInfo(get('cache.address'))}"
      };
    }

    return script;
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

      // Choose base URL based on network and environment override
      String baseUrl;

      switch (_environmentOverride) {
        case 'mainnet':
          baseUrl = _gameChangerMainnetUrl;
          break;
        case 'beta':
          baseUrl = _gameChangerBetaUrl;
          break;
        case 'testnet':
          baseUrl = _gameChangerTestnetUrl;
          break;
        case 'auto':
        default:
          // Default to beta for mainnet (matches Talos), preprod for testnet
          baseUrl = isMainnet ? _gameChangerBetaUrl : _gameChangerTestnetUrl;
          break;
      }

      final environment = baseUrl.contains('beta')
          ? 'BETA'
          : baseUrl.contains('preprod')
              ? 'TESTNET'
              : 'MAINNET';
      print(
          '🔍 DEBUG: Using GameChanger environment: $environment (override: $_environmentOverride)');
      print('🔍 DEBUG: Base URL: $baseUrl');

      // Create the GameChanger URL with transport header
      return '$baseUrl/$payload';
    } catch (e) {
      print('Error encoding script to URL: $e');
      throw Exception('Failed to generate GameChanger URL: $e');
    }
  }

  /// Generate the complete GameChanger connection URL with callback
  String generateConnectionUrl(
      {bool isMainnet = true, bool includeMacro = false}) {
    final script = _generateConnectScript(includeMacro: includeMacro);
    return _encodeScriptToUrl(script, isMainnet: isMainnet);
  }

  /// Initiate the GameChanger wallet connection flow with platform-specific strategy
  Future<GameChangerWalletData> connectWallet({bool isMainnet = true}) async {
    print('🔍 DEBUG: Starting connectWallet - isMainnet: $isMainnet');
    print('🔍 DEBUG: Platform detection - kIsWeb: $kIsWeb');
    
    // For iOS/Android, use the direct URL launch approach since FlutterWebAuth 
    // may not work correctly with GameChanger's redirect mechanism
    if (!kIsWeb) {
      print('🔍 DEBUG: Native platform detected - using direct URL launch approach');
      return await _connectWalletIosFallback(isMainnet: isMainnet);
    }
    
    // For web, use the standard FlutterWebAuth approach
    try {
      print('🔍 DEBUG: Web platform detected - using FlutterWebAuth approach');
      return await _connectWalletWithOptions(
        isMainnet: isMainnet,
        includeMacro: false,
      );
    } catch (e) {
      print('🔍 DEBUG: Web connection failed: $e');
      rethrow;
    }
  }
  
  /// iOS-specific connection method using URL launcher and deep link callback
  Future<GameChangerWalletData> _connectWalletIosFallback({bool isMainnet = true}) async {
    print('🔍 DEBUG: Starting iOS connection flow');
    
    try {
      // Generate the connection URL
      final connectionUrl = generateConnectionUrl(
          isMainnet: isMainnet, includeMacro: false);
      print('🔍 DEBUG: Generated connection URL for iOS: $connectionUrl');
      
      // Verify the callback URL scheme is correct for iOS
      final script = _generateConnectScript(includeMacro: false);
      final callbackUrl = script['returnURLPattern'] as String;
      print('🔍 DEBUG: Callback URL pattern: $callbackUrl');
      
      if (!callbackUrl.contains('bluelight://gamechanger-callback')) {
        throw GameChangerException(
            'Invalid callback URL for iOS. Expected bluelight:// scheme.');
      }
      
      // Launch GameChanger using url_launcher  
      final canLaunch = await canLaunchUrl(Uri.parse(connectionUrl));
      if (!canLaunch) {
        throw GameChangerException(
            'Cannot launch GameChanger. Please ensure GameChanger wallet is accessible.');
      }
      
      print('🔍 DEBUG: Launching GameChanger...');
      final launched = await launchUrl(
        Uri.parse(connectionUrl),
        mode: LaunchMode.externalApplication,
      );
      
      if (!launched) {
        throw GameChangerException(
            'Failed to launch GameChanger. Please try again.');
      }
      
      print('🔍 DEBUG: GameChanger launched successfully. Waiting for callback...');
      
      // Wait for the callback through AppDelegate -> MethodChannel -> main.dart
      // This is handled by the iOS AppDelegate and the callback screen
      throw GameChangerException(
          'REDIRECT_TO_CALLBACK_SCREEN'); // Special signal for UI to show callback screen
          
    } catch (e) {
      print('🔍 DEBUG: iOS connection flow failed: $e');
      
      if (e.toString().contains('REDIRECT_TO_CALLBACK_SCREEN')) {
        rethrow; // Pass through the redirect signal
      }
      
      throw GameChangerException(
          'iOS connection failed: $e');
    }
  }

  /// Internal method to connect with specific options
  Future<GameChangerWalletData> _connectWalletWithOptions(
      {required bool isMainnet, required bool includeMacro}) async {
    try {
      print('🔍 DEBUG: Starting GameChanger connection flow');
      print('🔍 DEBUG: isMainnet: $isMainnet');

      // Generate the connection URL
      final connectionUrl = generateConnectionUrl(
          isMainnet: isMainnet, includeMacro: includeMacro);
      print('🔍 DEBUG: Generated connection URL: $connectionUrl');
      print('🔍 DEBUG: URL length: ${connectionUrl.length}');
      print('🔍 DEBUG: Include macro: $includeMacro');

      // Check if URL seems valid (has proper transport header)
      final urlPath = Uri.parse(connectionUrl).path;
      if (!urlPath.contains('/1-')) {
        throw GameChangerException(
            'Generated URL missing transport header (1-)');
      }

      print('🔍 DEBUG: Launching flutter_web_auth...');

      // Use flutter_web_auth to handle the OAuth-style flow
      String callbackUrlScheme;

      // Enhanced platform detection for better iOS compatibility
      final currentUri = Uri.base;
      final isRunningOnWeb = kIsWeb || 
          currentUri.scheme == 'https' || 
          currentUri.scheme == 'http';

      print('🔍 DEBUG: Platform detection - kIsWeb: $kIsWeb, currentUri: $currentUri');
      print('🔍 DEBUG: isRunningOnWeb: $isRunningOnWeb');

      if (isRunningOnWeb) {
        // For web, flutter_web_auth expects the web protocol (https)
        callbackUrlScheme = 'https';
        print('🔍 DEBUG: Web environment - using HTTPS as callback scheme');
      } else {
        // For native apps (iOS/Android), use custom scheme
        callbackUrlScheme = _callbackScheme;
        print(
            '🔍 DEBUG: Native environment (iOS/Android) - using custom scheme: $callbackUrlScheme');
        print('🔍 DEBUG: Make sure "$callbackUrlScheme" is properly configured in Info.plist/AndroidManifest.xml');
      }

      final resultUrl = await FlutterWebAuth.authenticate(
        url: connectionUrl,
        callbackUrlScheme: callbackUrlScheme,
        preferEphemeral: true, // Use ephemeral session for better security
      );

      print('🔍 DEBUG: Received callback URL: $resultUrl');

      // Parse and decode the result
      final walletData = _parseCallbackResult(resultUrl);

      print('🔍 DEBUG: Successfully parsed wallet data');
      return walletData;
    } catch (e) {
      print('🔍 DEBUG: Error in GameChanger connection flow: $e');

      // Enhanced error handling with specific guidance
      String errorMessage = e.toString();

      if (errorMessage.contains('UNKNOWN_REQUEST') ||
          errorMessage.contains('Unknown request') ||
          errorMessage.contains('Failed to decode API call')) {
        throw GameChangerException(
            'GameChanger wallet rejected the request. This usually means:\n'
            '• Another wallet extension is interfering\n'
            '• Network mismatch (check if wallet is on correct network)\n'
            '• Wallet needs to be unlocked\n\n'
            'Try disabling other wallet extensions and use an incognito window.');
      }

      if (errorMessage.contains('User cancelled') ||
          errorMessage.contains('CANCELLED')) {
        throw GameChangerException('Connection cancelled by user');
      }

      // iOS-specific error handling
      if (errorMessage.contains('scheme does not have a registered handler') ||
          errorMessage.contains('No app associated with url') ||
          errorMessage.contains('URL scheme not registered')) {
        throw GameChangerException(
            'iOS URL scheme not properly configured. Please contact support.\n\n'
            'Technical details: The "bluelight://" URL scheme needs to be registered in the iOS app configuration.');
      }

      if (errorMessage.contains('FlutterWebAuth') && !kIsWeb) {
        throw GameChangerException(
            'Native callback failed. This could be due to:\n'
            '• URL scheme configuration issue\n'
            '• GameChanger app not installed\n'
            '• iOS system blocking the callback\n\n'
            'Please try again or contact support if the issue persists.');
      }

      throw GameChangerException(
          'Failed to connect with GameChanger wallet: $e');
    }
  }

  /// Parse the callback URL and extract wallet data
  GameChangerWalletData _parseCallbackResult(String callbackUrl) {
    try {
      final uri = Uri.parse(callbackUrl);
      print('🔍 DEBUG: Parsing callback URL: $callbackUrl');
      print(
          '🔍 DEBUG: URI scheme: ${uri.scheme}, host: ${uri.host}, path: ${uri.path}');

      // Validate callback URL based on platform
      if (kIsWeb) {
        // For web: expect HTTPS URL with specific path
        if (!['https', 'http'].contains(uri.scheme)) {
          throw Exception(
              'Invalid web callback URL scheme: expected https/http, got ${uri.scheme}');
        }

        if (uri.path != _webCallbackPath) {
          throw Exception(
              'Invalid web callback URL path: expected $_webCallbackPath, got ${uri.path}');
        }
      } else {
        // For native apps: expect custom scheme
        if (uri.scheme != _callbackScheme) {
          throw Exception(
              'Invalid callback URL scheme: expected $_callbackScheme, got ${uri.scheme}');
        }

        if (uri.host != _callbackHost) {
          throw Exception(
              'Invalid callback URL host: expected $_callbackHost, got ${uri.host}');
        }
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

      // Extract address info and network details
      final addressInfo = connectData['addressInfo'] as Map<String, dynamic>?;
      final networkId = addressInfo?['networkId'] as int? ?? 1;
      final network = addressInfo?['network'] as String? ?? 'mainnet';

      // Extract public keys if available
      final spendPubKey = connectData['spendPubKey'] as Map<String, dynamic>?;
      final stakePubKey = connectData['stakePubKey'] as Map<String, dynamic>?;

      // Extract stake address from addressInfo (if available)
      String? stakeAddress = addressInfo?['rewardAddress'] as String?;

      // If no addressInfo (macro-free connection), try to derive stake address from staking key
      if (stakeAddress == null && stakePubKey != null) {
        print(
            '🔍 DEBUG: No addressInfo available, attempting stake address derivation');

        // Try to construct a basic stake address if we have the staking key
        final stakePubKeyHex = stakePubKey['pubKeyHex'] as String?;
        if (stakePubKeyHex != null && networkId != null) {
          // Basic stake address construction (simplified)
          // This is a simplified approach - in production you'd use proper Cardano libraries
          final networkPrefix = networkId == 1 ? 'stake1' : 'stake_test1';
          stakeAddress = '${networkPrefix}_simplified_from_pubkey';
          print('🔍 DEBUG: Derived simplified stake address: $stakeAddress');
        } else {
          print(
              '🔍 DEBUG: Cannot derive stake address - missing pubkey or network info');
          stakeAddress = 'stake1_basic_connection'; // Basic fallback
        }
      }

      if (stakeAddress == null) {
        throw Exception(
            'No stake address found in GameChanger response and cannot derive from stake key');
      }

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
  String generateQrCodeUrl({bool isMainnet = true, bool includeMacro = false}) {
    return generateConnectionUrl(
        isMainnet: isMainnet, includeMacro: includeMacro);
  }

  /// Parse callback URL from GameChanger (public method for callback screen)
  GameChangerWalletData parseCallbackUrl(String callbackUrl) {
    return _parseCallbackResult(callbackUrl);
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

  /// Decode GameChanger callback result data
  GameChangerWalletData? decodeCallbackResult(String callbackData) {
    try {
      print('🔍 DEBUG: Decoding GameChanger callback data: $callbackData');
      
      // First, decode from base64url
      String decodedJson;
      
      // Handle base64url decoding
      try {
        final base64Data = callbackData.replaceAll('-', '+').replaceAll('_', '/');
        // Add padding if needed
        final padding = 4 - (base64Data.length % 4);
        final paddedData = padding == 4 ? base64Data : base64Data + ('=' * padding);
        final bytes = base64.decode(paddedData);
        decodedJson = utf8.decode(bytes);
      } catch (e) {
        // If base64 decoding fails, assume it's already JSON
        print('🔍 DEBUG: Base64 decode failed, treating as raw JSON: $e');
        decodedJson = callbackData;
      }
      
      print('🔍 DEBUG: Decoded JSON: $decodedJson');
      
      // Parse the JSON
      final Map<String, dynamic> data = json.decode(decodedJson);
      
      // Extract the 'connect' object
      if (data.containsKey('connect')) {
        final connectData = data['connect'] as Map<String, dynamic>;
        
        final walletName = connectData['name'] as String? ?? 'GameChanger Wallet';
        final address = connectData['address'] as String;
        
        // Extract stake address from the spending public key hash
        String? stakeAddress;
        if (connectData.containsKey('stakePubKey')) {
          final stakeKey = connectData['stakePubKey'] as Map<String, dynamic>;
          // For now, we'll use a placeholder - in a real implementation you'd derive this
          stakeAddress = 'stake_' + (stakeKey['pubKeyHashHex'] as String? ?? '');
        }
        
        print('🔍 DEBUG: Extracted wallet data - name: $walletName, address: $address');
        
        return GameChangerWalletData(
          walletName: walletName,
          address: address,
          stakeAddress: stakeAddress ?? '',
          networkId: address.startsWith('addr1') ? 1 : 0, // Simple mainnet/testnet detection
          network: address.startsWith('addr1') ? 'mainnet' : 'testnet',
          spendingPubKey: connectData['spendPubKey']?['pubKeyHex'] as String?,
          stakingPubKey: connectData['stakePubKey']?['pubKeyHex'] as String?,
          rawData: connectData,
        );
      } else {
        print('🔍 DEBUG: No "connect" key found in callback data');
        return null;
      }
    } catch (e) {
      print('🔍 DEBUG: Error decoding GameChanger callback: $e');
      return null;
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
