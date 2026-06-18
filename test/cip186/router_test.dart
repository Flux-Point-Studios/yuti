@Tags(['cip186-signing'])

import 'dart:convert';
import 'dart:typed_data';

import 'package:cardano_dart_types/cardano_dart_types.dart';
import 'package:cardano_flutter_sdk/cardano_flutter_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:pinenacl/x25519.dart' as x;
import 'package:yuti/cip186/attestation.dart';
import 'package:yuti/cip186/crypto.dart';
import 'package:yuti/cip186/deeplink_service.dart';
import 'package:yuti/cip186/platform_channel.dart';

const String _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon art';
const String _txHex = '84a40080018002000300a0f5f6';

String _b64u(Uint8List b) => base64Url.encode(b).replaceAll('=', '');
Uint8List _b64uDecode(String s) =>
    Uint8List.fromList(base64Url.decode(s + ('=' * ((4 - s.length % 4) % 4))));

void main() {
  test('connect -> signTx routes through the session store end-to-end',
      () async {
    final wallet = await WalletFactory.fromMnemonic(
        NetworkId.testnet, _mnemonic.split(' '));
    final address =
        (await wallet.getPaymentAddressKit(addressIndex: 0)).address.bech32Encoded;

    final service = Cip186DeepLinkService(
      wallet: wallet,
      walletId: 'yuti',
      walletScheme: 'cip30dl-yuti',
      walletRootSecret: Uint8List.fromList(List.filled(32, 7)),
      clockEpochSeconds: () => 1810000000,
    );
    final launched = <Uri>[];
    final router = Cip186Router(
      service: service,
      resolveWitnessAddresses: () async => {address},
      launcher: (u) async => launched.add(u),
    );

    // The dApp uses ONE X25519 keypair across connect + signTx (its `dappKey`).
    final dapp = x.PrivateKey.generate();
    final dappKeyB64 = _b64u(dapp.publicKey.asTypedList);

    // ---- 1. connect ----
    final dappInfo = _b64u(Uint8List.fromList(utf8.encode(
        '{"name":"Aegis","url":"https://aegis.fluxpointstudios.com"}')));
    await router.route(
      'cip30dl-yuti:/v1/connect?v=1'
      '&dapp=$dappInfo'
      '&dappKey=$dappKeyB64'
      '&redirect=https%3A%2F%2Faegis.fluxpointstudios.com%2Fcb'
      '&chain=cardano%3Apreprod'
      '&nonce=${_b64u(Uint8List.fromList(List.generate(24, (i) => i + 1)))}',
    );
    final connectResp = launched.last;
    expect(connectResp.queryParameters['response'], 'approved');

    final walletKey = _b64uDecode(connectResp.queryParameters['walletKey']!);
    final sessionJson = jsonDecode(utf8.decode(naclBoxDecrypt(
      ciphertext: _b64uDecode(connectResp.queryParameters['payload']!),
      nonce: _b64uDecode(connectResp.queryParameters['nonce']!),
      walletSecret: dapp.asTypedList,
      dappPublic: walletKey,
    ))) as Map<String, dynamic>;
    final sessionId = sessionJson['session'] as String;
    final signingPub = _b64uDecode(sessionJson['signingPublicKey'] as String);

    // ---- 2. signTx (same dappKey -> store finds the connect session) ----
    final commit =
        CardanoTransaction.deserializeFromHex(_txHex).body.computeBlake2bHash256();
    final reqNonce = Uint8List.fromList(List.generate(24, (i) => i + 50));
    final reqCipher = naclBoxEncrypt(
      plaintext: Uint8List.fromList(utf8.encode(
          '{"session":"$sessionId","tx":"$_txHex","partialSign":true,"vkeyHints":[]}')),
      nonce: reqNonce,
      walletSecret: dapp.asTypedList,
      dappPublic: walletKey, // encrypt to the wallet's connect-time X25519 key
    );
    await router.route(
      'cip30dl-yuti:/v1/signTx?v=1'
      '&dappKey=$dappKeyB64'
      '&redirect=https%3A%2F%2Faegis.fluxpointstudios.com%2Fcb'
      '&nonce=${_b64u(reqNonce)}'
      '&commit=${_b64u(commit)}'
      '&ttl=1810000300'
      '&payload=${_b64u(reqCipher)}',
    );
    final signResp = launched.last;
    expect(signResp.queryParameters['response'], 'approved');

    // The witness CBOR decrypts on the dApp side.
    final witnessCbor = naclBoxDecrypt(
      ciphertext: _b64uDecode(signResp.queryParameters['payload']!),
      nonce: _b64uDecode(signResp.queryParameters['nonce']!),
      walletSecret: dapp.asTypedList,
      dappPublic: walletKey,
    );
    expect(() => WitnessSet.deserializeBytes(witnessCbor), returnsNormally);

    // The signTx response verifies against the key advertised at CONNECT.
    final subject = AttestationBuilder.canonicalSubject(signResp);
    final ok = ed.VerifyKey(signingPub).verify(
      signature: ed.Signature(_b64uDecode(signResp.queryParameters['signature']!)),
      message: Uint8List.fromList(utf8.encode(subject)),
    );
    expect(ok, isTrue);
  });

  test('signTx with no prior connect -> rejected -3 SessionExpired', () async {
    final wallet = await WalletFactory.fromMnemonic(
        NetworkId.testnet, _mnemonic.split(' '));
    final service = Cip186DeepLinkService(
      wallet: wallet,
      walletId: 'yuti',
      walletScheme: 'cip30dl-yuti',
      walletRootSecret: Uint8List.fromList(List.filled(32, 7)),
      clockEpochSeconds: () => 1810000000,
    );
    final launched = <Uri>[];
    final router = Cip186Router(
      service: service,
      resolveWitnessAddresses: () async => const {},
      launcher: (u) async => launched.add(u),
    );
    final dapp = x.PrivateKey.generate();
    final commit =
        CardanoTransaction.deserializeFromHex(_txHex).body.computeBlake2bHash256();
    await router.route(
      'cip30dl-yuti:/v1/signTx?v=1'
      '&dappKey=${_b64u(dapp.publicKey.asTypedList)}'
      // Native-dApp custom-scheme callback: a no-session signTx still gets its
      // -3 (an unbindable https redirect would be dropped — see _safeRejected).
      '&redirect=aegisdemo%3A%2F%2Fcb'
      '&nonce=${_b64u(Uint8List.fromList(List.generate(24, (i) => i + 1)))}'
      '&commit=${_b64u(commit)}'
      '&ttl=1810000300'
      '&payload=${_b64u(Uint8List.fromList(utf8.encode("x")))}',
    );
    expect(launched.last.queryParameters['response'], 'rejected');
    expect(launched.last.queryParameters['errorCode'], '-3');
  });
}
