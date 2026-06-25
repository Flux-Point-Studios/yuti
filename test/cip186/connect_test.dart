@Tags(['cip186-signing'])

import 'dart:convert';
import 'dart:typed_data';

import 'package:cardano_dart_types/cardano_dart_types.dart';
import 'package:cardano_flutter_sdk/cardano_flutter_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/x25519.dart' as x;
import 'package:yuti/cip186/attestation.dart';
import 'package:yuti/cip186/crypto.dart';
import 'package:yuti/cip186/deeplink_service.dart';
import 'package:yuti/cip186/errors.dart';

const String _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon art';

String _b64u(Uint8List b) => base64Url.encode(b).replaceAll('=', '');
Uint8List _b64uDecode(String s) =>
    Uint8List.fromList(base64Url.decode(s + ('=' * ((4 - s.length % 4) % 4))));

Future<CardanoWallet> _wallet() async =>
    WalletFactory.fromMnemonic(NetworkId.testnet, _mnemonic.split(' '));

Uri _connectUrl(x.PrivateKey dapp, Uint8List nonce) {
  final dappInfo = _b64u(Uint8List.fromList(utf8.encode(
      '{"name":"Aegis","url":"https://aegis.fluxpointstudios.com","iconUrl":"https://x/i.png"}')));
  return Uri.parse(
    'cip30dl-yuti:/v1/connect?v=1'
    '&dapp=$dappInfo'
    '&dappKey=${_b64u(dapp.publicKey.asTypedList)}'
    '&redirect=https%3A%2F%2Faegis.fluxpointstudios.com%2Fcb'
    '&chain=cardano%3Apreprod'
    '&nonce=${_b64u(nonce)}',
  );
}

