import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'app_config.dart';

// Secure configuration service for managing API keys
// Based on research document's security recommendations
class SecureConfig {
  static const String _blockfrostKeyName = 'blockfrost_api_key';
  static const String _tBackendKeyName = 't_backend_api_key';
  static const String _uexClientIdName = 'uex_client_id';
  static const String _uexSecretKeyName = 'uex_secret_key';
  
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final AppConfig _appConfig = AppConfig();
  
  // Singleton pattern
  static final SecureConfig _instance = SecureConfig._internal();
  factory SecureConfig() => _instance;
  SecureConfig._internal();
  
  // Initialize with API keys (called once during setup)
  Future<void> initializeKeys({
    String? blockfrostKey,
    String? tBackendKey,
    String? uexClientId,
    String? uexSecretKey,
  }) async {
    if (blockfrostKey != null) {
      await _storage.write(key: _blockfrostKeyName, value: blockfrostKey);
    }
    if (tBackendKey != null) {
      await _storage.write(key: _tBackendKeyName, value: tBackendKey);
    }
    if (uexClientId != null) {
      await _storage.write(key: _uexClientIdName, value: uexClientId);
    }
    if (uexSecretKey != null) {
      await _storage.write(key: _uexSecretKeyName, value: uexSecretKey);
    }
  }
  
  // Get Blockfrost API key
  Future<String> getBlockfrostApiKey() async {
    // First try secure storage
    final storedKey = await _storage.read(key: _blockfrostKeyName);
    if (storedKey != null && storedKey.isNotEmpty) {
      return storedKey;
    }
    
    // Fall back to environment variable (for development)
    final envKey = _appConfig.blockfrostApiKey;
    if (envKey.isNotEmpty && envKey != 'demo') {
      return envKey;
    }
    
    // If no key available, throw error
    throw Exception('Blockfrost API key not configured');
  }
  
  // Get T-Backend API key
  Future<String> getTBackendApiKey() async {
    final storedKey = await _storage.read(key: _tBackendKeyName);
    if (storedKey != null && storedKey.isNotEmpty) {
      return storedKey;
    }
    
    final envKey = _appConfig.tBackendApiKey;
    if (envKey.isNotEmpty) {
      return envKey;
    }
    
    throw Exception('T-Backend API key not configured');
  }
  
  // Get UEX credentials
  Future<Map<String, String>> getUEXCredentials() async {
    final clientId = await _storage.read(key: _uexClientIdName) ?? _appConfig.uexClientId;
    final secretKey = await _storage.read(key: _uexSecretKeyName) ?? _appConfig.uexSecretKey;
    
    if (clientId.isEmpty || secretKey.isEmpty) {
      throw Exception('UEX credentials not configured');
    }
    
    return {
      'clientId': clientId,
      'secretKey': secretKey,
    };
  }
  
  // Check if API keys are configured
  Future<bool> hasRequiredKeys() async {
    try {
      await getBlockfrostApiKey();
      await getTBackendApiKey();
      return true;
    } catch (e) {
      return false;
    }
  }
  
  // Clear all stored keys (for logout/reset)
  Future<void> clearKeys() async {
    await _storage.delete(key: _blockfrostKeyName);
    await _storage.delete(key: _tBackendKeyName);
    await _storage.delete(key: _uexClientIdName);
    await _storage.delete(key: _uexSecretKeyName);
  }
  
  // For production: fetch keys from backend
  Future<void> fetchKeysFromBackend(String userToken) async {
    // Research document recommends backend proxy for production
    // This method would call your backend to get user-specific or
    // app-specific API keys based on authentication
    
    // Example implementation:
    // final response = await http.get(
    //   Uri.parse('${_appConfig.tBackendUrl}/api/keys'),
    //   headers: {'Authorization': 'Bearer $userToken'},
    // );
    // 
    // if (response.statusCode == 200) {
    //   final data = json.decode(response.body);
    //   await initializeKeys(
    //     blockfrostKey: data['blockfrost_key'],
    //     // Don't send other keys from backend - keep them server-side
    //   );
    // }
    
    throw UnimplementedError('Backend key fetching not implemented');
  }
} 