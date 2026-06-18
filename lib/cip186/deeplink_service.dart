import 'dart:convert';
import 'dart:typed_data';

import 'package:cardano_dart_types/cardano_dart_types.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:pinenacl/x25519.dart' as x;

import 'attestation.dart';
import 'crypto.dart';
import 'errors.dart';
import 'signing_engine.dart';
import 'uri_parser.dart';

/// Pluggable strategy for decoding the encrypted `payload` of a signTx request
/// into its `tx` / `partialSign` / `vkeyHints` JSON fields.
abstract class SignTxPayloadDecoder {
  Map<String, dynamic> decode({
    required Uint8List payload,
    required Uint8List walletNonce,
    required Uint8List dappKey,
  });

  Set<String> get witnessAddresses;

  factory SignTxPayloadDecoder.plaintextJson({
    required Set<String> witnessAddresses,
  }) =>
      _PlaintextJsonDecoder(witnessAddresses);

  /// Production decoder: NaCl-box (X25519 + XSalsa20-Poly1305) decryption of
  /// the request payload using the wallet's ephemeral session X25519 secret
  /// and the dApp public key carried in the URL (spec §Methods AEAD envelope).
  factory SignTxPayloadDecoder.naclBox({
    required Uint8List walletX25519Secret,
    required Set<String> witnessAddresses,
  }) =>
      _NaClBoxJsonDecoder(walletX25519Secret, witnessAddresses);
}

class _NaClBoxJsonDecoder implements SignTxPayloadDecoder {
  _NaClBoxJsonDecoder(this._walletX25519Secret, this._witnessAddresses);

  final Uint8List _walletX25519Secret;
  final Set<String> _witnessAddresses;

  @override
  Set<String> get witnessAddresses => _witnessAddresses;

  @override
  Map<String, dynamic> decode({
    required Uint8List payload,
    required Uint8List walletNonce,
    required Uint8List dappKey,
  }) {
    // Throws Cip186Exception(-7) on MAC failure or low-order dApp key.
    final plaintext = naclBoxDecrypt(
      ciphertext: payload,
      nonce: walletNonce,
      walletSecret: _walletX25519Secret,
      dappPublic: dappKey,
    );
    try {
      return jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
    } catch (e) {
      throw Cip186Exception(
        Cip186ErrorCode.decryptFailed,
        'decrypted payload is not a JSON object',
      );
    }
  }
}

/// Per-`connect` session state the wallet establishes (spec §Session-binding
/// key derivation): the ephemeral X25519 secret used for NaCl-box, and the
/// HKDF-derived Ed25519 key that signs every response. A future `connect`
/// handler persists this; signTx consumes it. Never logged.
class Cip186Session {
  Cip186Session({
    required this.walletX25519Secret,
    required this.sessionSigningKey,
    this.dappName,
    this.dappHost,
    this.expiresAt,
  });

  /// 32-byte ephemeral X25519 secret (rotates per `connect`).
  final Uint8List walletX25519Secret;

  /// Session-binding Ed25519 signing key; its vkey is published in the
  /// `connect` session JSON as `signingPublicKey`.
  final ed.SigningKey sessionSigningKey;

  /// dApp identity captured at `connect` (from the dapp-info JSON), so a later
  /// signTx prompt can name the requester. Null when not supplied.
  final String? dappName;
  final String? dappHost;

  /// Unix-seconds expiry (matches the connect session JSON `expiresAt`), used
  /// by a persistent store to evict stale sessions. Null when not supplied.
  final int? expiresAt;
}

/// What the user is being asked to approve. Surfaced to the wallet UI before
/// any session is established (connect) or any transaction is signed (signTx).
class Cip186ApprovalRequest {
  Cip186ApprovalRequest({
    required this.method,
    this.dappName,
    this.dappHost,
    this.txHashHex,
  });

  final Cip186Method method;
  final String? dappName;
  final String? dappHost;

  /// BLAKE2b-256(tx_body) hex — the transaction the dApp wants signed (signTx).
  final String? txHashHex;
}

/// Asks the user to approve a request. Returns true to proceed, false to reject
/// with `-1 UserRejected`. Null (the default) means headless auto-approve.
typedef Cip186Approval = Future<bool> Function(Cip186ApprovalRequest request);

