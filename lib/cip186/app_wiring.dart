import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cardano_dart_types/cardano_dart_types.dart';
import 'package:cardano_flutter_sdk/cardano_flutter_sdk.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pinenacl/ed25519.dart' as ed;

import 'approval_dialog.dart';
import 'crypto.dart';
import 'deeplink_service.dart';
import 'platform_channel.dart';

/// Global navigator key so the CIP-186 deep-link handler — which runs outside
/// any widget — can present the user-consent sheet. Wired into MaterialApp.
final GlobalKey<NavigatorState> cip186NavigatorKey = GlobalKey<NavigatorState>();

/// Completes once the app is past its splash screen, so a deep-link that
/// cold-starts the wallet waits for a stable navigator before prompting (rather
/// than racing the splash→home route replacement). Signalled by the splash.
final Completer<void> _cip186UiReady = Completer<void>();

void markCip186UiReady() {
  if (!_cip186UiReady.isCompleted) _cip186UiReady.complete();
}

/// Secure-storage keys.
const String _mnemonicKey = 'wallet_mnemonic'; // shared with WalletService
const String _rootSecretKey = 'cip186_root_secret';

/// Wires the CIP-186 deep-link signing channel into the running app. Call ONCE
/// at startup (replaces the legacy parking handler). [isMainnet] MUST reflect
/// the active wallet's network — it drives key derivation, so a wrong value
/// produces wrong addresses/signatures. Pass it from the app's wallet config;
/// there is deliberately no default.
///
/// Resolution is lazy: keys are read from secure storage only when a deep-link
/// actually arrives. If no wallet is loaded yet, signing requests fail cleanly
/// (the dApp can retry after the user unlocks).
Future<void> setupCip186Signing({
  required bool isMainnet,
  Cip186Launcher? launcher,
}) async {
  const storage = FlutterSecureStorage();

  // Persistent wallet-internal secret for HKDF session-key derivation. NOT the
  // CIP-1852 root / stake / DRep key. Generated once, then reused.
  var rootB64 = await storage.read(key: _rootSecretKey);
  if (rootB64 == null) {
    rootB64 = base64Url.encode(randomBytes(32));
    await storage.write(key: _rootSecretKey, value: rootB64);
  }
  final rootSecret = Uint8List.fromList(base64Url.decode(rootB64));
  final network = isMainnet ? NetworkId.mainnet : NetworkId.testnet;

  Future<CardanoWallet> resolveWallet() async {
    final mnemonic = await storage.read(key: _mnemonicKey);
    if (mnemonic == null) {
      throw StateError('CIP-186: no wallet loaded — unlock the wallet first');
    }
    return WalletFactory.fromMnemonic(network, mnemonic.split(' '));
  }

  // CIP-1852 address derivation is slow on some devices; memoize + persist it
  // so connect/signTx don't re-derive on every request.
  final addressCache = _Cip186AddressCache(
    storage: storage,
    network: network,
    resolveWallet: resolveWallet,
  );

  registerCip186Channel(
    resolveWallet: resolveWallet,
    walletRootSecret: () => rootSecret,
    resolveWitnessAddresses: () async => {await addressCache.resolve()},
    approval: _promptApproval,
    sessionStore: _SecureCip186SessionStore(storage, network),
    addressResolver: addressCache.resolve,
  );

  // Warm the cache in the background so the first connect isn't slow. Swallows
  // the "no wallet yet" error — it'll resolve on the first real request.
  unawaited(addressCache.resolve().then((_) {}, onError: (_) {}));
}

/// Memoizes + persists the wallet's payment address. In-flight de-dup ensures a
/// concurrent connect + prewarm derive at most once. Keyed by network + a hash
/// of the mnemonic, so changing wallets re-derives rather than returning stale.
class _Cip186AddressCache {
  _Cip186AddressCache({
    required this.storage,
    required this.network,
    required this.resolveWallet,
  });

