import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'blockfrost_service.dart';

class AssetCacheService {
  static const _storage = FlutterSecureStorage();
  static const String _metaKey = 'asset_metadata_cache_v1';
  static const String _researchKey = 'asset_research_cache_v1';

  static final AssetCacheService _instance = AssetCacheService._internal();
  factory AssetCacheService() => _instance;
  AssetCacheService._internal();

  final Map<String, _CacheEntry> _metaCache = {};
  final Map<String, _CacheEntry> _researchCache = {};

  Duration metadataTtl = const Duration(days: 7);
  Duration researchTtl = const Duration(days: 3);

  Future<void> initialize() async {
    try {
      final metaJson = await _storage.read(key: _metaKey);
      if (metaJson != null) {
        final map = json.decode(metaJson) as Map<String, dynamic>;
        map.forEach((k, v) {
          _metaCache[k] = _CacheEntry.fromJson(Map<String, dynamic>.from(v));
        });
      }
      final researchJson = await _storage.read(key: _researchKey);
      if (researchJson != null) {
        final map = json.decode(researchJson) as Map<String, dynamic>;
        map.forEach((k, v) {
          _researchCache[k] = _CacheEntry.fromJson(Map<String, dynamic>.from(v));
        });
      }
    } catch (_) {}
  }

  Future<Map<String, dynamic>> getDisplayInfoWithCache(String unit) async {
    await initialize();
    final existing = _metaCache[unit];
    if (existing != null && DateTime.now().difference(existing.storedAt) < metadataTtl) {
      return existing.data;
    }
    final fresh = await BlockfrostService().getAssetDisplayInfo(unit);
    _metaCache[unit] = _CacheEntry(data: fresh, storedAt: DateTime.now());
    _persistMeta();
    return fresh;
  }

  Future<Map<String, dynamic>> getAssetMetadataWithCache(String unit) async {
    await initialize();
    final existing = _metaCache['meta:$unit'];
    if (existing != null && DateTime.now().difference(existing.storedAt) < metadataTtl) {
      return existing.data;
    }
    final fresh = await BlockfrostService().getAssetMetadata(unit);
    _metaCache['meta:$unit'] = _CacheEntry(data: fresh, storedAt: DateTime.now());
    _persistMeta();
    return fresh;
  }

  Future<void> cacheResearch(String key, Map<String, dynamic> data) async {
    await initialize();
    _researchCache[key] = _CacheEntry(data: data, storedAt: DateTime.now());
    _persistResearch();
  }

  Future<Map<String, dynamic>?> getResearch(String key) async {
    await initialize();
    final existing = _researchCache[key];
    if (existing != null && DateTime.now().difference(existing.storedAt) < researchTtl) {
      return existing.data;
    }
    return null;
  }

  void _persistMeta() {
    try {
      final map = _metaCache.map((k, v) => MapEntry(k, v.toJson()));
      _storage.write(key: _metaKey, value: json.encode(map));
    } catch (_) {}
  }

  void _persistResearch() {
    try {
      final map = _researchCache.map((k, v) => MapEntry(k, v.toJson()));
      _storage.write(key: _researchKey, value: json.encode(map));
    } catch (_) {}
  }
}

class _CacheEntry {
  final Map<String, dynamic> data;
  final DateTime storedAt;
  _CacheEntry({required this.data, required this.storedAt});
  Map<String, dynamic> toJson() => {
        'data': data,
        'storedAt': storedAt.toIso8601String(),
      };
  factory _CacheEntry.fromJson(Map<String, dynamic> json) => _CacheEntry(
        data: Map<String, dynamic>.from(json['data'] as Map),
        storedAt: DateTime.parse(json['storedAt'] as String),
      );
} 