/// In-memory `(dappKey, nonce)` replay guard (spec §Replay protection). A tuple
/// is remembered until `ttl + 600` seconds; a repeat within that window is
/// rejected. One instance lives for the app's lifetime (per wallet).
///
/// NOTE: this guard is process-scoped — it is rebuilt on a cold start, so a
/// replay fired after the wallet is killed/restarted (within the request ttl)
/// is not remembered here. The per-call user-consent prompt is the backstop in
/// that window (the same request re-prompts the user). Persisting replay tuples
/// across restarts is a tracked follow-up.
class Cip186ReplayGuard {
  final Map<String, int> _seen = <String, int>{};

  /// Records `(dappKey, nonce)` (expiring at [expiryEpoch]) and returns true if
  /// it was fresh, or false if the tuple was already seen within its window.
  bool checkAndRecord(
    Uint8List dappKey,
    Uint8List nonce,
    int expiryEpoch,
    int nowEpoch,
  ) {
    _seen.removeWhere((_, exp) => exp < nowEpoch);
    final key = '${base64Url.encode(dappKey)}:${base64Url.encode(nonce)}';
    if (_seen.containsKey(key)) return false;
    _seen[key] = expiryEpoch;
    return true;
  }
}

class _PlaintextJsonDecoder implements SignTxPayloadDecoder {
  _PlaintextJsonDecoder(this._witnessAddresses);

  final Set<String> _witnessAddresses;

  @override
  Set<String> get witnessAddresses => _witnessAddresses;

  @override
  Map<String, dynamic> decode({
    required Uint8List payload,
    required Uint8List walletNonce,
    required Uint8List dappKey,
  }) {
    try {
      return jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    } catch (e) {
      throw Cip186Exception(
        Cip186ErrorCode.decryptFailed,
        'plaintext-JSON payload decode failed: $e',
      );
    }
  }
}

/// Outcome of routing a single deep-link URL.
class DeepLinkOutcome {
  DeepLinkOutcome.success({required this.responseUri, required this.signResult})
      : errorCode = null,
        errorMessage = null,
        establishedSession = null,
        sessionId = null;

  DeepLinkOutcome.failure({
    required this.responseUri,
    required this.errorCode,
    required this.errorMessage,
  })  : signResult = null,
        establishedSession = null,
        sessionId = null;

  /// A successful `connect`: the response carries the encrypted session JSON,
  /// and [establishedSession] is the session the wiring layer must persist
  /// (keyed by the dApp X25519 key) so a later signTx can consume it.
  DeepLinkOutcome.connectApproved({
    required this.responseUri,
    required this.establishedSession,
    required this.sessionId,
  })  : signResult = null,
        errorCode = null,
        errorMessage = null;

  final Uri? responseUri;
  final Cip186SignResult? signResult;
  final Cip186ErrorCode? errorCode;
  final String? errorMessage;

  /// Set only for a successful `connect`.
  final Cip186Session? establishedSession;
  final String? sessionId;
}

/// Top-level orchestrator: parses the deep-link URL, validates redirect host,
/// dispatches to the signer for signTx, and constructs the callback URL.
class Cip186DeepLinkService {
  Cip186DeepLinkService({
    required CardanoWallet wallet,
    required this.walletId,
    required this.walletScheme,
    Uint8List? walletRootSecret,
    int sessionTtlSeconds = 3600,
    Uint8List Function()? sessionEntropySource,
    Cip186ReplayGuard? replayGuard,
    int Function()? clockEpochSeconds,
    Cip186Approval? approval,
    Future<String> Function()? addressResolver,
  })  : _wallet = wallet,
        _engine = Cip186SigningEngine(wallet: wallet),
        _walletRootSecret = walletRootSecret,
        _sessionTtl = sessionTtlSeconds,
        _sessionEntropy = sessionEntropySource ?? (() => randomBytes(32)),
        _replay = replayGuard ?? Cip186ReplayGuard(),
        _now = clockEpochSeconds ?? _systemClock,
        _approval = approval,
        _addressResolver = addressResolver;

