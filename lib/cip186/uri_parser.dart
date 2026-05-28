import 'dart:convert';
import 'dart:typed_data';

import 'errors.dart';

/// CIP-186 protocol version handled by this implementation.
const String cip186ProtocolVersion = '1';

/// Maximum request URL size per spec §URI length budget.
const int cip186MaxPayloadBytes = 12 * 1024;

/// Wire form of a CIP-186 URI.
enum Cip186UriForm { https, customScheme }

/// CIP-186 method per §Methods + ABNF in §URI format.
enum Cip186Method {
  connect('connect'),
  disconnect('disconnect'),
  signTx('signTx'),
  signData('signData'),
  getUsedAddresses('getUsedAddresses'),
  getUnusedAddresses('getUnusedAddresses'),
  getRewardAddresses('getRewardAddresses'),
  getNetworkId('getNetworkId'),
  submitTx('submitTx');

  const Cip186Method(this.wireName);

  final String wireName;

  static Cip186Method? fromWire(String name) {
    for (final m in Cip186Method.values) {
      if (m.wireName == name) return m;
    }
    return null;
  }
}

/// ABNF-permitted query keys for v=1; any other key is a strict-reject (-9).
const Set<String> _allowedQueryKeys = {
  'v',
  'dapp',
  'dappKey',
  'redirect',
  'nonce',
  'commit',
  'session',
  'payload',
  'chain',
  'ttl',
  'page',
  'aead',
};

/// Structured CIP-186 request decoded from a deep-link URI.
class Cip186Request {
  Cip186Request({
    required this.form,
    required this.walletDomain,
    required this.walletId,
    required this.method,
    required this.params,
    required this.redirectUri,
    required this.dappKeyBytes,
    required this.nonceBytes,
    required this.commitBytes,
    required this.payloadBytes,
    required this.ttl,
    required this.chain,
  });

  final Cip186UriForm form;
  final String? walletDomain;
  final String? walletId;
  final Cip186Method method;
  final Map<String, String> params;
  final Uri? redirectUri;
  final Uint8List? dappKeyBytes;
  final Uint8List? nonceBytes;
  final Uint8List? commitBytes;
  final Uint8List? payloadBytes;
  final int? ttl;
  final String? chain;
}

/// Strict CIP-186 URI parser. Decodes the wire URI into a [Cip186Request].
///
/// Throws [Cip186Exception] on any spec violation:
/// unknown query key (-9), unrecognised method (-9), malformed scheme (-9),
/// payload over 12 KiB (-32), bad base64url (-9), wrong field byte length (-9).
class Cip186UriParser {
  static const String _httpsPathPrefix = '/cip30dl/v1/';
  static const String _customSchemePathPrefix = '/v1/';
  static const String _customSchemeFamily = 'cip30dl-';

  static Cip186Request parse(
    Uri uri, {
    String? expectedWalletId,
    String? expectedScheme,
  }) {
    final raw = uri.toString();
    if (raw.length > cip186MaxPayloadBytes) {
      throw Cip186Exception(
        Cip186ErrorCode.payloadTooLarge,
        'request URL exceeds $cip186MaxPayloadBytes bytes',
      );
    }

    final Cip186UriForm form;
    final String? walletDomain;
    final String? walletId;
    final String methodName;

    if (uri.scheme == 'https') {
      form = Cip186UriForm.https;
      walletDomain = uri.host.toLowerCase();
      walletId = null;
      methodName = _methodFromHttpsPath(uri.path);
    } else if (uri.scheme.startsWith(_customSchemeFamily) &&
        uri.scheme.length > _customSchemeFamily.length) {
      form = Cip186UriForm.customScheme;
      walletDomain = null;
      walletId = uri.scheme.substring(_customSchemeFamily.length);
      _validateWalletIdShape(walletId);
      methodName = _methodFromCustomSchemePath(uri.path);
    } else {
      throw Cip186Exception(
        Cip186ErrorCode.unsupportedVersion,
        'scheme "${uri.scheme}" is not a valid CIP-186 transport',
      );
    }

    if (expectedScheme != null &&
        form == Cip186UriForm.customScheme &&
        uri.scheme != expectedScheme) {
      throw Cip186Exception(
        Cip186ErrorCode.unsupportedVersion,
        'custom scheme "${uri.scheme}" does not match wallet scheme '
        '"$expectedScheme"',
      );
    }
    if (expectedWalletId != null &&
        walletId != null &&
        walletId != expectedWalletId) {
      throw Cip186Exception(
        Cip186ErrorCode.unsupportedVersion,
        'wallet id "$walletId" does not match this wallet "$expectedWalletId"',
      );
    }

    final method = Cip186Method.fromWire(methodName);
    if (method == null) {
      throw Cip186Exception(
        Cip186ErrorCode.unsupportedVersion,
        'method "$methodName" is not in v1 ABNF',
        offendingKey: methodName,
      );
    }

    final params = <String, String>{};
    uri.queryParameters.forEach((k, v) {
      if (!_allowedQueryKeys.contains(k)) {
        throw Cip186Exception(
          Cip186ErrorCode.unsupportedVersion,
          'unknown query-string key "$k"',
          offendingKey: k,
        );
      }
      params[k] = v;
    });

    _validateVersion(params['v']);

    final dappKeyBytes = _decodeFixedBase64Url(params['dappKey'], 32, 'dappKey');
    final nonceBytes = _decodeFixedBase64Url(params['nonce'], 24, 'nonce');
    final commitBytes = _decodeFixedBase64Url(params['commit'], 32, 'commit');
    final payloadBytes = _decodeVariableBase64Url(params['payload'], 'payload');
    final ttl = _parseTtl(params['ttl']);
    final redirectUri = _parseRedirect(params['redirect']);

    return Cip186Request(
      form: form,
      walletDomain: walletDomain,
      walletId: walletId,
      method: method,
      params: Map.unmodifiable(params),
      redirectUri: redirectUri,
      dappKeyBytes: dappKeyBytes,
      nonceBytes: nonceBytes,
      commitBytes: commitBytes,
      payloadBytes: payloadBytes,
      ttl: ttl,
      chain: params['chain'],
    );
  }

