import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/address_book_entry.dart';
import 'ada_handle_service.dart';

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

  /// Initialize and load existing entries
  Future<void> initialize() async {
    await loadEntries();
  }

  /// Load entries from storage
  Future<void> loadEntries() async {
    try {
      final entriesJson = await _storage.read(key: _addressBookKey);
      if (entriesJson != null) {
        final List<dynamic> entriesList = json.decode(entriesJson);
        _entries = entriesList
            .map((json) => AddressBookEntry.fromJson(json))
            .toList();
        
        // Sort by name
        _entries.sort((a, b) => a.name.compareTo(b.name));
      }
    } catch (e) {
      print('Error loading address book entries: $e');
      _entries = [];
    }
  }

  /// Save entries to storage
  Future<void> _saveEntries() async {
    try {
      final entriesJson = json.encode(
        _entries.map((entry) => entry.toJson()).toList(),
      );
      await _storage.write(key: _addressBookKey, value: entriesJson);
    } catch (e) {
      print('Error saving address book entries: $e');
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
    // Check if address already exists
    if (_entries.any((e) => e.address == entry.address)) {
      return false; // Address already exists
    }
    
    // Check if name already exists
    if (_entries.any((e) => e.name.toLowerCase() == entry.name.toLowerCase())) {
      return false; // Name already exists
    }

    _entries.add(entry);
    _entries.sort((a, b) => a.name.compareTo(b.name)); // Re-sort
    await _saveEntries();
    return true;
  }

  /// Update an existing entry
  Future<bool> updateEntry(String id, AddressBookEntry updatedEntry) async {
    final index = _entries.indexWhere((entry) => entry.id == id);
    if (index == -1) return false;

    // Check if new name conflicts with another entry (excluding current one)
    if (_entries.any((e) => 
        e.id != id && 
        e.name.toLowerCase() == updatedEntry.name.toLowerCase())) {
      return false; // Name already exists
    }

    // Check if new address conflicts with another entry (excluding current one)
    if (_entries.any((e) => 
        e.id != id && 
        e.address == updatedEntry.address)) {
      return false; // Address already exists
    }

    _entries[index] = updatedEntry;
    _entries.sort((a, b) => a.name.compareTo(b.name)); // Re-sort
    await _saveEntries();
    return true;
  }

  /// Delete an entry
  Future<bool> deleteEntry(String id) async {
    final initialLength = _entries.length;
    _entries.removeWhere((entry) => entry.id == id);
    
    if (_entries.length < initialLength) {
      await _saveEntries();
      return true;
    }
    return false;
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
    return _entries
        .where((entry) => entry.name.toLowerCase().contains(lowercaseQuery))
        .toList();
  }

  /// Update last used timestamp for an entry
  Future<void> updateLastUsed(String address) async {
    final index = _entries.indexWhere((entry) => entry.address == address);
    if (index != -1) {
      final entry = _entries[index];
      _entries[index] = entry.copyWith(lastUsed: DateTime.now());
      await _saveEntries();
    }
  }

  /// Get recently used entries
  List<AddressBookEntry> getRecentlyUsed({int limit = 5}) {
    final recentEntries = _entries
        .where((entry) => entry.lastUsed != null)
        .toList()
      ..sort((a, b) => b.lastUsed!.compareTo(a.lastUsed!));
    
    return recentEntries.take(limit).toList();
  }

  /// Clear all entries
  Future<void> clearEntries() async {
    _entries.clear();
    await _saveEntries();
  }

  /// Check if address is valid Cardano address
  bool isValidCardanoAddress(String address) {
    // Basic Cardano address validation
    return address.startsWith('addr1') || address.startsWith('addr_test1');
  }
}