  final String walletId;
  final String walletScheme;
  final CardanoWallet _wallet;
  final Cip186SigningEngine _engine;

  /// Wallet-internal secret (NOT the CIP-1852 root / stake / DRep key) used to
  /// derive session signing keys at `connect`. Persisted in secure storage in
  /// production; injected in tests. `connect` rejects (-100) if absent.
  final Uint8List? _walletRootSecret;
  final int _sessionTtl;
  final Uint8List Function() _sessionEntropy;
  final Set<String> _seenEntropy = <String>{};
  final Cip186ReplayGuard _replay;
  final int Function() _now;

  /// User-consent gate. Null → headless auto-approve (tests, legacy). When set,
  /// connect and signTx are only fulfilled if it returns true.
  final Cip186Approval? _approval;

  /// Resolves the wallet's payment address. Injected so it can be memoized +
  /// persisted (CIP-1852 derivation is slow on some devices). Null → derive
  /// inline from the wallet each time.
  final Future<String> Function()? _addressResolver;

  static int _systemClock() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Spec §-4 RedirectHostMismatch: bind the response redirect to the dApp's
  /// declared identity. An `https` redirect MUST match the dApp host (prevents
  /// an open redirect / response exfiltration to an attacker page). A custom
  /// scheme (native callback, e.g. `mydapp://cb`) is OS-routed only to the app
  /// that registered the scheme, so it is allowed. Plain `http` is rejected.
  static bool _redirectAllowed(Uri redirect, String? dappHost) {
    if (redirect.scheme == 'http') return false;
    if (redirect.scheme != 'https') return redirect.scheme.isNotEmpty;
    return dappHost != null &&
        redirect.host.isNotEmpty &&
        redirect.host.toLowerCase() == dappHost.toLowerCase();
  }

  Future<DeepLinkOutcome> handle({
    required Uri url,
    SignTxPayloadDecoder? signTxSemantics,
    Cip186Session? session,
  }) async {
    final Cip186Request request;
    try {
      request = Cip186UriParser.parse(
        url,
        expectedWalletId: walletId,
        expectedScheme: walletScheme,
      );
    } on Cip186Exception catch (e) {
      return DeepLinkOutcome.failure(
        responseUri: _maybeBuildErrorRedirect(url, e),
        errorCode: e.code,
        errorMessage: e.message,
      );
    }

    if (request.redirectUri == null) {
      return DeepLinkOutcome.failure(
        responseUri: null,
        errorCode: Cip186ErrorCode.redirectHostMismatch,
        errorMessage: '"redirect" parameter missing',
      );
    }

    switch (request.method) {
      case Cip186Method.signTx:
        if (signTxSemantics == null || session == null) {
          return DeepLinkOutcome.failure(
            responseUri: AttestationBuilder.buildRejected(
              redirect: request.redirectUri!,
              code: Cip186ErrorCode.sessionExpired,
              message: 'no active session for signTx — connect first',
            ),
            errorCode: Cip186ErrorCode.sessionExpired,
            errorMessage: 'no active session for signTx',
          );
        }
        return _handleSignTx(request, signTxSemantics, session);
      case Cip186Method.connect:
        return _handleConnect(request);
      case Cip186Method.disconnect:
      case Cip186Method.signData:
      case Cip186Method.getUsedAddresses:
      case Cip186Method.getUnusedAddresses:
      case Cip186Method.getRewardAddresses:
      case Cip186Method.getNetworkId:
      case Cip186Method.submitTx:
        // TODO(cip186): implement non-signTx methods. Spec §Methods.
        return DeepLinkOutcome.failure(
          responseUri: AttestationBuilder.buildRejected(
            redirect: request.redirectUri!,
            code: Cip186ErrorCode.unsupportedVersion,
            message: 'method ${request.method.wireName} not yet implemented',
          ),
          errorCode: Cip186ErrorCode.unsupportedVersion,
          errorMessage: 'method ${request.method.wireName} not yet implemented',
        );
    }
  }

