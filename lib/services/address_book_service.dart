import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/address_book_entry.dart';
import 'ada_handle_service.dart';
import 'supabase_service.dart';

class AddressBookService {
  static const _storage = FlutterSecureStorage();
  static const String _addressBookKey = 'wallet_address_book';
  static final RegExp _gmailAddressPattern = RegExp(
    r'^[a-z0-9](?:[a-z0-9._%+\-]{0,62})@gmail\.com$',
    caseSensitive: false,
  );

  // Singleton pattern
  static final AddressBookService _instance = AddressBookService._internal();
  factory AddressBookService() => _instance;
  AddressBookService._internal();

  final AdaHandleService _handleService = AdaHandleService();

  List<AddressBookEntry> _entries = [];
  
  List<AddressBookEntry> get entries => List.unmodifiable(_entries);

  /// Normalizes Cardano/Gmail input so lookups stay consistent
  String normalizeRecipient(String input) => _normalizeRecipient(input);

  /// Returns true when the string is a supported recipient (Cardano or Gmail)
  bool isSupportedRecipient(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return false;
    return isValidCardanoAddress(trimmed) || isValidGmailAddress(trimmed);
  }

  bool isValidGmailAddress(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return false;
    return _gmailAddressPattern.hasMatch(trimmed);
  }

  SupabaseClient get _supabase => SupabaseService.client;
  bool get _isLoggedIn => _supabase.auth.currentUser != null;
  String? get _userId => _supabase.auth.currentUser?.id;

  /// Initialize and load existing entries
  Future<void> initialize() async {
    await loadEntries();
  }

  /// Load entries (remote if logged in, else local cache)
  Future<void> loadEntries() async {
    try {
      if (_isLoggedIn) {
        final rows = await _supabase
            .from('address_book')
            .select('*')
            .order('name');
        _entries = (rows as List<dynamic>).map((row) {
          final entry = AddressBookEntry(
            id: row['id'].toString(),
            name: (row['name'] ?? '').toString(),
            address: (row['address'] ?? '').toString(),
            handle: row['handle']?.toString(),
            description: row['description']?.toString(),
            createdAt: DateTime.parse((row['created_at'] ?? DateTime.now().toIso8601String()).toString()),
            lastUsed: row['last_used'] != null ? DateTime.parse(row['last_used'].toString()) : null,
          );
          return _sanitizeEntry(entry);
        }).toList();
        _entries.sort((a, b) => a.name.compareTo(b.name));

        // If remote is empty but local cache exists, bootstrap-sync local -> remote
        if (_entries.isEmpty) {
          try {
            final cached = await _storage.read(key: _addressBookKey);
            if (cached != null) {
              final List<dynamic> cacheList = json.decode(cached);
              final localEntries = cacheList
                  .map((e) => AddressBookEntry.fromJson(e))
                  .map(_sanitizeEntry)
                  .toList();
              if (localEntries.isNotEmpty) {
                final payload = localEntries.map((e) => {
                  'id': e.id,
                  'user_id': _userId!,
                  'name': e.name,
                  'address': e.address,
                  'handle': e.handle,
                  'description': e.description,
                  'created_at': e.createdAt.toIso8601String(),
                  'last_used': e.lastUsed?.toIso8601String(),
                }).toList();
                await _supabase.from('address_book').upsert(payload, onConflict: 'id');
                _entries = localEntries;
                _entries.sort((a, b) => a.name.compareTo(b.name));
              }
            }
          } catch (e) {
            // Silent; best-effort bootstrap
          }
        }
        // Cache for offline use
        await _saveCache();
        return;
      }

      // Fallback: local cache
      final entriesJson = await _storage.read(key: _addressBookKey);
      if (entriesJson != null) {
        final List<dynamic> entriesList = json.decode(entriesJson);
        _entries = entriesList
            .map((json) => AddressBookEntry.fromJson(json))
            .map(_sanitizeEntry)
            .toList();
        _entries.sort((a, b) => a.name.compareTo(b.name));
      }
    } catch (e) {
      print('Error loading address book entries: $e');
      _entries = [];
    }
  }

