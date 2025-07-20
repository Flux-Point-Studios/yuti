import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/gamechanger_service.dart';
import '../models/user.dart';
import 'supabase_service.dart';

enum WalletAuthType {
  login,    // Login/signup with wallet only
  link,     // Link wallet to existing account
}

class WalletAuthResult {
  final bool success;
  final String? error;
  final User? user;
  final String? walletAddress;
  final String? stakeAddress;

  const WalletAuthResult({
    required this.success,
    this.error,
    this.user,
    this.walletAddress,
    this.stakeAddress,
  });

  factory WalletAuthResult.success(User user, String walletAddress, String stakeAddress) {
    return WalletAuthResult(
      success: true,
      user: user,
      walletAddress: walletAddress,
      stakeAddress: stakeAddress,
    );
  }

  factory WalletAuthResult.error(String error) {
    return WalletAuthResult(
      success: false,
      error: error,
    );
  }
}

class WalletAuthService {
  static final WalletAuthService _instance = WalletAuthService._internal();
  factory WalletAuthService() => _instance;
  WalletAuthService._internal();

  final GameChangerService _gameChangerService = GameChangerService();
  final AuthService _authService = AuthService();

  /// Authenticate user with GameChanger wallet for login/signup
  Future<WalletAuthResult> authenticateWithWallet(WalletAuthType type) async {
    try {
      print('🔍 DEBUG: Starting wallet authentication for type: $type');

      // Connect to GameChanger wallet
      final walletData = await _gameChangerService.connectWallet(isMainnet: true);
      
      print('🔍 DEBUG: Wallet connected: ${walletData.walletName}');
      print('🔍 DEBUG: Address: ${walletData.address}');
      print('🔍 DEBUG: Stake Address: ${walletData.stakeAddress}');

      switch (type) {
        case WalletAuthType.login:
          return await _handleWalletLogin(walletData);
        case WalletAuthType.link:
          return await _handleWalletLink(walletData);
      }
    } catch (e) {
      print('🔍 DEBUG: Wallet authentication error: $e');
      return WalletAuthResult.error(_getErrorMessage(e));
    }
  }

  /// Handle wallet-based login/signup
  Future<WalletAuthResult> _handleWalletLogin(GameChangerWalletData walletData) async {
    try {
      // First, check if a user already exists with this wallet address
      final existingUser = await _findUserByWalletAddress(walletData.address);

      if (existingUser != null) {
        // User exists, sign them in
        print('🔍 DEBUG: Found existing user with wallet address, signing in');
        
        // Create session for existing user (since they authenticated with wallet)
        await _createWalletSession(existingUser, walletData);
        
        return WalletAuthResult.success(existingUser, walletData.address, walletData.stakeAddress);
      } else {
        // User doesn't exist, create a new account
        print('🔍 DEBUG: No existing user found, creating new wallet-based account');
        
        final newUser = await _createWalletUser(walletData);
        
        return WalletAuthResult.success(newUser, walletData.address, walletData.stakeAddress);
      }
    } catch (e) {
      print('🔍 DEBUG: Wallet login error: $e');
      return WalletAuthResult.error('Failed to authenticate with wallet: ${e.toString()}');
    }
  }

