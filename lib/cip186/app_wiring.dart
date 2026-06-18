import 'dart:convert';
import 'dart:typed_data';

import 'package:cardano_dart_types/cardano_dart_types.dart';
import 'package:cardano_flutter_sdk/cardano_flutter_sdk.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'crypto.dart';
import 'platform_channel.dart';

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

  registerCip186Channel(
    resolveWallet: resolveWallet,
    walletRootSecret: () => rootSecret,
    resolveWitnessAddresses: () async {
      final wallet = await resolveWallet();
      final addr =
          (await wallet.getPaymentAddressKit(addressIndex: 0)).address.bech32Encoded;
      return {addr};
    },
  );
}