  final FlutterSecureStorage storage;
  final NetworkId network;
  final Future<CardanoWallet> Function() resolveWallet;

  String? _cached;
  Future<String>? _inFlight;

  Future<String> resolve() {
    final c = _cached;
    if (c != null) return Future<String>.value(c);
    return _inFlight ??= _resolve();
  }

  Future<String> _resolve() async {
    try {
      final mnemonic = await storage.read(key: _mnemonicKey) ?? '';
      final key = 'cip186_addr_${base64Url.encode(sha256Bytes(utf8.encode('$network:$mnemonic'))).replaceAll('=', '').substring(0, 22)}';
      final stored = await storage.read(key: key);
      if (stored != null && stored.isNotEmpty) {
        _cached = stored;
        return stored;
      }
      final wallet = await resolveWallet();
      final addr =
          (await wallet.getPaymentAddressKit(addressIndex: 0)).address.bech32Encoded;
      await storage.write(key: key, value: addr);
      _cached = addr;
      return addr;
    } finally {
      _inFlight = null;
    }
  }
}

/// Presents the user-consent sheet via the global navigator. Waits for the app
/// to be past its splash (so a cold-start deep-link gets a stable navigator),
/// then fails closed: if still no context, the request is rejected, not signed.
Future<bool> _promptApproval(Cip186ApprovalRequest request) async {
  try {
    await _cip186UiReady.future.timeout(const Duration(seconds: 15));
  } catch (_) {}
  final context = cip186NavigatorKey.currentContext;
  if (context == null) return false;
  return showCip186ApprovalDialog(context, request);
}

/// Persists `connect` sessions to encrypted storage so a signTx survives the
/// wallet being killed and cold-started between the two deep-links. Sessions
/// are evicted once past their `expiresAt`.
class _SecureCip186SessionStore implements Cip186SessionStore {
  _SecureCip186SessionStore(this._storage, this._network);

  final FlutterSecureStorage _storage;
  final NetworkId _network;

  /// Namespaced by the active wallet (network + mnemonic hash) so a session
  /// established under one wallet is never consumed under another after a
  /// wallet switch — a different wallet simply finds no session (fail closed,
  /// dApp must reconnect). Mirrors [_Cip186AddressCache]'s keying.
  Future<String> _key(String dappKey) async {
    final mnemonic = await _storage.read(key: _mnemonicKey) ?? '';
    final wallet = base64Url
        .encode(sha256Bytes(utf8.encode('$_network:$mnemonic')))
        .replaceAll('=', '')
        .substring(0, 16);
    final dk = base64Url.encode(utf8.encode(dappKey)).replaceAll('=', '');
    return 'cip186_sess_${wallet}_$dk';
  }

  int get _nowEpoch => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  @override
  Future<void> put(String dappKey, Cip186Session session) async {
    final json = jsonEncode(<String, dynamic>{
      'x': base64Url.encode(session.walletX25519Secret),
      'sk': base64Url.encode(session.sessionSigningKey.seed),
      'name': session.dappName,
      'host': session.dappHost,
      'exp': session.expiresAt,
    });
    await _storage.write(key: await _key(dappKey), value: json);
  }

  @override
  Future<Cip186Session?> get(String dappKey) async {
    final key = await _key(dappKey);
    final raw = await _storage.read(key: key);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final exp = m['exp'] as int?;
      if (exp != null && _nowEpoch > exp) {
        await _storage.delete(key: key);
        return null;
      }
      return Cip186Session(
        walletX25519Secret:
            Uint8List.fromList(base64Url.decode(m['x'] as String)),
        sessionSigningKey: ed.SigningKey(
            seed: Uint8List.fromList(base64Url.decode(m['sk'] as String))),
        dappName: m['name'] as String?,
        dappHost: m['host'] as String?,
        expiresAt: exp,
      );
    } catch (_) {
      return null;
    }
  }
}