  Future<void> _saveCache() async {
    try {
      final entriesJson = json.encode(
        _entries.map((entry) => entry.toJson()).toList(),
      );
      await _storage.write(key: _addressBookKey, value: entriesJson);
    } catch (e) {
      print('Error saving address book cache: $e');
    }
  }

  /// Resolve input if it is an ADA Handle; otherwise return input as-is
  Future<Map<String, String>> resolveIfHandle(String input) async {
    final trimmed = input.trim();
    if (_handleService.isHandle(trimmed)) {
      final res = await _handleService.resolveHandle(trimmed);
      if (res != null) {
        final resolvedHandle = res.handle.startsWith('@') ? res.handle : '@${res.handle}';
        return {'address': res.adaAddress, 'handle': resolvedHandle};
      }
    }
    return {'address': trimmed};
  }

  /// Add a new entry
  Future<bool> addEntry(AddressBookEntry entry) async {
    final sanitizedEntry = _sanitizeEntry(entry);

    // Check duplicates locally
    if (_entries.any((e) => _recipientsMatch(e.address, sanitizedEntry.address))) {
      return false;
    }
    if (_entries.any((e) => e.name.toLowerCase() == sanitizedEntry.name.toLowerCase())) {
      return false;
    }

    try {
      if (_isLoggedIn) {
        await _supabase.from('address_book').insert({
          'id': sanitizedEntry.id,
          'user_id': _userId,
          'name': sanitizedEntry.name,
          'address': sanitizedEntry.address,
          'handle': sanitizedEntry.handle,
          'description': sanitizedEntry.description,
          'created_at': sanitizedEntry.createdAt.toIso8601String(),
          'last_used': sanitizedEntry.lastUsed?.toIso8601String(),
        });
      }

      _entries.add(sanitizedEntry);
      _entries.sort((a, b) => a.name.compareTo(b.name));
      await _saveCache();
      return true;
    } catch (e) {
      print('Error adding address book entry: $e');
      return false;
    }
  }

  /// Update an existing entry
  Future<bool> updateEntry(String id, AddressBookEntry updatedEntry) async {
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index == -1) return false;

    final sanitizedEntry = _sanitizeEntry(updatedEntry);

    // Uniqueness checks
    if (_entries.any((e) => e.id != id && e.name.toLowerCase() == sanitizedEntry.name.toLowerCase())) {
      return false;
    }
    if (_entries.any((e) => e.id != id && _recipientsMatch(e.address, sanitizedEntry.address))) {
      return false;
    }

