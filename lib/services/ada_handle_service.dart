import 'dart:convert';
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

    final url = Uri.parse('$_apiBase/handles/$normalized');
    final headers = <String, String>{'Accept': 'application/json'};

    final resp = await http.get(url, headers: headers);
    if (resp.statusCode != 200) return null;
    final data = json.decode(resp.body) as Map<String, dynamic>;

    final resolved = data['resolved_addresses']?['ada'] as String?;
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
    final url = Uri.parse('$_apiBase/holders/$address');
    final headers = <String, String>{'Accept': 'application/json'};

    final resp = await http.get(url, headers: headers);
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