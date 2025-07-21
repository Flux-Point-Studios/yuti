import 'package:local_auth/local_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BiometricAuthService {
  static const String _biometricEnabledKey = 'biometric_auth_enabled';
  static const _storage = FlutterSecureStorage();
  
  final LocalAuthentication _localAuth = LocalAuthentication();
  
  // Singleton pattern
  static final BiometricAuthService _instance = BiometricAuthService._internal();
  factory BiometricAuthService() => _instance;
  BiometricAuthService._internal();

  /// Check if biometric authentication is available on the device
  Future<bool> isBiometricAvailable() async {
    try {
      if (kIsWeb) return false; // Biometric not supported on web
      
      final bool isAvailable = await _localAuth.isDeviceSupported();
      final bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final List<BiometricType> availableBiometrics = await _localAuth.getAvailableBiometrics();
      
      print('🔍 DEBUG: Device supports biometric: $isAvailable');
      print('🔍 DEBUG: Can check biometrics: $canCheckBiometrics');
      print('🔍 DEBUG: Available biometrics: $availableBiometrics');
      
      return isAvailable && canCheckBiometrics && availableBiometrics.isNotEmpty;
    } catch (e) {
      print('🔍 DEBUG: Error checking biometric availability: $e');
      return false;
    }
  }

  /// Get available biometric types (Face ID, Touch ID, etc.)
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      if (kIsWeb) return [];
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      print('🔍 DEBUG: Error getting available biometrics: $e');
      return [];
    }
  }

  /// Get user-friendly name for biometric type
  String getBiometricTypeName(List<BiometricType> types) {
    if (types.contains(BiometricType.face)) {
      return 'Face ID';
    } else if (types.contains(BiometricType.fingerprint)) {
      return 'Touch ID';
    } else if (types.contains(BiometricType.iris)) {
      return 'Iris Scanner';
    } else if (types.contains(BiometricType.strong)) {
      return 'Biometric Authentication';
    } else if (types.contains(BiometricType.weak)) {
      return 'Device Authentication';
    }
    return 'Biometric Authentication';
  }

  /// Check if user has enabled biometric authentication for wallet access
  Future<bool> isBiometricEnabled() async {
    try {
      final String? enabled = await _storage.read(key: _biometricEnabledKey);
      return enabled == 'true';
    } catch (e) {
      print('🔍 DEBUG: Error checking biometric enabled status: $e');
      return false;
    }
  }

  /// Enable or disable biometric authentication for wallet access
  Future<void> setBiometricEnabled(bool enabled) async {
    try {
      await _storage.write(key: _biometricEnabledKey, value: enabled.toString());
      print('🔍 DEBUG: Biometric authentication ${enabled ? 'enabled' : 'disabled'}');
    } catch (e) {
      print('🔍 DEBUG: Error setting biometric enabled status: $e');
    }
  }

  /// Authenticate user with biometrics
  Future<bool> authenticateWithBiometrics({
    required String reason,
    bool fallbackToPasscode = true,
  }) async {
    try {
      if (kIsWeb) {
        print('🔍 DEBUG: Biometric auth not available on web, returning true');
        return true; // Skip biometric on web
      }

      final bool isAvailable = await isBiometricAvailable();
      if (!isAvailable) {
        print('🔍 DEBUG: Biometric not available, returning $fallbackToPasscode');
        return fallbackToPasscode; // If not available, fall back based on parameter
      }

      print('🔍 DEBUG: Attempting biometric authentication...');
      
      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          biometricOnly: !fallbackToPasscode,
          stickyAuth: true,
        ),
      );

      print('🔍 DEBUG: Biometric authentication result: $didAuthenticate');
      return didAuthenticate;
    } catch (e) {
      print('🔍 DEBUG: Biometric authentication error: $e');
      return false;
    }
  }

  /// Authenticate user specifically for wallet access
  Future<bool> authenticateForWalletAccess() async {
    final bool biometricEnabled = await isBiometricEnabled();
    
    if (!biometricEnabled) {
      print('🔍 DEBUG: Biometric not enabled for wallet access, allowing access');
      return true; // If user hasn't enabled biometric, don't block access
    }

    return await authenticateWithBiometrics(
      reason: 'Authenticate to access your wallet',
      fallbackToPasscode: true,
    );
  }

  /// Show biometric setup dialog to user
  Future<bool> promptBiometricSetup() async {
    final bool isAvailable = await isBiometricAvailable();
    if (!isAvailable) {
      return false;
    }

    // This would be called from UI to test biometric and enable it
    final bool canAuthenticate = await authenticateWithBiometrics(
      reason: 'Test biometric authentication for wallet security',
      fallbackToPasscode: false, // Only biometric for setup
    );

    if (canAuthenticate) {
      await setBiometricEnabled(true);
      return true;
    }

    return false;
  }

  /// Reset biometric settings (for debugging or user preference)
  Future<void> resetBiometricSettings() async {
    try {
      await _storage.delete(key: _biometricEnabledKey);
      print('🔍 DEBUG: Biometric settings reset');
    } catch (e) {
      print('🔍 DEBUG: Error resetting biometric settings: $e');
    }
  }
} 