void main() {
  group('connect handshake (spec §connect)', () {
    test('establishes a session: encrypted session-json + verifiable signingPublicKey',
        () async {
      final wallet = await _wallet();
      final dapp = x.PrivateKey.generate();
      final service = Cip186DeepLinkService(
        wallet: wallet,
        walletId: 'yuti',
        walletScheme: 'cip30dl-yuti',
        walletRootSecret: Uint8List.fromList(List.filled(32, 42)),
        clockEpochSeconds: () => 1810000000,
      );

      final outcome = await service.handle(
        url: _connectUrl(dapp, Uint8List.fromList(List.generate(24, (i) => i + 3))),
      );

      final resp = outcome.responseUri!;
      expect(resp.queryParameters['response'], 'approved');
      expect(resp.queryParameters['walletKey'], isNotNull);
      expect(outcome.establishedSession, isNotNull);

      // dApp decrypts the session JSON with its own secret + the wallet key.
      final walletKey = _b64uDecode(resp.queryParameters['walletKey']!);
      final sessionJsonBytes = naclBoxDecrypt(
        ciphertext: _b64uDecode(resp.queryParameters['payload']!),
        nonce: _b64uDecode(resp.queryParameters['nonce']!),
        walletSecret: dapp.asTypedList,
        dappPublic: walletKey,
      );
      final sessionJson =
          jsonDecode(utf8.decode(sessionJsonBytes)) as Map<String, dynamic>;

      expect(sessionJson['walletId'], 'yuti');
      expect(sessionJson['chain'], 'cardano:preprod');
      expect(sessionJson['network'], 0);
      expect((sessionJson['addresses'] as List), isNotEmpty);
      expect(sessionJson['expiresAt'], 1810000000 + 3600);
      expect(sessionJson['session'], outcome.sessionId);

      // The advertised signingPublicKey is the established session's vkey, so
      // the dApp can verify every subsequent response.
      final advertised = _b64uDecode(sessionJson['signingPublicKey'] as String);
      expect(advertised.length, 32);
      expect(advertised,
          outcome.establishedSession!.sessionSigningKey.verifyKey.asTypedList);
    });

    test('signs the connect response over the canonical subject and echoes the request nonce',
        () async {
      final wallet = await _wallet();
      final dapp = x.PrivateKey.generate();
      final reqNonce = Uint8List.fromList(List.generate(24, (i) => i + 3));
      final service = Cip186DeepLinkService(
        wallet: wallet,
        walletId: 'yuti',
        walletScheme: 'cip30dl-yuti',
        walletRootSecret: Uint8List.fromList(List.filled(32, 42)),
        clockEpochSeconds: () => 1810000000,
      );

      final outcome = await service.handle(url: _connectUrl(dapp, reqNonce));
      final resp = outcome.responseUri!;

      // Domain tag + a verbatim echo of the dApp's request nonce.
      expect(resp.queryParameters['method'], 'connect');
      expect(_b64uDecode(resp.queryParameters['echo']!), reqNonce);
      expect(resp.queryParameters['signature'], isNotNull);

      // The signature is the session key's signature over the exact canonical
      // subject the dApp re-derives (signature stripped). Ed25519 is
      // deterministic, so re-signing reproduces the identical bytes — proving
      // the dApp's verification against the advertised signingPublicKey holds.
      final subject = AttestationBuilder.canonicalSubject(resp);
      final expectedSig = signCanonicalSubject(
        signingKey: outcome.establishedSession!.sessionSigningKey,
        canonicalSubject: subject,
      );
      expect(_b64uDecode(resp.queryParameters['signature']!), expectedSig);
    });

    test('rejects -9 when the connect request omits the nonce', () async {
      final wallet = await _wallet();
      final dapp = x.PrivateKey.generate();
      final service = Cip186DeepLinkService(
        wallet: wallet,
        walletId: 'yuti',
        walletScheme: 'cip30dl-yuti',
        walletRootSecret: Uint8List.fromList(List.filled(32, 42)),
      );
      final dappInfo = _b64u(Uint8List.fromList(utf8.encode(
          '{"name":"Aegis","url":"https://aegis.fluxpointstudios.com"}')));
      final url = Uri.parse(
        'cip30dl-yuti:/v1/connect?v=1'
        '&dapp=$dappInfo'
        '&dappKey=${_b64u(dapp.publicKey.asTypedList)}'
        '&redirect=https%3A%2F%2Faegis.fluxpointstudios.com%2Fcb'
        '&chain=cardano%3Apreprod', // no nonce
      );
      final outcome = await service.handle(url: url);
      expect(outcome.errorCode, Cip186ErrorCode.unsupportedVersion);
      expect(outcome.responseUri!.queryParameters['response'], 'rejected');
    });

    test('rejects -12 when session_entropy is reused for the same dApp host',
        () async {
      final wallet = await _wallet();
      final dapp = x.PrivateKey.generate();
      final service = Cip186DeepLinkService(
        wallet: wallet,
        walletId: 'yuti',
        walletScheme: 'cip30dl-yuti',
        walletRootSecret: Uint8List.fromList(List.filled(32, 42)),
        // Fixed entropy source -> the second connect reuses it.
        sessionEntropySource: () => Uint8List.fromList(List.filled(32, 5)),
      );

      final first = await service.handle(
          url: _connectUrl(dapp, Uint8List.fromList(List.generate(24, (i) => i + 3))));
      final second = await service.handle(
          url: _connectUrl(dapp, Uint8List.fromList(List.generate(24, (i) => i + 9))));

      expect(first.responseUri!.queryParameters['response'], 'approved');
      expect(second.errorCode, Cip186ErrorCode.sessionEntropyReuse);
      expect(second.responseUri!.queryParameters['errorCode'], '-12');
    });

    test('rejects malformed dapp-info-json with -9', () async {
      final wallet = await _wallet();
      final dapp = x.PrivateKey.generate();
      final service = Cip186DeepLinkService(
        wallet: wallet,
        walletId: 'yuti',
        walletScheme: 'cip30dl-yuti',
        walletRootSecret: Uint8List.fromList(List.filled(32, 42)),
      );
      final url = Uri.parse(
        'cip30dl-yuti:/v1/connect?v=1'
        '&dapp=${_b64u(Uint8List.fromList(utf8.encode("not json")))}'
        '&dappKey=${_b64u(dapp.publicKey.asTypedList)}'
        '&redirect=https%3A%2F%2Faegis.fluxpointstudios.com%2Fcb'
        '&chain=cardano%3Apreprod'
        '&nonce=${_b64u(Uint8List.fromList(List.generate(24, (i) => i + 1)))}',
      );
      final outcome = await service.handle(url: url);
      expect(outcome.errorCode, Cip186ErrorCode.unsupportedVersion);
      expect(outcome.responseUri!.queryParameters['response'], 'rejected');
    });
  });
}
