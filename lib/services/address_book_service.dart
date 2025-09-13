import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/address_book_entry.dart';
import 'ada_handle_service.dart';
import 'supabase_service.dart';

class AddressBookService {
  static const _storage = FlutterSecureStorage();
  static const String _addressBookKey = 'wallet_address_book';

  // Singleton pattern
  static final AddressBookService _instance = AddressBookService._internal();
  factory AddressBookService() => _instance;
  AddressBookService._internal();

  final AdaHandleService _handleService = AdaHandleService();

  List<AddressBookEntry> _entries = [];
  
  List<AddressBookEntry> get entries => List.unmodifiable(_entries);

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
          return AddressBookEntry(
            id: row['id'].toString(),
            name: (row['name'] ?? '').toString(),
            address: (row['address'] ?? '').toString(),
            handle: row['handle']?.toString(),
            description: row['description']?.toString(),
            createdAt: DateTime.parse((row['created_at'] ?? DateTime.now().toIso8601String()).toString()),
            lastUsed: row['last_used'] != null ? DateTime.parse(row['last_used'].toString()) : null,
          );
        }).toList();
        _entries.sort((a, b) => a.name.compareTo(b.name));

        // If remote is empty but local cache exists, bootstrap-sync local -> remote
        if (_entries.isEmpty) {
          try {
            final cached = await _storage.read(key: _addressBookKey);
            if (cached != null) {
              final List<dynamic> cacheList = json.decode(cached);
              final localEntries = cacheList.map((e) => AddressBookEntry.fromJson(e)).toList();
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
        _entries = entriesList.map((json) => AddressBookEntry.fromJson(json)).toList();
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
        return {'address': res.adaAddress, 'handle': res.handle.startsWith('@') ? '@${res.handle}' : '@${res.handle}'};
      }
    }
    return {'address': trimmed};
  }

  /// Add a new entry
  Future<bool> addEntry(AddressBookEntry entry) async {
    // Check duplicates locally
    if (_entries.any((e) => e.address == entry.address)) {
      return false;
    }
    if (_entries.any((e) => e.name.toLowerCase() == entry.name.toLowerCase())) {
      return false;
    }

    try {
      if (_isLoggedIn) {
        await _supabase.from('address_book').insert({
          'id': entry.id,
          'user_id': _userId,
          'name': entry.name,
          'address': entry.address,
          'handle': entry.handle,
          'description': entry.description,
          'created_at': entry.createdAt.toIso8601String(),
          'last_used': entry.lastUsed?.toIso8601String(),
        });
      }

      _entries.add(entry);
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

    // Uniqueness checks
    if (_entries.any((e) => e.id != id && e.name.toLowerCase() == updatedEntry.name.toLowerCase())) {
      return false;
    }
    if (_entries.any((e) => e.id != id && e.address == updatedEntry.address)) {
      return false;
    }

    try {
      if (_isLoggedIn) {
        await _supabase
            .from('address_book')
            .update({
              'name': updatedEntry.name,
              'address': updatedEntry.address,
              'handle': updatedEntry.handle,
              'description': updatedEntry.description,
              'last_used': updatedEntry.lastUsed?.toIso8601String(),
            })
            .eq('id', id)
            .eq('user_id', _userId!);
      }

      _entries[index] = updatedEntry;
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
    try {
      return _entries.firstWhere((entry) => entry.address == address);
    } catch (e) {
      return null;
    }
  }

  /// Search entries by name
  List<AddressBookEntry> searchByName(String query) {
    final lowercaseQuery = query.toLowerCase();
    return _entries.where((entry) => entry.name.toLowerCase().contains(lowercaseQuery)).toList();
  }

  /// Update last used timestamp for an entry
  Future<void> updateLastUsed(String address) async {
    final index = _entries.indexWhere((entry) => entry.address == address);
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
    return address.startsWith('addr1') || address.startsWith('addr_test1');
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
}