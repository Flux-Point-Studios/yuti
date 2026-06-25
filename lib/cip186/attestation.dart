import 'dart:convert';
import 'dart:typed_data';

import 'errors.dart';

/// Canonical-form domain separator per spec §Response signing.
const String cip186SubjectDomainSeparator = 'cip30dl-v1\n';

/// Builds CIP-186 callback URLs (approved + rejected) and the canonical-form
/// subject string the wallet signs with its session Ed25519 key.
class AttestationBuilder {
  /// Constructs an `approved` response URL appended to [redirect].
  /// The Ed25519 signature is appended as the FINAL parameter per spec.
  static Uri buildApproved({
    required Uri redirect,
    required Uint8List walletNonce,
    required Uint8List ciphertext,
    required Uint8List signature,
  }) {
    final params = <String, String>{
      'response': 'approved',
      'nonce': _b64u(walletNonce),
      'payload': _b64u(ciphertext),
    };
    final base = _appendQuery(redirect, params);
    return _appendQuery(base, {'signature': _b64u(signature)});
  }

  /// Constructs an `approved` response URL whose Ed25519 signature is computed
  /// over the canonical subject of the (response, nonce, payload) base — i.e.
  /// the exact bytes the dApp will re-derive (canonicalSubject strips the
  /// `signature` parameter). [sign] receives the canonical-subject string and
  /// returns the 64-byte detached signature.
  static Uri buildApprovedSigned({
    required Uri redirect,
    required Uint8List walletNonce,
    required Uint8List ciphertext,
    required Uint8List Function(String canonicalSubject) sign,
  }) {
    final base = _appendQuery(redirect, {
      'response': 'approved',
      'nonce': _b64u(walletNonce),
      'payload': _b64u(ciphertext),
    });
    final signature = sign(canonicalSubject(base));
    return _appendQuery(base, {'signature': _b64u(signature)});
  }

  /// Constructs the `connect` approved response URL (spec §connect), Ed25519
  /// signed over its canonical subject. Beyond the wallet X25519 key + the
  /// box-encrypted session JSON, it adds a `method=connect` domain tag and an
  /// `echo` of the dApp's request nonce, then signs the
  /// (method, walletKey, nonce, echo, payload) base — so the dApp can verify the
  /// response is untampered, bound to its request, and pin the `signingPublicKey`
  /// the payload advertises for every SUBSEQUENT response. [sign] receives the
  /// canonical subject (signature stripped, keys sorted) and returns the 64-byte
  /// detached signature.
  static Uri buildConnectApprovedSigned({
    required Uri redirect,
    required Uint8List walletKey,
    required Uint8List walletNonce,
    required Uint8List ciphertext,
    required Uint8List echoNonce,
    required Uint8List Function(String canonicalSubject) sign,
  }) {
    final base = _appendQuery(redirect, {
      'response': 'approved',
      'method': 'connect',
      'walletKey': _b64u(walletKey),
      'nonce': _b64u(walletNonce),
      'echo': _b64u(echoNonce),
      'payload': _b64u(ciphertext),
    });
    final signature = sign(canonicalSubject(base));
    return _appendQuery(base, {'signature': _b64u(signature)});
  }

  /// Constructs a `rejected` response URL with the spec error envelope.
  static Uri buildRejected({
    required Uri redirect,
    required Cip186ErrorCode code,
    required String message,
  }) {
    return _appendQuery(redirect, {
      'response': 'rejected',
      'errorCode': code.wireValue.toString(),
      'errorMessage': message,
    });
  }

  /// Returns the canonical byte-string the wallet Ed25519-signs.
  /// Six-step procedure from spec §Response signing §Signature construction.
  static String canonicalSubject(Uri url) {
    final host = url.host.toLowerCase();
    final path = url.path;
    final schemeAndAuthority =
        '${url.scheme}://$host${url.hasPort ? ':${url.port}' : ''}$path';

    final pairs = <_QueryPair>[];
    url.queryParametersAll.forEach((k, vs) {
      if (k == 'signature') return;
      for (final v in vs) {
        pairs.add(_QueryPair(k, v));
      }
    });
    pairs.sort((a, b) {
      final cmp = a.key.compareTo(b.key);
      return cmp != 0 ? cmp : 0;
    });

    final encoded = pairs
        .map((p) => '${_strictUnreservedEncode(p.key)}='
            '${_strictUnreservedEncode(p.value)}')
        .join('&');

    return '$cip186SubjectDomainSeparator$schemeAndAuthority?$encoded';
  }

  static Uri _appendQuery(Uri base, Map<String, String> extra) {
    final merged = <String, List<String>>{};
    base.queryParametersAll.forEach((k, vs) => merged[k] = List.of(vs));
    extra.forEach((k, v) => (merged[k] ??= <String>[]).add(v));
    final qs = merged.entries
        .expand((e) =>
            e.value.map((v) => '${_strictUnreservedEncode(e.key)}'
                '=${_strictUnreservedEncode(v)}'))
        .join('&');
    final scheme = base.scheme;
    final host = base.host;
    final path = base.path;
    final auth = host.isEmpty ? '' : (base.hasPort ? '$host:${base.port}' : host);
    return Uri.parse('$scheme:${host.isEmpty ? '' : '//'}$auth$path?$qs');
  }

  static String _b64u(List<int> bytes) {
    final s = base64Url.encode(bytes);
    return s.replaceAll('=', '');
  }

  static final RegExp _unreserved = RegExp(r'[A-Za-z0-9._~-]');

  static String _strictUnreservedEncode(String input) {
    final buf = StringBuffer();
    final bytes = utf8.encode(input);
    for (final b in bytes) {
      final ch = String.fromCharCode(b);
      if (_unreserved.hasMatch(ch)) {
        buf.write(ch);
      } else {
        buf.write('%');
        buf.write(b.toRadixString(16).toUpperCase().padLeft(2, '0'));
      }
    }
    return buf.toString();
  }
}

class _QueryPair {
  _QueryPair(this.key, this.value);
  final String key;
  final String value;
}