  Future<DeepLinkOutcome> _handleSignTx(
    Cip186Request request,
    SignTxPayloadDecoder decoder,
    Cip186Session session,
  ) async {
    // Defense-in-depth: enforce session expiry at the point of use, not only
    // in the store's eviction path — so an expired session never signs even if
    // a store (e.g. in-memory) doesn't self-evict.
    if (session.expiresAt != null && _now() > session.expiresAt!) {
      return DeepLinkOutcome.failure(
        responseUri: request.redirectUri != null
            ? AttestationBuilder.buildRejected(
                redirect: request.redirectUri!,
                code: Cip186ErrorCode.sessionExpired,
                message: 'session has expired — reconnect',
              )
            : null,
        errorCode: Cip186ErrorCode.sessionExpired,
        errorMessage: 'session has expired',
      );
    }
    // Spec §-4: the signTx response must go back to the dApp that established
    // the session, not an attacker-chosen URL.
    if (session.dappHost != null &&
        !_redirectAllowed(request.redirectUri!, session.dappHost)) {
      return DeepLinkOutcome.failure(
        responseUri: AttestationBuilder.buildRejected(
          redirect: request.redirectUri!,
          code: Cip186ErrorCode.redirectHostMismatch,
          message: 'redirect host does not match the connected dApp',
        ),
        errorCode: Cip186ErrorCode.redirectHostMismatch,
        errorMessage: 'redirect host does not match dApp',
      );
    }
    if (request.payloadBytes == null ||
        request.commitBytes == null ||
        request.nonceBytes == null ||
        request.dappKeyBytes == null) {
      return DeepLinkOutcome.failure(
        responseUri: AttestationBuilder.buildRejected(
          redirect: request.redirectUri!,
          code: Cip186ErrorCode.unsupportedVersion,
          message: 'signTx is missing required encrypted-envelope fields',
        ),
        errorCode: Cip186ErrorCode.unsupportedVersion,
        errorMessage: 'signTx missing encrypted-envelope fields',
      );
    }

    // Spec §Replay protection: refuse to sign once the clock passes ttl (-6),
    // and refuse a (dappKey, nonce) tuple already seen within its window (-5).
    // Checked before any signing or decryption so replays are cheap to reject.
    final now = _now();
    if (request.ttl != null && now > request.ttl!) {
      return DeepLinkOutcome.failure(
        responseUri: AttestationBuilder.buildRejected(
          redirect: request.redirectUri!,
          code: Cip186ErrorCode.ttlExpired,
          message: 'request ttl has passed',
        ),
        errorCode: Cip186ErrorCode.ttlExpired,
        errorMessage: 'request ttl has passed',
      );
    }
    final expiry = (request.ttl ?? now) + 600;
    if (!_replay.checkAndRecord(
        request.dappKeyBytes!, request.nonceBytes!, expiry, now)) {
      return DeepLinkOutcome.failure(
        responseUri: AttestationBuilder.buildRejected(
          redirect: request.redirectUri!,
          code: Cip186ErrorCode.nonceReplay,
          message: 'duplicate (dappKey, nonce) — request already seen',
        ),
        errorCode: Cip186ErrorCode.nonceReplay,
        errorMessage: 'duplicate (dappKey, nonce)',
      );
    }

    final Map<String, dynamic> payload;
    try {
      payload = decoder.decode(
        payload: request.payloadBytes!,
        walletNonce: request.nonceBytes!,
        dappKey: request.dappKeyBytes!,
      );
    } on Cip186Exception catch (e) {
      return DeepLinkOutcome.failure(
        responseUri: AttestationBuilder.buildRejected(
          redirect: request.redirectUri!,
          code: e.code,
          message: e.message,
        ),
        errorCode: e.code,
        errorMessage: e.message,
      );
    }

    // MUST-FIX #2: guard the type, not just null. A non-String `tx`
    // (number/bool/list/object) must reject cleanly, never throw an uncaught
    // CastError that escapes the `on Cip186Exception` handler below.
    final txVal = payload['tx'];
    if (txVal is! String) {
      final msg =
          txVal == null ? 'payload.tx missing' : 'payload.tx must be a hex string';
      return DeepLinkOutcome.failure(
        responseUri: AttestationBuilder.buildRejected(
          redirect: request.redirectUri!,
          code: Cip186ErrorCode.unsupportedVersion,
          message: msg,
        ),
        errorCode: Cip186ErrorCode.unsupportedVersion,
        errorMessage: msg,
      );
    }
    final txHex = txVal;

    // User consent (spec §UserRejected). Asked after the request is understood
    // (decrypted + commit-bound) but before any signature is produced.
    if (_approval != null) {
      // The prompt shows the URL-supplied commit; it is verified against
      // BLAKE2b-256(tx_body) at sign time (signTxBody, constant-time), so a
      // mismatched commit fails closed AFTER approval rather than signing.
      final approved = await _approval(Cip186ApprovalRequest(
        method: Cip186Method.signTx,
        dappName: session.dappName,
        dappHost: session.dappHost,
        txHashHex: _hex(request.commitBytes!),
      ));
      if (!approved) {
        return DeepLinkOutcome.failure(
          responseUri: AttestationBuilder.buildRejected(
            redirect: request.redirectUri!,
            code: Cip186ErrorCode.userRejected,
            message: 'user rejected the signing request',
          ),
          errorCode: Cip186ErrorCode.userRejected,
          errorMessage: 'user rejected the signing request',
        );
      }
    }

    try {
      final result = await _engine.signTxBody(
        transactionHex: txHex,
        expectedCommit: request.commitBytes!,
        witnessAddresses: decoder.witnessAddresses,
      );

      // Approved response (spec §Methods AEAD envelope + §Response signing):
      // a FRESH 24-byte nonce, the witness-set CBOR NaCl-box-encrypted to the
      // dApp's X25519 key, and an Ed25519 signature over the canonical subject
      // by the session signing key. No placeholders.
      final walletNonce = randomBytes(24);
      final ciphertext = naclBoxEncrypt(
        plaintext: result.witnessSetCbor,
        nonce: walletNonce,
        walletSecret: session.walletX25519Secret,
        dappPublic: request.dappKeyBytes!,
      );

      return DeepLinkOutcome.success(
        responseUri: AttestationBuilder.buildApprovedSigned(
          redirect: request.redirectUri!,
          walletNonce: walletNonce,
          ciphertext: ciphertext,
          sign: (subject) => signCanonicalSubject(
            signingKey: session.sessionSigningKey,
            canonicalSubject: subject,
          ),
        ),
        signResult: result,
      );
    } on Cip186Exception catch (e) {
      return DeepLinkOutcome.failure(
        responseUri: AttestationBuilder.buildRejected(
          redirect: request.redirectUri!,
          code: e.code,
          message: e.message,
        ),
        errorCode: e.code,
        errorMessage: e.message,
      );
    }
  }

