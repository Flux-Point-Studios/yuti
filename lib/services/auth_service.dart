import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../models/user.dart';
import 'supabase_service.dart';
import 'cardano_wallet_service.dart';
import 'gamification_service.dart';

class AuthService {
  static const String _userKey = 'current_user';
  static const String _sessionKey = 'auth_session';

  static const _storage = FlutterSecureStorage();

  // Singleton pattern
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  User? _currentUser;
  Session? _currentSession;
  final CardanoWalletService _cardanoWalletService = CardanoWalletService();

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null && _currentSession != null;
  bool get isCardanoWalletConnected => _cardanoWalletService.isConnected;

  SupabaseClient get _supabase => SupabaseService.client;

  Future<void> initialize() async {
    await _loadUserSession();
    _setupAuthListener();
  }

  void _setupAuthListener() {
    _supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      if (event == AuthChangeEvent.signedIn && session != null) {
        _currentSession = session;
        _fetchUserData();
      } else if (event == AuthChangeEvent.signedOut) {
        _currentUser = null;
        _currentSession = null;
        _clearUserSession();
      }
    });
  }

  Future<void> _loadUserSession() async {
    try {
      final userJson = await _storage.read(key: _userKey);
      final sessionJson = await _storage.read(key: _sessionKey);

      if (userJson != null) {
        _currentUser = User.fromJson(json.decode(userJson));
      }

      // Check if we have a persisted session in Supabase
      final session = _supabase.auth.currentSession;
      if (session != null) {
        _currentSession = session;
        // Refresh user data from server
        await _fetchUserData();
      }
    } catch (e) {
      print('Error loading user session: $e');
      await _clearUserSession();
    }
  }

  Future<void> _saveUserSession() async {
    try {
      if (_currentUser != null) {
        await _storage.write(
            key: _userKey, value: json.encode(_currentUser!.toJson()));
      }
    } catch (e) {
      print('Error saving user session: $e');
    }
  }

  Future<void> _updateUserInDatabase() async {
    if (_currentUser == null) return;
    
    try {
      await SupabaseService.client
          .from('users')
          .update({
            'wallet_address': _currentUser!.walletAddress,
            'stake_address': _currentUser!.stakeAddress,
            'premium_access_details': _currentUser!.premiumAccessDetails,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', _currentUser!.id);
      
      print('User wallet data updated in database successfully');
    } catch (e) {
      print('Error updating user wallet data in database: $e');
      // Don't throw - we want the wallet connection to succeed even if DB update fails
    }
  }

  Future<void> _clearUserSession() async {
    try {
      await _storage.delete(key: _userKey);
      await _storage.delete(key: _sessionKey);
    } catch (e) {
      print('Error clearing user session: $e');
    }
  }

  Future<void> _fetchUserData() async {
    try {
      if (_currentSession?.user.id == null) return;

      final userId = _currentSession!.user.id;

      // Fetch user data from users table
      final userResponse =
          await _supabase.from('users').select('*').eq('id', userId).single();

      // Fetch subscription data
      final subscriptionResponse = await _supabase
          .from('subscriptions')
          .select('*')
          .eq('user_id', userId)
          .maybeSingle();

      _currentUser = User.fromSupabaseUser(
        userResponse,
        subscriptionResponse,
      );

      await _saveUserSession();
    } catch (e) {
      print('Error fetching user data: $e');
      // If we can't fetch user data, create basic user from session
      if (_currentSession?.user != null) {
        _currentUser = User(
          id: _currentSession!.user.id,
          email: _currentSession!.user.email ?? '',
          tier: 'FREE',
          createdAt: DateTime.now(),
        );
        await _saveUserSession();
      }
    }
  }

  Future<User> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
  }) async {
    try {
      // On web, direct email confirmation and magic/OTP links back to our in-app handler
      final emailRedirect = Uri.base.origin + '/auth-callback';
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'first_name': firstName,
          'last_name': lastName,
        },
        emailRedirectTo: emailRedirect,
      );

      if (response.user != null) {
        // Wait for the session to be properly established
        await Future.delayed(const Duration(milliseconds: 100));
        
        // Set the current session immediately
        _currentSession = response.session;
        
        try {
          // Create user record in our users table using RPC function to bypass RLS
          await _supabase.rpc('create_user_profile', params: {
            'user_id': response.user!.id,
            'user_email': email,
          });
        } catch (rpcError) {
          print('RPC function failed, trying direct insert: $rpcError');
          // Fallback to direct insert with proper auth context
          try {
            await _supabase.from('users').insert({
              'id': response.user!.id,
              'email': email,
              'customer_id': null, // Will be set when they subscribe
              'created_at': DateTime.now().toIso8601String(),
            });

            // Create FREE subscription record
            await _supabase.from('subscriptions').insert({
              'user_id': response.user!.id,
              'tier': 'FREE',
              'status': 'active',
              'created_at': DateTime.now().toIso8601String(),
            });
          } catch (insertError) {
            print('Direct insert failed: $insertError');
            // If both RPC and direct insert fail, create a basic user object
            // The database triggers should handle user profile creation
            _currentUser = User(
              id: response.user!.id,
              email: email,
              tier: 'FREE',
              createdAt: DateTime.now(),
            );
            await _saveUserSession();
            return _currentUser!;
          }
        }

        // Fetch complete user data
        await _fetchUserData();
        return _currentUser!;
      } else {
        throw Exception('Failed to create user account');
      }
    } catch (e) {
      print('Signup error: $e');
      throw Exception('Signup failed: ${e.toString()}');
    }
  }

  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null && response.session != null) {
        _currentSession = response.session;
        await _fetchUserData();
        return AuthResult.success(_currentUser);
      }

      return AuthResult.error('Failed to sign in');
    } catch (e) {
      print('Signin error: $e');
      return AuthResult.error('Failed to sign in: ${e.toString()}');
    }
  }

  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
      _currentUser = null;
      _currentSession = null;
      await _clearUserSession();
    } catch (e) {
      print('Signout error: $e');
    }
  }

  /// Refresh current user data from database
  Future<void> refreshUser() async {
    if (_currentSession?.user.id != null) {
      await _fetchUserData();
    }
  }

  Future<AuthResult> resetPassword({required String email}) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
      return AuthResult.success(null,
          message: 'Password reset email sent to $email');
    } catch (e) {
      print('Reset password error: $e');
      return AuthResult.error('Failed to send reset email: ${e.toString()}');
    }
  }

  Future<void> updateUserTier(String tier) async {
    try {
      if (_currentUser == null) return;

      // Update subscription in database
      await _supabase.from('subscriptions').update({
        'tier': tier,
        'status': 'active',
        'ended_at': tier != 'FREE'
            ? DateTime.now().add(const Duration(days: 30)).toIso8601String()
            : null,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('user_id', _currentUser!.id);

      // Update local user data
      _currentUser = _currentUser!.copyWith(
        tier: tier,
        subscriptionStatus: 'active',
        endedAt: tier != 'FREE'
            ? DateTime.now().add(const Duration(days: 30))
            : null,
        updatedAt: DateTime.now(),
      );

      await _saveUserSession();
    } catch (e) {
      print('Update tier error: $e');
    }
  }

  // Check subscription status and enforce access
  Future<bool> checkSubscriptionAccess() async {
    if (_currentUser == null) return false;

    // Admin emails have unlimited access
    if (SupabaseService.isAdminEmail(_currentUser!.email)) {
      return true;
    }

    // Check if subscription is active and not expired
    return _currentUser!.hasActiveSubscription && !_currentUser!.hasExpired;
  }

  // Get user tier for feature access
  String getUserTier() {
    return _currentUser?.tier ?? 'FREE';
  }

  // Cardano wallet premium access verification methods

  /// Connect Cardano wallet for premium access verification
  Future<bool> connectCardanoWallet(String mnemonic, String walletName) async {
    if (_currentUser == null) {
      return false;
    }

    try {
      // Create/connect wallet
      final success = await _cardanoWalletService.createWallet(walletName,
          mnemonic: mnemonic);

      if (!success) {
        return false;
      }

      // Check premium access
      final hasPremiumAccess = _cardanoWalletService.hasPremiumAccess;
      final premiumDetails = _cardanoWalletService.premiumAccessDetails;
      final walletAddress = _cardanoWalletService.currentAddress;
      final stakeAddress = _cardanoWalletService.stakeAddress;

      // Update user with wallet info and premium access
      _currentUser = User(
        id: _currentUser!.id,
        email: _currentUser!.email,
        customerId: _currentUser!.customerId,
        tier: hasPremiumAccess ? 'premium' : _currentUser!.tier,
        createdAt: _currentUser!.createdAt,
        updatedAt: DateTime.now(),
        subscriptionId: _currentUser!.subscriptionId,
        subscriptionStatus:
            hasPremiumAccess ? 'active' : _currentUser!.subscriptionStatus,
        endedAt: _currentUser!.endedAt,
        walletAddress: walletAddress,
        stakeAddress: stakeAddress,
        premiumAccessDetails: premiumDetails,
      );

      await _saveUserSession();
      await _updateUserInDatabase(); // Save wallet data to database

      // Award XP for 'Add a wallet'
      try {
        final gami = GamificationService();
        await gami.awardTask('task_add_wallet');
      } catch (_) {}

      return true;
    } catch (e) {
      print('Error connecting Cardano wallet: $e');
      return false;
    }
  }

  /// Connect external Cardano wallet (e.g., GameChanger) for premium access verification
  Future<bool> connectCardanoWalletExternal(String walletName, String address, String stakeAddress) async {
    if (_currentUser == null) {
      return false;
    }

    try {
      // Connect external wallet
      final success = await _cardanoWalletService.connectExternalWallet(walletName, address, stakeAddress);

      if (!success) {
        return false;
      }

      // Check premium access
      final hasPremiumAccess = _cardanoWalletService.hasPremiumAccess;
      final premiumDetails = _cardanoWalletService.premiumAccessDetails;

      // Update user with wallet info and premium access
      _currentUser = User(
        id: _currentUser!.id,
        email: _currentUser!.email,
        customerId: _currentUser!.customerId,
        tier: hasPremiumAccess ? 'premium' : _currentUser!.tier,
        createdAt: _currentUser!.createdAt,
        updatedAt: DateTime.now(),
        subscriptionId: _currentUser!.subscriptionId,
        subscriptionStatus:
            hasPremiumAccess ? 'active' : _currentUser!.subscriptionStatus,
        endedAt: _currentUser!.endedAt,
        walletAddress: address,
        stakeAddress: stakeAddress,
        premiumAccessDetails: premiumDetails,
      );

      await _saveUserSession();
      await _updateUserInDatabase(); // Save wallet data to database

      // Award XP for 'Add a wallet'
      try {
        final gami = GamificationService();
        await gami.awardTask('task_add_wallet');
      } catch (_) {}

      print('External Cardano wallet connected successfully: $walletName');
      return true;
    } catch (e) {
      print('Error connecting external Cardano wallet: $e');
      return false;
    }
  }

  /// Check if current user has premium access via connected Cardano wallet
  Future<bool> refreshCardanoPremiumAccess() async {
    if (_currentUser == null || !_cardanoWalletService.isConnected) {
      return false;
    }

    try {
      // Force refresh premium access check
      await _cardanoWalletService.initialize();

      final hasPremiumAccess = _cardanoWalletService.hasPremiumAccess;
      final premiumDetails = _cardanoWalletService.premiumAccessDetails;

      // Update user premium status
      _currentUser = User(
        id: _currentUser!.id,
        email: _currentUser!.email,
        customerId: _currentUser!.customerId,
        tier: hasPremiumAccess ? 'premium' : _currentUser!.tier,
        createdAt: _currentUser!.createdAt,
        updatedAt: DateTime.now(),
        subscriptionId: _currentUser!.subscriptionId,
        subscriptionStatus:
            hasPremiumAccess ? 'active' : _currentUser!.subscriptionStatus,
        endedAt: _currentUser!.endedAt,
        walletAddress: _currentUser!.walletAddress,
        stakeAddress: _currentUser!.stakeAddress,
        premiumAccessDetails: premiumDetails,
      );

      await _saveUserSession();
      await _updateUserInDatabase(); // Update premium access in database
      return hasPremiumAccess;
    } catch (e) {
      print('Error refreshing Cardano premium access: $e');
      return false;
    }
  }

  /// Get Cardano wallet service instance
  CardanoWalletService get cardanoWalletService => _cardanoWalletService;

  /// Disconnect Cardano wallet (but keep user authentication)
  Future<void> disconnectCardanoWallet() async {
    if (_currentUser != null) {
      await _cardanoWalletService.disconnectWallet();

      // Remove wallet info from user but keep authentication
      _currentUser = User(
        id: _currentUser!.id,
        email: _currentUser!.email,
        customerId: _currentUser!.customerId,
        tier: _currentUser!.tier,
        createdAt: _currentUser!.createdAt,
        updatedAt: DateTime.now(),
        subscriptionId: _currentUser!.subscriptionId,
        subscriptionStatus: _currentUser!.subscriptionStatus,
        endedAt: _currentUser!.endedAt,
        walletAddress: null,
        stakeAddress: null,
        premiumAccessDetails: null,
      );

      await _saveUserSession();
      await _updateUserInDatabase(); // Clear wallet data from database
    }
  }

  // Check if user can access premium features
  bool canAccessPremiumFeatures() {
    if (_currentUser == null) return false;

    // Admin emails have access to everything
    if (SupabaseService.isAdminEmail(_currentUser!.email)) {
      return true;
    }

    // Check if user has premium tier (from subscription or Cardano wallet verification)
    if (_currentUser!.tier == 'premium') {
      return true;
    }

    // For users with connected Cardano wallet, check premium access directly
    if (_cardanoWalletService.isConnected) {
      return _cardanoWalletService.hasPremiumAccess;
    }

    // Default subscription check
    return _currentUser!.subscriptionStatus == 'active';
  }
}

class AuthResult {
  final bool isSuccess;
  final User? user;
  final String? error;
  final String? message;

  AuthResult.success(this.user, {this.message})
      : isSuccess = true,
        error = null;

  AuthResult.error(this.error)
      : isSuccess = false,
        user = null,
        message = null;
}