    try {
      if (_isLoggedIn) {
        await _supabase
            .from('address_book')
            .update({
              'name': sanitizedEntry.name,
              'address': sanitizedEntry.address,
              'handle': sanitizedEntry.handle,
              'description': sanitizedEntry.description,
              'last_used': sanitizedEntry.lastUsed?.toIso8601String(),
            })
            .eq('id', id)
            .eq('user_id', _userId!);
      }

      _entries[index] = sanitizedEntry.copyWith(id: id);
      _entries.sort((a, b) => a.name.compareTo(b.name));
      await _saveCache();
      return true;
    } catch (e) {
      print('Error updating address book entry: $e');
      return false;
    }
  }

  /// Delete an entry
  Future<bool> deleteEntry(String id) async {
    final initialLength = _entries.length;
    _entries.removeWhere((entry) => entry.id == id);

    try {
      if (_isLoggedIn) {
        await _supabase.from('address_book').delete().eq('id', id).eq('user_id', _userId!);
      }
      if (_entries.length < initialLength) {
        await _saveCache();
        return true;
      }
      return false;
    } catch (e) {
      print('Error deleting address book entry: $e');
      // Even if server fails, keep local removed to avoid duplicates; cache state
      await _saveCache();
      return _entries.length < initialLength;
    }
  }

  /// Get entry by ID
  AddressBookEntry? getEntryById(String id) {
    try {
      return _entries.firstWhere((entry) => entry.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Get entry by address
  AddressBookEntry? getEntryByAddress(String address) {
    final normalized = _normalizeRecipient(address);
    if (normalized.isEmpty) return null;
    try {
      return _entries.firstWhere((entry) => _recipientsMatch(entry.address, normalized));
    } catch (e) {
      return null;
    }
  }

  /// Search entries by name
  List<AddressBookEntry> searchByName(String query) {
    final lowercaseQuery = query.toLowerCase();
    return _entries.where((entry) {
      final matchesName = entry.name.toLowerCase().contains(lowercaseQuery);
      final matchesAddress = entry.address.toLowerCase().contains(lowercaseQuery);
      final matchesDescription = entry.description?.toLowerCase().contains(lowercaseQuery) ?? false;
      return matchesName || matchesAddress || matchesDescription;
    }).toList();
  }

  /// Update last used timestamp for an entry
  Future<void> updateLastUsed(String address) async {
    final normalized = _normalizeRecipient(address);
    if (normalized.isEmpty) return;
    final index = _entries.indexWhere((entry) => _recipientsMatch(entry.address, normalized));
    if (index != -1) {
      final entry = _entries[index];
      final updated = entry.copyWith(lastUsed: DateTime.now());
      _entries[index] = updated;
      await _saveCache();
      try {
        if (_isLoggedIn) {
          await _supabase
              .from('address_book')
              .update({'last_used': updated.lastUsed!.toIso8601String()})
              .eq('id', entry.id)
              .eq('user_id', _userId!);
        }
      } catch (_) {}
    }
  }

  /// Get recently used entries
  List<AddressBookEntry> getRecentlyUsed({int limit = 5}) {
    final recentEntries = _entries.where((entry) => entry.lastUsed != null).toList()
      ..sort((a, b) => b.lastUsed!.compareTo(a.lastUsed!));
    return recentEntries.take(limit).toList();
  }

  /// Clear all entries (local + remote for current user)
  Future<void> clearEntries() async {
    _entries.clear();
    await _saveCache();
    try {
      if (_isLoggedIn) {
        await _supabase.from('address_book').delete().eq('user_id', _userId!);
      }
    } catch (_) {}
  }

  /// Check if address is valid Cardano address
  bool isValidCardanoAddress(String address) {
    final trimmed = address.trim();
    return trimmed.startsWith('addr1') || trimmed.startsWith('addr_test1');
  }

  /// Provide lightweight contact list for AI context
  List<Map<String, String>> summarizeForContext({int limit = 25}) {
    final list = _entries.take(limit).map((e) => {
      'name': e.name,
      'address': e.address,
      if (e.handle != null) 'handle': e.handle!,
    }).toList();
    return list;
  }

  bool _recipientsMatch(String a, String b) {
    return _normalizeRecipient(a) == _normalizeRecipient(b);
  }

  String _normalizeRecipient(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    if (isValidGmailAddress(trimmed)) {
      return trimmed.toLowerCase();
    }
    return trimmed;
  }

  AddressBookEntry _sanitizeEntry(AddressBookEntry entry) {
    final normalizedAddress = _normalizeRecipient(entry.address);
    final normalizedName = entry.name.trim();
    final normalizedHandle = entry.handle?.trim();
    final normalizedDescription = entry.description?.trim();

    return entry.copyWith(
      name: normalizedName,
      address: normalizedAddress,
      handle: normalizedHandle != null && normalizedHandle.isNotEmpty ? normalizedHandle : null,
      description: normalizedDescription != null && normalizedDescription.isNotEmpty ? normalizedDescription : null,
    );
  }
}