  static String _methodFromHttpsPath(String path) {
    if (!path.startsWith(_httpsPathPrefix)) {
      throw Cip186Exception(
        Cip186ErrorCode.unsupportedVersion,
        'HTTPS URL must start with $_httpsPathPrefix',
      );
    }
    final tail = path.substring(_httpsPathPrefix.length);
    if (tail.isEmpty || tail.contains('/')) {
      throw Cip186Exception(
        Cip186ErrorCode.unsupportedVersion,
        'method segment missing or malformed after $_httpsPathPrefix',
      );
    }
    return tail;
  }

  static String _methodFromCustomSchemePath(String path) {
    if (!path.startsWith(_customSchemePathPrefix)) {
      throw Cip186Exception(
        Cip186ErrorCode.unsupportedVersion,
        'custom-scheme URL must start with $_customSchemePathPrefix',
      );
    }
    final tail = path.substring(_customSchemePathPrefix.length);
    if (tail.isEmpty || tail.contains('/')) {
      throw Cip186Exception(
        Cip186ErrorCode.unsupportedVersion,
        'method segment missing or malformed after $_customSchemePathPrefix',
      );
    }
    return tail;
  }

  static final RegExp _walletIdShape =
      RegExp(r'^[a-z0-9][a-z0-9_-]{0,30}[a-z0-9]$');

  static void _validateWalletIdShape(String id) {
    if (!_walletIdShape.hasMatch(id)) {
      throw Cip186Exception(
        Cip186ErrorCode.unsupportedVersion,
        'wallet id "$id" violates scheme grammar',
      );
    }
  }

  static void _validateVersion(String? v) {
    if (v == null) {
      throw Cip186Exception(
        Cip186ErrorCode.unsupportedVersion,
        'missing required "v" parameter',
        offendingKey: 'v',
      );
    }
    if (v.length > 1 && v.startsWith('0')) {
      throw Cip186Exception(
        Cip186ErrorCode.unsupportedVersion,
        '"v" must be decimal integer with no leading zeros',
        offendingKey: 'v',
      );
    }
    if (v != cip186ProtocolVersion) {
      throw Cip186Exception(
        Cip186ErrorCode.unsupportedVersion,
        'protocol version "$v" not supported (this wallet implements v=1)',
      );
    }
  }

  static int? _parseTtl(String? raw) {
    if (raw == null) return null;
    final ttl = int.tryParse(raw);
    if (ttl == null || ttl <= 0) {
      throw Cip186Exception(
        Cip186ErrorCode.unsupportedVersion,
        '"ttl" must be a positive integer of unix seconds',
        offendingKey: 'ttl',
      );
    }
    return ttl;
  }

  static Uri? _parseRedirect(String? raw) {
    if (raw == null) return null;
    try {
      return Uri.parse(raw);
    } catch (_) {
      throw Cip186Exception(
        Cip186ErrorCode.redirectHostMismatch,
        '"redirect" is not a parseable URI',
        offendingKey: 'redirect',
      );
    }
  }

  static final RegExp _base64UrlAlphabet = RegExp(r'^[A-Za-z0-9_-]+$');

  static Uint8List? _decodeFixedBase64Url(
      String? raw, int expectedLen, String fieldName) {
    if (raw == null) return null;
    final bytes = _strictBase64UrlDecode(raw, fieldName);
    if (bytes.length != expectedLen) {
      throw Cip186Exception(
        Cip186ErrorCode.unsupportedVersion,
        '"$fieldName" must decode to $expectedLen bytes (got ${bytes.length})',
        offendingKey: fieldName,
      );
    }
    return bytes;
  }

  static Uint8List? _decodeVariableBase64Url(String? raw, String fieldName) {
    if (raw == null) return null;
    return _strictBase64UrlDecode(raw, fieldName);
  }

  static Uint8List _strictBase64UrlDecode(String input, String fieldName) {
    if (input.isEmpty) {
      throw Cip186Exception(
        Cip186ErrorCode.unsupportedVersion,
        '"$fieldName" is empty',
        offendingKey: fieldName,
      );
    }
    if (!_base64UrlAlphabet.hasMatch(input)) {
      throw Cip186Exception(
        Cip186ErrorCode.unsupportedVersion,
        '"$fieldName" contains characters outside the unpadded base64url alphabet',
        offendingKey: fieldName,
      );
    }
    final padded =
        input + ('=' * ((4 - input.length % 4) % 4));
    try {
      return Uint8List.fromList(base64Url.decode(padded));
    } catch (e) {
      throw Cip186Exception(
        Cip186ErrorCode.unsupportedVersion,
        '"$fieldName" failed strict base64url decode: $e',
        offendingKey: fieldName,
      );
    }
  }
}
