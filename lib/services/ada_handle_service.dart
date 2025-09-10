import 'dart:convert';
import 'dart:collection';
import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class AdaHandleData {
  final String handle;
  final String? image;
  final String policyId;
  final String adaAddress;
  final String? displayName;
  final String? description;
  final bool isDefault;

  AdaHandleData({
    required this.handle,
    required this.policyId,
    required this.adaAddress,
    this.image,
    this.displayName,
    this.description,
    this.isDefault = false,
  });
}

class AdaHandleService {
  static const String _apiBase = 'https://api.handle.me';
  static const Duration _cacheTtl = Duration(minutes: 10);
  static const Duration _minInterval = Duration(milliseconds: 500);

  final Map<String, _CacheEntry<AdaHandleData?>> _resolveCache = HashMap();
  final Map<String, Future<AdaHandleData?>> _inflight = {};
  DateTime _lastRequestAt = DateTime.fromMillisecondsSinceEpoch(0);

  String _normalizeHandle(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed.replaceFirst(RegExp(r'^[\$@]'), '');
  }

  bool isHandle(String input) {
    final s = input.trim();
    return RegExp(r'^[\$@]').hasMatch(s) || RegExp(r'^[a-zA-Z0-9_.-]{1,60}').hasMatch(s);
  }

  Future<AdaHandleData?> resolveHandle(String handle) async {
    final normalized = _normalizeHandle(handle);
    if (normalized.isEmpty) return null;

    // Cache hit
    final cached = _resolveCache[normalized];
    final now = DateTime.now();
    if (cached != null && now.difference(cached.insertedAt) < _cacheTtl) {
      return cached.value;
    }

    // In-flight de-duplication
    final existing = _inflight[normalized];
    if (existing != null) return await existing;

    // Rate limit
    final since = now.difference(_lastRequestAt);
    if (since < _minInterval) {
      await Future.delayed(_minInterval - since);
    }
    _lastRequestAt = DateTime.now();

    final future = _resolveHandleNetwork(normalized).then((result) {
      // Only cache positive results; avoid caching null failures
      if (result != null) {
        _resolveCache[normalized] = _CacheEntry(result, DateTime.now());
      }
      _inflight.remove(normalized);
      return result;
    }).catchError((e) {
      _inflight.remove(normalized);
      throw e;
    });

    _inflight[normalized] = future;
    return await future;
  }

  Future<AdaHandleData?> _resolveHandleNetwork(String normalized) async {
    // Prefer proxy on web to avoid CORS; serverless function should forward to api.handle.me
    Uri url;
    Map<String, String> headers = {'Accept': 'application/json'};
    if (kIsWeb) {
      url = Uri.parse('/api/handle/handles/$normalized');
    } else {
      url = Uri.parse('$_apiBase/handles/$normalized');
    }

    http.Response resp;
    try {
      resp = await http.get(url, headers: headers);
    } catch (_) {
      // Fallback to direct (in case proxy missing) even on web
      resp = await http.get(Uri.parse('$_apiBase/handles/$normalized'), headers: headers);
    }

    // Debug diagnostics (safe for production; short)
    try {
      // ignore: avoid_print
      print('🔍 HANDLE DEBUG: status=${resp.statusCode} ct=${resp.headers['content-type']} len=${resp.body.length}');
    } catch (_) {}

    if (resp.statusCode == 429) {
      // Back off briefly and return null to avoid hammering
      await Future.delayed(const Duration(seconds: 1));
      return null;
    }

    if (resp.statusCode != 200) {
      // On web, try direct as a secondary attempt if proxy failed (may still hit CORS)
      if (kIsWeb) {
        try {
          final direct = await http.get(Uri.parse('$_apiBase/handles/$normalized'), headers: headers);
          if (direct.statusCode == 200) {
            resp = direct;
          } else {
            return null;
          }
        } catch (_) {
          return null;
        }
      } else {
        return null;
      }
    }
    Map<String, dynamic> data;
    try {
      data = json.decode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    String? resolved;
    final ra = data['resolved_addresses'];
    if (ra is Map) {
      final adaVal = ra['ada'];
      if (adaVal is String) {
        resolved = adaVal;
      } else if (adaVal is Map) {
        // Some variants nest address
        resolved = (adaVal['address'] as String?) ?? (adaVal['mainnet'] as String?);
      }
    }
    // Other possible shapes
    resolved ??= data['address'] as String?;
    final addrs = data['addresses'] ?? data['addr'] ?? data['ada'];
    if (resolved == null && addrs is Map) {
      final ada = addrs['ada'];
      if (ada is String) resolved = ada;
      if (ada is Map) resolved = ada['address'] as String?;
    }

    if (resolved == null || resolved.isEmpty) return null;
    return AdaHandleData(
      handle: data['handle'] ?? normalized,
      image: data['image'],
      policyId: data['policy_id'] ?? '',
      adaAddress: resolved,
      displayName: data['profile']?['display_name'],
      description: data['profile']?['description'],
      isDefault: data['default_handle'] == true,
    );
  }

  Future<List<AdaHandleData>> getHandlesByAddress(String address) async {
    Uri url;
    Map<String, String> headers = {'Accept': 'application/json'};
    if (kIsWeb) {
      url = Uri.parse('/api/handle/holders/$address');
    } else {
      url = Uri.parse('$_apiBase/holders/$address');
    }

    http.Response resp;
    try {
      resp = await http.get(url, headers: headers);
    } catch (_) {
      resp = await http.get(Uri.parse('$_apiBase/holders/$address'), headers: headers);
    }
    if (resp.statusCode != 200) return <AdaHandleData>[];
    final data = json.decode(resp.body) as Map<String, dynamic>;
    final handles = (data['handles'] as List? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();

    return handles.map((h) {
      final resolved = h['resolved_addresses']?['ada'] as String? ?? '';
      return AdaHandleData(
        handle: h['handle'] ?? '',
        image: h['image'],
        policyId: h['policy_id'] ?? '',
        adaAddress: resolved,
        displayName: h['profile']?['display_name'],
        description: h['profile']?['description'],
        isDefault: h['default_handle'] == true,
      );
    }).where((h) => h.adaAddress.isNotEmpty).toList();
  }
}

class _CacheEntry<T> {
  final T value;
  final DateTime insertedAt;
  _CacheEntry(this.value, this.insertedAt);
} 