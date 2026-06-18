import 'package:cardano_dart_types/cardano_dart_types.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'deeplink_service.dart';

const String cip186MethodChannelName = 'com.yuti/cip30';
const String cip186WalletId = 'yuti';
const String cip186WalletScheme = 'cip30dl-yuti';

/// Native -> Flutter entry method names.
const String _methodHandleDeepLink = 'handleCip30DeepLink';

/// Fires the signed response deep-link back to the dApp's redirect.
typedef Cip186Launcher = Future<void> Function(Uri responseUri);

Future<void> _defaultLaunch(Uri uri) async {
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Routes a received CIP-186 deep-link URL to the service and owns the per-dApp
/// session store (keyed by the dApp X25519 public key carried in `dappKey`):
/// `connect` populates it, `signTx` consumes it. Pure + unit-testable — no
/// MethodChannel, no platform launch (the launcher is injectable).
class Cip186Router {
  Cip186Router({
    required this.service,
    required this.resolveWitnessAddresses,
    Cip186Launcher? launcher,
  }) : _launch = launcher ?? _defaultLaunch;

  final Cip186DeepLinkService service;

  /// Addresses the wallet will witness with for a signTx (e.g. its payment
  /// address). Resolved per request so no key material is cached.
  final Future<Set<String>> Function() resolveWitnessAddresses;

  final Cip186Launcher _launch;
  final Map<String, Cip186Session> _sessions = <String, Cip186Session>{};

  /// Drive one inbound deep-link URL end-to-end and fire the response.
  /// Returns the response URL string (for the platform channel result).
  Future<String?> route(String rawUrl) async {
    final uri = Uri.parse(rawUrl);
    final dappKey = uri.queryParameters['dappKey'] ?? '';
    final method = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;

    final DeepLinkOutcome outcome;
    if (method == 'signTx') {
      final session = _sessions[dappKey];
      final decoder = session == null
          ? null
          : SignTxPayloadDecoder.naclBox(
              walletX25519Secret: session.walletX25519Secret,
              witnessAddresses: await resolveWitnessAddresses(),
            );
      outcome = await service.handle(
        url: uri,
        signTxSemantics: decoder,
        session: session,
      );
    } else {
      // connect (and any future session-establishing method).
      outcome = await service.handle(url: uri);
      final established = outcome.establishedSession;
      if (established != null && dappKey.isNotEmpty) {
        _sessions[dappKey] = established;
      }
    }

    if (outcome.responseUri != null) {
      await _launch(outcome.responseUri!);
    }
    return outcome.responseUri?.toString();
  }
}

/// Registers the CIP-186 MethodChannel over a single persistent [Cip186Router]
/// (so replay/entropy/session state survives across requests). The router +
/// service are created lazily on the first deep-link, once the wallet is
/// resolvable. [launcher] is injectable for tests.
void registerCip186Channel({
  required Future<CardanoWallet> Function() resolveWallet,
  required Uint8List Function() walletRootSecret,
  required Future<Set<String>> Function() resolveWitnessAddresses,
  Cip186Launcher? launcher,
}) {
  Cip186Router? router;
  const channel = MethodChannel(cip186MethodChannelName);
  channel.setMethodCallHandler((call) async {
    if (call.method != _methodHandleDeepLink) {
      throw PlatformException(
        code: 'unimplemented',
        message: 'method ${call.method} is not handled',
      );
    }
    debugPrint('[cip186] channel received $_methodHandleDeepLink');
    try {
      router ??= Cip186Router(
        service: Cip186DeepLinkService(
          wallet: await resolveWallet(),
          walletId: cip186WalletId,
          walletScheme: cip186WalletScheme,
          walletRootSecret: walletRootSecret(),
        ),
        resolveWitnessAddresses: resolveWitnessAddresses,
        launcher: launcher,
      );
      final result = await router!.route(call.arguments as String);
      debugPrint('[cip186] routed -> '
          '${result == null ? 'no response uri' : 'response launched'}');
      return result;
    } catch (e) {
      debugPrint('[cip186] handler error: $e');
      rethrow;
    }
  });
}
