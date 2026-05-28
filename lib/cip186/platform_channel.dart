import 'package:cardano_dart_types/cardano_dart_types.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'deeplink_service.dart';

const String cip186MethodChannelName = 'com.yuti/cip30';
const String cip186WalletId = 'yuti';
const String cip186WalletScheme = 'cip30dl-yuti';

/// Native -> Flutter entry method names.
const String _methodHandleDeepLink = 'handleCip30DeepLink';

/// Registers the CIP-186 MethodChannel.
///
/// [resolveWallet] lazily produces the active wallet at signing time so the
/// signing key never lives in memory between requests.
/// [resolveDecoder] returns the payload-decoder strategy (encrypted in
/// production; plaintext in tests).
void registerCip186Channel({
  required Future<CardanoWallet> Function() resolveWallet,
  required Future<SignTxPayloadDecoder> Function() resolveDecoder,
}) {
  const channel = MethodChannel(cip186MethodChannelName);
  channel.setMethodCallHandler((call) async {
    if (call.method != _methodHandleDeepLink) {
      throw PlatformException(
        code: 'unimplemented',
        message: 'method ${call.method} is not handled',
      );
    }
    final rawUrl = call.arguments as String;
    final wallet = await resolveWallet();
    final decoder = await resolveDecoder();
    final service = Cip186DeepLinkService(
      wallet: wallet,
      walletId: cip186WalletId,
      walletScheme: cip186WalletScheme,
    );
    final outcome = await service.handle(
      url: Uri.parse(rawUrl),
      signTxSemantics: decoder,
    );
    if (outcome.responseUri != null) {
      await launchUrl(outcome.responseUri!, mode: LaunchMode.externalApplication);
    }
    return outcome.responseUri?.toString();
  });
}
