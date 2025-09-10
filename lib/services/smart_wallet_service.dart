import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_web_auth/flutter_web_auth.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as enc;
import 'package:pointycastle/export.dart' as pc;
import '../config/app_config.dart';

class SmartWalletService {
  SmartWalletService._internal();
  static final SmartWalletService _instance = SmartWalletService._internal();
  factory SmartWalletService() => _instance;

  final AppConfig _config = AppConfig();

  // OAuth scopes required for id_token
  static const String _googleScopes = 'openid email profile';

  // OAuth redirect scheme/URI (matches platform URL schemes)
  static const String _callbackScheme = 'yuti';
  static const String _callbackHost = 'smartwallet-oauth';
  static String get _redirectUri => '$_callbackScheme://$_callbackHost';

  // Public API

  Future<SmartWalletAuthResult> continueWithGoogle() async {
    if (kIsWeb) {
      throw Exception('Smart Wallet Google login is handled by web flow');
    }

    final clientId = await _obtainGoogleClientId();
    if (clientId == null || clientId.isEmpty) {
      throw Exception('Missing Google OAuth client ID');
    }

    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _codeChallengeS256(codeVerifier);

    final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': clientId,
      'redirect_uri': _redirectUri,
      'response_type': 'code',
      'scope': _googleScopes,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'access_type': 'offline',
      'prompt': 'select_account',
    }).toString();

    final resultUrl = await FlutterWebAuth.authenticate(
      url: authUrl,
      callbackUrlScheme: _callbackScheme,
    );

    final result = Uri.parse(resultUrl);
    final code = result.queryParameters['code'];
    if (code == null || code.isEmpty) {
      throw Exception('OAuth failed: missing code');
    }

    final token = await _exchangeCodeForToken(
      code: code,
      clientId: clientId,
      codeVerifier: codeVerifier,
      redirectUri: _redirectUri,
    );

    final idToken = token.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw Exception('OAuth failed: missing id_token');
    }

    final email = _extractEmailFromIdToken(idToken);
    if (email == null || email.isEmpty) {
      throw Exception('OAuth failed: missing email from id_token');
    }

    return SmartWalletAuthResult(email: email, idToken: idToken);
  }

  // Web OAuth helpers
  Future<String> buildGoogleAuthUrlWeb({String? returnTo}) async {
    final clientId = await _obtainGoogleClientId();
    if (clientId == null || clientId.isEmpty) {
      throw Exception('Missing Google OAuth client ID');
    }
    final codeVerifier = _generateCodeVerifier();
    final codeChallenge = _codeChallengeS256(codeVerifier);
    final redirectUri = '${Uri.base.origin}/smartwallet-oauth';

    // Pack code_verifier into state (base64url JSON)
    final stateObj = {
      'cv': codeVerifier,
      if (returnTo != null) 'rt': returnTo,
    };
    final state = _base64UrlEncode(Uint8List.fromList(utf8.encode(jsonEncode(stateObj))));

    final params = {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': _googleScopes,
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'access_type': 'offline',
      'prompt': 'select_account',
      'state': state,
    };

    return Uri.https('accounts.google.com', '/o/oauth2/v2/auth', params).toString();
  }

  Future<SmartWalletAuthResult> completeWebLogin({
    required String code,
    required String state,
  }) async {
    final clientId = await _obtainGoogleClientId();
    if (clientId == null || clientId.isEmpty) {
      throw Exception('Missing Google OAuth client ID');
    }
    // Decode state
    final stateJson = utf8.decode(_base64UrlDecode(state));
    final stateObj = jsonDecode(stateJson) as Map<String, dynamic>;
    final codeVerifier = stateObj['cv']?.toString();
    if (codeVerifier == null || codeVerifier.isEmpty) {
      throw Exception('Missing code_verifier in state');
    }
    final redirectUri = '${Uri.base.origin}/smartwallet-oauth';

    final token = await _exchangeCodeForToken(
      code: code,
      clientId: clientId,
      codeVerifier: codeVerifier,
      redirectUri: redirectUri,
    );

    final idToken = token.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw Exception('OAuth failed: missing id_token');
    }
    final email = _extractEmailFromIdToken(idToken);
    if (email == null || email.isEmpty) {
      throw Exception('OAuth failed: missing email from id_token');
    }
    return SmartWalletAuthResult(email: email, idToken: idToken);
  }

  Future<String?> getWalletAddressByEmail(String email) async {
    final url = Uri.parse('${_config.smartWalletApiBase}/v0/wallet/address');
    final headers = await _jsonHeaders();
    final resp = await http.post(
      url,
      headers: headers,
      body: jsonEncode({'email': email}),
    );

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return data['address']?.toString();
    }

    return null; // address might not exist yet
  }

  // Activation and transactions (high-level wrappers)

  Future<ProofKeys?> getProverKeys() async {
    final url = Uri.parse('${_config.smartWalletProverBase}/v0/keys');
    final resp = await http.get(url);
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body) as List<dynamic>;
    if (data.isEmpty) return null;
    final first = data.first as Map<String, dynamic>;
    return ProofKeys(
      keyId: first['id']?.toString() ?? '',
      publicN: first['public']?['public_n']?.toString() ?? '',
      publicE: first['public']?['public_e']?.toString() ?? '',
      sizeBits: (first['public']?['public_size'] as num?)?.toInt() ?? 2048,
    );
  }

  Future<String?> submitProveRequest({
    required String idToken,
    required String paymentKeyHashHex,
    required ProofKeys keys,
  }) async {
    try {
      // Parse JWT parts
      final parts = idToken.split('.');
      if (parts.length != 3) throw Exception('Invalid id_token');
      final headerB64 = parts[0];
      final payloadB64 = parts[1];
      final signatureB64 = parts[2];
      final headerJson = jsonDecode(utf8.decode(_base64UrlDecode(headerB64))) as Map<String, dynamic>;
      final kid = headerJson['kid']?.toString();
      if (kid == null || kid.isEmpty) throw Exception('JWT missing kid');

      // Fetch Google JWK for kid
      final jwk = await _getGoogleJwk(kid);
      final pubEBytes = _base64UrlDecode(jwk['e']?.toString() ?? '');
      final pubNBytes = _base64UrlDecode(jwk['n']?.toString() ?? '');
      final piPubE = _bigIntFromBytes(pubEBytes).toString();
      final piPubN = _bigIntFromBytes(pubNBytes).toString();

      // Signature decimal integer
      final sigBytes = _base64UrlDecode(signatureB64);
      final piSignature = _bigIntFromBytes(sigBytes).toString();

      // Token name = decimal from payment_key_hash (hex)
      final piTokenName = _decimalFromHex(paymentKeyHashHex);

      // Build unencrypted payload
      final payloadMap = {
        'piPubE': piPubE,
        'piPubN': piPubN,
        'piSignature': piSignature,
        'piTokenName': piTokenName,
      };
      final plaintext = utf8.encode(jsonEncode(payloadMap));

      // Encrypt payload with AES-256-CBC (PKCS7), IV prefixed
      final aesKey = _secureRandomBytes(32);
      final iv = _secureRandomBytes(16);
      final encrypter = enc.Encrypter(enc.AES(enc.Key(aesKey), mode: enc.AESMode.cbc, padding: 'PKCS7'));
      final encrypted = encrypter.encryptBytes(plaintext, iv: enc.IV(iv));
      final encryptedPayloadHex = _bytesToHex(Uint8List.fromList(iv + encrypted.bytes));

      // Encrypt AES key with server RSA (PKCS1 v1.5)
      final serverN = BigInt.parse(keys.publicN);
      final serverE = BigInt.parse(keys.publicE);
      final rsa = pc.PKCS1Encoding(pc.RSAEngine())
        ..init(true, pc.PublicKeyParameter<pc.RSAPublicKey>(pc.RSAPublicKey(serverN, serverE)));
      final rsaOut = rsa.process(aesKey);
      final encAesHex = _bytesToHex(Uint8List.fromList(rsaOut));

      final body = {
        'server_key_id': keys.keyId,
        'aes_encryption_key': encAesHex,
        'encrypted_payload': encryptedPayloadHex,
      };

      final url = Uri.parse('${_config.smartWalletProverBase}/v0/prove');
      final resp = await http.post(url, headers: await _jsonHeaders(), body: jsonEncode(body));
      if (resp.statusCode != 200) {
        throw Exception('Prove request failed (${resp.statusCode})');
      }
      final proofId = (jsonDecode(resp.body) as Map<String, dynamic>);
      // API returns a JSON string or object? The swagger shows ProofId is a UUID string in body.
      // Handle both cases gracefully
      if (resp.body.trim().startsWith('"')) {
        return jsonDecode(resp.body).toString();
      }
      return proofId.toString();
    } catch (e) {
      rethrow;
    }
  }

  Future<ProofStatusResult?> pollProofStatus(String proofId) async {
    final url = Uri.parse('${_config.smartWalletProverBase}/v0/proof-status');
    final resp = await http.post(url, headers: await _jsonHeaders(), body: jsonEncode(proofId));
    if (resp.statusCode != 200) return null;
    final m = jsonDecode(resp.body) as Map<String, dynamic>;
    if (m.containsKey('Completed')) {
      final comp = m['Completed'] as Map<String, dynamic>;
      final bytes = (comp['bytes'] ?? comp) as Map<String, dynamic>;
      return ProofStatusResult.completed(bytes);
    }
    return ProofStatusResult.pending();
  }

  Future<ActivateWalletResult> activateWallet({
    required String jwtUnsigned,
    required String paymentKeyHashHex,
    required Map<String, dynamic> proofBytes,
  }) async {
    final url = Uri.parse('${_config.smartWalletApiBase}/v0/wallet/activate');
    final resp = await http.post(
      url,
      headers: await _jsonHeaders(),
      body: jsonEncode({
        'jwt': jwtUnsigned,
        'payment_key_hash': paymentKeyHashHex,
        'proof_bytes': proofBytes,
      }),
    );
    if (resp.statusCode != 200) {
      throw Exception('Activation failed (${resp.statusCode})');
    }
    final m = jsonDecode(resp.body) as Map<String, dynamic>;
    return ActivateWalletResult(
      address: m['address']?.toString() ?? '',
      txCborHex: m['transaction']?.toString() ?? '',
      txId: m['transaction_id']?.toString() ?? '',
      txFee: m['transaction_fee']?.toString() ?? '0',
    );
  }

  Future<SendFundsResult> buildSendFunds({
    required String email,
    required String paymentKeyHashHex,
    required String recipientAddress,
    required Map<String, int> valueMap,
  }) async {
    final url = Uri.parse('${_config.smartWalletApiBase}/v0/wallet/send-funds');
    final resp = await http.post(url, headers: await _jsonHeaders(), body: jsonEncode({
      'email': email,
      'payment_key_hash': paymentKeyHashHex,
      'outs': [
        {
          'address': recipientAddress,
          'value': valueMap,
        }
      ],
    }));
    if (resp.statusCode != 200) {
      throw Exception('Build send-funds failed (${resp.statusCode})');
    }
    final m = jsonDecode(resp.body) as Map<String, dynamic>;
    return SendFundsResult(
      txCborHex: m['transaction']?.toString() ?? '',
      txId: m['transaction_id']?.toString() ?? '',
      txFee: m['transaction_fee']?.toString() ?? '0',
    );
  }

  Future<SubmitResult> submitTransaction({
    required String txCborHex,
    List<String> notifyEmails = const [],
  }) async {
    final url = Uri.parse('${_config.smartWalletApiBase}/v0/tx/submit');
    final resp = await http.post(url, headers: await _jsonHeaders(), body: jsonEncode({
      'transaction': txCborHex,
      'email_recipients': notifyEmails,
    }));
    if (resp.statusCode != 200) {
      throw Exception('Submit failed (${resp.statusCode})');
    }
    final m = jsonDecode(resp.body) as Map<String, dynamic>;
    return SubmitResult(txId: m['transaction_id']?.toString() ?? '');
  }

  Future<String?> activateSeedlessWallet({required String idToken, required String email}) async {
    // Try to fully activate using prover flow
    final keys = await getProverKeys();
    if (keys == null) return null;
    final paymentKeyHashHex = derivePaymentKeyHashHex(email);
    final proofId = await submitProveRequest(idToken: idToken, paymentKeyHashHex: paymentKeyHashHex, keys: keys);
    if (proofId == null) return null;

    // Poll up to ~5 minutes
    ProofStatusResult? status;
    for (int i = 0; i < 30; i++) {
      await Future.delayed(const Duration(seconds: 10));
      status = await pollProofStatus(proofId);
      if (status?.isCompleted == true) break;
    }
    if (status?.isCompleted != true || status?.proofBytes == null) return null;

    final jwtUnsigned = unsignedJwtFromIdToken(idToken);
    final res = await activateWallet(
      jwtUnsigned: jwtUnsigned,
      paymentKeyHashHex: paymentKeyHashHex,
      proofBytes: status!.proofBytes!,
    );
    return res.address.isNotEmpty ? res.address : null;
  }

  // INTERNALS

  Future<String?> _obtainGoogleClientId() async {
    // Prefer environment override
    final envClientId = _config.smartWalletGoogleWebClientId;
    if (envClientId.isNotEmpty) return envClientId;

    // Fetch from Smart Wallet Backend
    try {
      final url = Uri.parse('${_config.smartWalletApiBase}/v0/oauth/credentials');
      final headers = await _jsonHeaders(allowApiKey: true);
      final resp = await http.get(url, headers: headers);
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        return data['client_id']?.toString();
      }
    } catch (_) {}

    return null;
  }

  Future<_TokenResponse> _exchangeCodeForToken({
    required String code,
    required String clientId,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final url = Uri.parse('https://oauth2.googleapis.com/token');
    final resp = await http.post(url, headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    }, body: {
      'code': code,
      'client_id': clientId,
      'code_verifier': codeVerifier,
      'redirect_uri': redirectUri,
      'grant_type': 'authorization_code',
    });

    if (resp.statusCode != 200) {
      throw Exception('Token exchange failed (${resp.statusCode})');
    }

    final m = jsonDecode(resp.body) as Map<String, dynamic>;
    return _TokenResponse(
      accessToken: m['access_token']?.toString(),
      idToken: m['id_token']?.toString(),
      refreshToken: m['refresh_token']?.toString(),
      expiresIn: (m['expires_in'] is int)
          ? m['expires_in'] as int
          : int.tryParse(m['expires_in']?.toString() ?? '0') ?? 0,
    );
  }

  String? _extractEmailFromIdToken(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length < 2) return null;
      final payload = _base64UrlDecode(parts[1]);
      final jsonMap = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
      return jsonMap['email']?.toString();
    } catch (_) {
      return null;
    }
  }

  String unsignedJwtFromIdToken(String jwt) {
    final parts = jwt.split('.');
    if (parts.length < 2) throw Exception('Invalid JWT');
    return '${parts[0]}.${parts[1]}';
  }

  Future<Map<String, dynamic>> _getGoogleJwk(String kid) async {
    final url = Uri.parse('https://www.googleapis.com/oauth2/v3/certs');
    final resp = await http.get(url);
    if (resp.statusCode != 200) throw Exception('Failed to fetch Google certs');
    final m = jsonDecode(resp.body) as Map<String, dynamic>;
    final keys = (m['keys'] as List).cast<Map<String, dynamic>>();
    final found = keys.firstWhere((k) => k['kid'] == kid, orElse: () => {});
    if (found.isEmpty) throw Exception('Google JWK not found for kid');
    return found;
  }

  // Helpers
  Uint8List _secureRandomBytes(int length) {
    final rnd = Random.secure();
    return Uint8List.fromList(List<int>.generate(length, (_) => rnd.nextInt(256)));
  }

  BigInt _bigIntFromBytes(Uint8List bytes) {
    BigInt result = BigInt.zero;
    for (final b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  String _bytesToHex(Uint8List bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  String _decimalFromHex(String hex) {
    final cleaned = hex.startsWith('0x') ? hex.substring(2) : hex;
    BigInt value = BigInt.zero;
    for (int i = 0; i < cleaned.length; i++) {
      final c = cleaned.codeUnitAt(i);
      int v;
      if (c >= 48 && c <= 57) {
        v = c - 48;
      } else if (c >= 97 && c <= 102) {
        v = 10 + (c - 97);
      } else if (c >= 65 && c <= 70) {
        v = 10 + (c - 65);
      } else {
        continue;
      }
      value = (value << 4) + BigInt.from(v);
    }
    return value.toString();
  }

  String derivePaymentKeyHashHex(String email) {
    // Deterministic placeholder: blake2b-224(email)
    final digest = pc.Blake2bDigest(digestSize: 28); // 224 bits
    final input = Uint8List.fromList(utf8.encode(email));
    digest.update(input, 0, input.length);
    final out = Uint8List(28);
    digest.doFinal(out, 0);
    return _bytesToHex(out);
  }

  // Headers
  Future<Map<String, String>> _jsonHeaders({bool allowApiKey = false}) async {
    final h = {
      'Content-Type': 'application/json;charset=utf-8',
    };
    if (allowApiKey && _config.smartWalletApiKey.isNotEmpty) {
      h['api-key'] = _config.smartWalletApiKey;
    }
    return h;
  }

  // PKCE helpers
  String _generateCodeVerifier() {
    const length = 64; // 43-128
    const charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rand = Random.secure();
    return List.generate(length, (_) => charset[rand.nextInt(charset.length)]).join();
  }

  String _codeChallengeS256(String verifier) {
    final bytes = Uint8List.fromList(utf8.encode(verifier));
    final digest = _sha256(bytes);
    return _base64UrlEncode(digest);
  }

  Uint8List _sha256(Uint8List input) {
    final h = crypto.sha256.convert(input);
    return Uint8List.fromList(h.bytes);
  }

  Uint8List _base64UrlDecode(String input) {
    String normalized = input.replaceAll('-', '+').replaceAll('_', '/');
    switch (normalized.length % 4) {
      case 2:
        normalized += '==';
        break;
      case 3:
        normalized += '=';
        break;
      default:
        break;
    }
    return base64.decode(normalized);
  }

  String _base64UrlEncode(Uint8List bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

class SmartWalletAuthResult {
  final String email;
  final String idToken;
  SmartWalletAuthResult({required this.email, required this.idToken});
}

class ProofKeys {
  final String keyId;
  final String publicN;
  final String publicE;
  final int sizeBits;
  ProofKeys({required this.keyId, required this.publicN, required this.publicE, required this.sizeBits});
}

class ProofStatusResult {
  final bool isCompleted;
  final Map<String, dynamic>? proofBytes;
  ProofStatusResult._(this.isCompleted, this.proofBytes);
  factory ProofStatusResult.completed(Map<String, dynamic> bytes) => ProofStatusResult._(true, bytes);
  factory ProofStatusResult.pending() => ProofStatusResult._(false, null);
}

class ActivateWalletResult {
  final String address;
  final String txCborHex;
  final String txId;
  final String txFee;
  ActivateWalletResult({required this.address, required this.txCborHex, required this.txId, required this.txFee});
}

class SendFundsResult {
  final String txCborHex;
  final String txId;
  final String txFee;
  SendFundsResult({required this.txCborHex, required this.txId, required this.txFee});
}

class SubmitResult {
  final String txId;
  SubmitResult({required this.txId});
}

class _TokenResponse {
  final String? accessToken;
  final String? idToken;
  final String? refreshToken;
  final int expiresIn;
  _TokenResponse({this.accessToken, this.idToken, this.refreshToken, required this.expiresIn});
} 