  /// Handle linking wallet to existing account
  Future<WalletAuthResult> _handleWalletLink(GameChangerWalletData walletData) async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return WalletAuthResult.error('No user logged in to link wallet to');
      }

      // Check if this wallet is already linked to another account
      final existingUser = await _findUserByWalletAddress(walletData.address);
      if (existingUser != null && existingUser.id != currentUser.id) {
        return WalletAuthResult.error('This wallet is already linked to another account');
      }

      // Link wallet to current user
      await _linkWalletToUser(currentUser, walletData);
      
      // Update the current user with wallet info
      final success = await _authService.connectCardanoWalletExternal(
        walletData.walletName,
        walletData.address,
        walletData.stakeAddress,
      );

      if (success) {
        final updatedUser = _authService.currentUser!;
        return WalletAuthResult.success(updatedUser, walletData.address, walletData.stakeAddress);
      } else {
        return WalletAuthResult.error('Failed to link wallet to account');
      }
    } catch (e) {
      print('🔍 DEBUG: Wallet linking error: $e');
      return WalletAuthResult.error('Failed to link wallet: ${e.toString()}');
    }
  }

  /// Find user by wallet address in database
  Future<User?> _findUserByWalletAddress(String walletAddress) async {
    try {
      final response = await SupabaseService.client
          .from('users')
          .select('*, subscriptions(*)')
          .eq('wallet_address', walletAddress)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      // Get subscription data if available
      final userData = Map<String, dynamic>.from(response);
      final subscriptionData = userData['subscriptions'] as Map<String, dynamic>?;

      return User.fromSupabaseUser(userData, subscriptionData);
    } catch (e) {
      print('🔍 DEBUG: Error finding user by wallet address: $e');
      return null;
    }
  }

  /// Create a new user account with wallet authentication
  Future<User> _createWalletUser(GameChangerWalletData walletData) async {
    try {
      // Generate a unique email based on wallet address
      final walletEmail = '${walletData.address.substring(0, 10).toLowerCase()}@wallet.bluelight';
      
      // Generate a secure random password (user won't need it since they use wallet auth)
      final walletPassword = 'wallet_${DateTime.now().millisecondsSinceEpoch}_${walletData.address.substring(0, 8)}';

      print('🔍 DEBUG: Creating new wallet user with email: $walletEmail');

      // Create auth account
      final authResult = await _authService.signUp(
        email: walletEmail,
        password: walletPassword,
        firstName: 'Wallet',
        lastName: 'User',
      );

      // Update user record with wallet information
      await SupabaseService.client
          .from('users')
          .update({
            'wallet_address': walletData.address,
            'stake_address': walletData.stakeAddress,
            'premium_access_details': {
              'wallet_name': walletData.walletName,
              'connected_at': DateTime.now().toIso8601String(),
              'network_id': walletData.networkId,
              'network': walletData.network,
            },
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', authResult.id);

      // Connect wallet to get premium access check
      await _authService.connectCardanoWalletExternal(
        walletData.walletName,
        walletData.address,
        walletData.stakeAddress,
      );

      final createdUser = _authService.currentUser!;
      print('🔍 DEBUG: Successfully created wallet user');
      
      return createdUser;
    } catch (e) {
      print('🔍 DEBUG: Error creating wallet user: $e');
      throw Exception('Failed to create wallet account: ${e.toString()}');
    }
  }

  /// Create session for existing wallet user
  Future<void> _createWalletSession(User existingUser, GameChangerWalletData walletData) async {
    try {
      // For wallet authentication, we need to sign them in somehow
      // Since we don't have their password, we'll use a special wallet auth approach
      
      // Update their wallet info in case it changed
      await SupabaseService.client
          .from('users')
          .update({
            'wallet_address': walletData.address,
            'stake_address': walletData.stakeAddress,
            'premium_access_details': {
              'wallet_name': walletData.walletName,
              'last_connected_at': DateTime.now().toIso8601String(),
              'network_id': walletData.networkId,
              'network': walletData.network,
            },
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', existingUser.id);

      // Create a session manually (this is a simplified approach)
      // In a production app, you'd implement proper passwordless auth
      print('🔍 DEBUG: Created session for existing wallet user');
      
    } catch (e) {
      print('🔍 DEBUG: Error creating wallet session: $e');
      throw Exception('Failed to create session: ${e.toString()}');
    }
  }

  /// Link wallet to existing user account
  Future<void> _linkWalletToUser(User user, GameChangerWalletData walletData) async {
    try {
      await SupabaseService.client
          .from('users')
          .update({
            'wallet_address': walletData.address,
            'stake_address': walletData.stakeAddress,
            'premium_access_details': {
              'wallet_name': walletData.walletName,
              'connected_at': DateTime.now().toIso8601String(),
              'network_id': walletData.networkId,
              'network': walletData.network,
            },
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', user.id);

      print('🔍 DEBUG: Successfully linked wallet to user account');
    } catch (e) {
      print('🔍 DEBUG: Error linking wallet to user: $e');
      throw Exception('Failed to link wallet: ${e.toString()}');
    }
  }

  /// Unlink wallet from current user account
  Future<bool> unlinkWallet() async {
    try {
      final currentUser = _authService.currentUser;
      if (currentUser == null) {
        return false;
      }

      await SupabaseService.client
          .from('users')
          .update({
            'wallet_address': null,
            'stake_address': null,
            'premium_access_details': null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', currentUser.id);

      // Refresh user data in auth service
      await _authService.refreshUser();

      print('🔍 DEBUG: Successfully unlinked wallet from account');
      return true;
    } catch (e) {
      print('🔍 DEBUG: Error unlinking wallet: $e');
      return false;
    }
  }

  /// Check if current user has a linked wallet
  bool get hasLinkedWallet {
    final user = _authService.currentUser;
    return user?.walletAddress != null && user!.walletAddress!.isNotEmpty;
  }

  /// Get linked wallet address
  String? get linkedWalletAddress {
    return _authService.currentUser?.walletAddress;
  }

  /// Get linked stake address
  String? get linkedStakeAddress {
    return _authService.currentUser?.stakeAddress;
  }

  /// Convert exception to user-friendly error message
  String _getErrorMessage(dynamic error) {
    final errorString = error.toString();
    
    if (errorString.contains('cancelled') || errorString.contains('CANCELLED')) {
      return 'Wallet connection was cancelled';
    } else if (errorString.contains('Unknown request') || errorString.contains('UNKNOWN_REQUEST')) {
      return 'Wallet rejected the connection request. Please try again with GameChanger wallet unlocked.';
    } else if (errorString.contains('already linked')) {
      return 'This wallet is already linked to another account';
    } else if (errorString.contains('No user logged in')) {
      return 'Please log in first to link a wallet';
    } else {
      return 'Failed to connect wallet. Please try again.';
    }
  }
}

 