  /// Handles a `connect` handshake (spec §connect): derive a session-binding
  /// Ed25519 key (HKDF-SHA512) + a fresh ephemeral X25519 keypair, box-encrypt
  /// the session JSON to the dApp, and return the established session for the
  /// wiring layer to persist (keyed by the dApp X25519 key).
  Future<DeepLinkOutcome> _handleConnect(Cip186Request request) async {
    if (_walletRootSecret == null) {
      return _rejectConnect(request, Cip186ErrorCode.internalError,
          'wallet root secret unavailable for session derivation');
    }
    if (request.dappKeyBytes == null) {
      return _rejectConnect(
          request, Cip186ErrorCode.unsupportedVersion, 'connect missing dappKey');
    }
    // The dApp origin host binds the session signing key. It is carried in the
    // base64url dapp-info-json (spec §connect).
    final dappInfoRaw = request.params['dapp'];
    if (dappInfoRaw == null) {
      return _rejectConnect(
          request, Cip186ErrorCode.unsupportedVersion, 'connect missing dapp');
    }
    final String dappHost;
    final String? dappName;
    try {
      final info = jsonDecode(utf8.decode(_b64uDecode(dappInfoRaw)))
          as Map<String, dynamic>;
      dappHost = Uri.parse(info['url'] as String).host;
      if (dappHost.isEmpty) throw const FormatException('empty dApp host');
      final nameVal = info['name'];
      dappName = nameVal is String ? nameVal : null;
    } catch (_) {
      return _rejectConnect(request, Cip186ErrorCode.unsupportedVersion,
          'malformed dapp-info-json');
    }

    // Spec §-4: bind the response redirect to the dApp's declared host before
    // establishing a session or launching the session JSON anywhere.
    if (!_redirectAllowed(request.redirectUri!, dappHost)) {
      return _rejectConnect(request, Cip186ErrorCode.redirectHostMismatch,
          'redirect host does not match the dApp identity');
    }

    // User consent (spec §UserRejected) before establishing any session.
    if (_approval != null) {
      final approved = await _approval(Cip186ApprovalRequest(
        method: Cip186Method.connect,
        dappName: dappName,
        dappHost: dappHost,
      ));
      if (!approved) {
        return _rejectConnect(request, Cip186ErrorCode.userRejected,
            'user rejected the connection request');
      }
    }

    final sessionEntropy = _sessionEntropy();
    // -12: a session_entropy value MUST NOT be reused with the same dApp host.
    final entropyKey = '$dappHost:${base64Url.encode(sessionEntropy)}';
    if (!_seenEntropy.add(entropyKey)) {
      return _rejectConnect(request, Cip186ErrorCode.sessionEntropyReuse,
          'session_entropy reused for this dApp host');
    }

    final sessionId = base64Url.encode(randomBytes(32)).replaceAll('=', '');
    final signingKey = deriveSessionSigningKey(
      walletRootSecret: _walletRootSecret,
      sessionEntropy: sessionEntropy,
      dappHost: dappHost,
      sessionId: sessionId,
    );
    final walletX = x.PrivateKey.generate();

    final address = _addressResolver != null
        ? await _addressResolver()
        : (await _wallet.getPaymentAddressKit(addressIndex: 0))
            .address
            .bech32Encoded;
    final chain = request.chain ?? 'cardano:preprod';
    final expiresAt = _now() + _sessionTtl;
    final sessionJson = jsonEncode(<String, dynamic>{
      'session': sessionId,
      'network': chain == 'cardano:mainnet' ? 1 : 0,
      'addresses': <String>[address],
      'chain': chain,
      'walletId': walletId,
      'expiresAt': expiresAt,
      'signingPublicKey':
          base64Url.encode(signingKey.verifyKey.asTypedList).replaceAll('=', ''),
    });

    final walletNonce = randomBytes(24);
    final ciphertext = naclBoxEncrypt(
      plaintext: Uint8List.fromList(utf8.encode(sessionJson)),
      nonce: walletNonce,
      walletSecret: walletX.asTypedList,
      dappPublic: request.dappKeyBytes!,
    );

    return DeepLinkOutcome.connectApproved(
      responseUri: AttestationBuilder.buildConnectApproved(
        redirect: request.redirectUri!,
        walletKey: walletX.publicKey.asTypedList,
        walletNonce: walletNonce,
        ciphertext: ciphertext,
      ),
      establishedSession: Cip186Session(
        walletX25519Secret: walletX.asTypedList,
        sessionSigningKey: signingKey,
        dappName: dappName,
        dappHost: dappHost,
        expiresAt: expiresAt,
      ),
      sessionId: sessionId,
    );
  }

  DeepLinkOutcome _rejectConnect(
      Cip186Request request, Cip186ErrorCode code, String message) {
    return DeepLinkOutcome.failure(
      responseUri: request.redirectUri != null
          ? AttestationBuilder.buildRejected(
              redirect: request.redirectUri!, code: code, message: message)
          : null,
      errorCode: code,
      errorMessage: message,
    );
  }

  static Uint8List _b64uDecode(String s) {
    final padded = s + ('=' * ((4 - s.length % 4) % 4));
    return Uint8List.fromList(base64Url.decode(padded));
  }

  static Uri? _maybeBuildErrorRedirect(Uri original, Cip186Exception e) {
    final raw = original.queryParameters['redirect'];
    if (raw == null) return null;
    final Uri target;
    try {
      target = Uri.parse(raw);
    } catch (_) {
      return null;
    }
    return AttestationBuilder.buildRejected(
      redirect: target,
      code: e.code,
      message: e.message,
    );
  }
}
