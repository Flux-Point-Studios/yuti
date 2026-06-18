@Tags(['cip186-signing'])

import 'dart:convert';
import 'dart:typed_data';

import 'package:cardano_dart_types/cardano_dart_types.dart';
import 'package:cardano_flutter_sdk/cardano_flutter_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:pinenacl/x25519.dart' as x;
import 'package:yuti/cip186/crypto.dart';
import 'package:yuti/cip186/deeplink_service.dart';
import 'package:yuti/cip186/errors.dart';
import 'package:yuti/cip186/uri_parser.dart';

const String _mnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon art';

const String _minimalTxHex = '84a40080018002000300a0f5f6';

String _b64u(Uint8List b) => base64Url.encode(b).replaceAll('=', '');
Uint8List _b64uDecode(String s) =>
    Uint8List.fromList(base64Url.decode(s + ('=' * ((4 - s.length % 4) % 4))));

Future<CardanoWallet> _wallet() async =>
    WalletFactory.fromMnemonic(NetworkId.testnet, _mnemonic.split(' '));

Uri _connectUrl(x.PrivateKey dapp) {
  final dappInfo = _b64u(Uint8List.fromList(utf8.encode(
      '{"name":"Aegis","url":"https://aegis.fluxpointstudios.com"}')));
  return Uri.parse('cip30dl-yuti:/v1/connect?v=1'
      '&dapp=$dappInfo'
      '&dappKey=${_b64u(dapp.publicKey.asTypedList)}'
      '&redirect=https%3A%2F%2Faegis.fluxpointstudios.com%2Fcb'
      '&chain=cardano%3Apreprod'
      '&nonce=${_b64u(Uint8List.fromList(List.generate(24, (i) => i + 3)))}');
}

void main() {
  group('User consent gate (spec §UserRejected)', () {
    test('connect: rejection -> -1 UserRejected, no session', () async {
      Cip186ApprovalRequest? seen;
      final service = Cip186DeepLinkService(
        wallet: await _wallet(),
        walletId: 'yuti',
        walletScheme: 'cip30dl-yuti',
        walletRootSecret: Uint8List.fromList(List.filled(32, 42)),
        approval: (req) async {
          seen = req;
          return false;
        },
      );
      final outcome = await service.handle(url: _connectUrl(x.PrivateKey.generate()));

      expect(outcome.errorCode, Cip186ErrorCode.userRejected);
      expect(outcome.responseUri!.queryParameters['response'], 'rejected');
      expect(outcome.responseUri!.queryParameters['errorCode'], '-1');
      expect(outcome.establishedSession, isNull);
      // The prompt was given the dApp identity.
      expect(seen!.method, Cip186Method.connect);
      expect(seen!.dappName, 'Aegis');
      expect(seen!.dappHost, 'aegis.fluxpointstudios.com');
    });

    test('connect: approval -> session established', () async {
      final service = Cip186DeepLinkService(
        wallet: await _wallet(),
        walletId: 'yuti',
        walletScheme: 'cip30dl-yuti',
        walletRootSecret: Uint8List.fromList(List.filled(32, 42)),
        approval: (req) async => true,
      );
      final outcome = await service.handle(url: _connectUrl(x.PrivateKey.generate()));

      expect(outcome.responseUri!.queryParameters['response'], 'approved');
      expect(outcome.establishedSession, isNotNull);
      expect(outcome.establishedSession!.dappName, 'Aegis');
    });

    test('signTx: rejection -> -1 UserRejected, nothing signed', () async {
      final wallet = await _wallet();
      final address =
          (await wallet.getPaymentAddressKit(addressIndex: 0)).address.bech32Encoded;
      final dapp = x.PrivateKey.generate();
      final walletX = x.PrivateKey.generate();
      final session = Cip186Session(
        walletX25519Secret: walletX.asTypedList,
        sessionSigningKey: ed.SigningKey.generate(),
        dappName: 'Aegis',
        dappHost: 'aegis.fluxpointstudios.com',
      );

      final commit =
          CardanoTransaction.deserializeFromHex(_minimalTxHex).body.computeBlake2bHash256();
      final reqNonce = Uint8List.fromList(List.generate(24, (i) => i + 7));
      final reqCipher = naclBoxEncrypt(
        plaintext: Uint8List.fromList(utf8.encode('{"tx":"$_minimalTxHex"}')),
        nonce: reqNonce,
        walletSecret: dapp.asTypedList,
        dappPublic: walletX.publicKey.asTypedList,
      );
      final url = Uri.parse('cip30dl-yuti:/v1/signTx?v=1'
          '&dappKey=${_b64u(dapp.publicKey.asTypedList)}'
          '&redirect=https%3A%2F%2Faegis.fluxpointstudios.com%2Fcb'
          '&nonce=${_b64u(reqNonce)}'
          '&commit=${_b64u(commit)}'
          '&ttl=1900000000'
          '&payload=${_b64u(reqCipher)}');

      Cip186ApprovalRequest? seen;
      final service = Cip186DeepLinkService(
        wallet: wallet,
        walletId: 'yuti',
        walletScheme: 'cip30dl-yuti',
        approval: (req) async {
          seen = req;
          return false;
        },
      );
      final outcome = await service.handle(
        url: url,
        signTxSemantics: SignTxPayloadDecoder.naclBox(
          walletX25519Secret: walletX.asTypedList,
          witnessAddresses: {address},
        ),
        session: session,
      );

      expect(outcome.errorCode, Cip186ErrorCode.userRejected);
      expect(outcome.responseUri!.queryParameters['errorCode'], '-1');
      expect(outcome.signResult, isNull);
      expect(seen!.method, Cip186Method.signTx);
      expect(seen!.dappName, 'Aegis');
      expect(seen!.txHashHex, _hex(commit));
    });

    test('signTx: approval -> signed response', () async {
      final wallet = await _wallet();
      final address =
          (await wallet.getPaymentAddressKit(addressIndex: 0)).address.bech32Encoded;
      final dapp = x.PrivateKey.generate();
      final walletX = x.PrivateKey.generate();
      final session = Cip186Session(
        walletX25519Secret: walletX.asTypedList,
        sessionSigningKey: ed.SigningKey.generate(),
      );

      final commit =
          CardanoTransaction.deserializeFromHex(_minimalTxHex).body.computeBlake2bHash256();
      final reqNonce = Uint8List.fromList(List.generate(24, (i) => i + 7));
      final reqCipher = naclBoxEncrypt(
        plaintext: Uint8List.fromList(utf8.encode('{"tx":"$_minimalTxHex"}')),
        nonce: reqNonce,
        walletSecret: dapp.asTypedList,
        dappPublic: walletX.publicKey.asTypedList,
      );
      final url = Uri.parse('cip30dl-yuti:/v1/signTx?v=1'
          '&dappKey=${_b64u(dapp.publicKey.asTypedList)}'
          '&redirect=https%3A%2F%2Faegis.fluxpointstudios.com%2Fcb'
          '&nonce=${_b64u(reqNonce)}'
          '&commit=${_b64u(commit)}'
          '&ttl=1900000000'
          '&payload=${_b64u(reqCipher)}');

      final service = Cip186DeepLinkService(
        wallet: wallet,
        walletId: 'yuti',
        walletScheme: 'cip30dl-yuti',
        approval: (req) async => true,
      );
      final outcome = await service.handle(
        url: url,
        signTxSemantics: SignTxPayloadDecoder.naclBox(
          walletX25519Secret: walletX.asTypedList,
          witnessAddresses: {address},
        ),
        session: session,
      );

      expect(outcome.responseUri!.queryParameters['response'], 'approved');
      expect(outcome.signResult, isNotNull);
    });
  });

  group('Address resolver + session expiry (review hardening)', () {
    test('connect publishes the address from the injected resolver', () async {
      const injected =
          'addr1qyqt0pru382hy9vjlsxv3ye02z50sfvt8xunscg5pgden77z73dpdfng2ctw2ekqplqgrljelz7h4dneac27nn3qx3rqrhqvwd';
      final service = Cip186DeepLinkService(
        wallet: await _wallet(),
        walletId: 'yuti',
        walletScheme: 'cip30dl-yuti',
        walletRootSecret: Uint8List.fromList(List.filled(32, 42)),
        approval: (req) async => true,
        addressResolver: () async => injected,
      );
      final dapp = x.PrivateKey.generate();
      final outcome = await service.handle(url: _connectUrl(dapp));
      final resp = outcome.responseUri!.queryParameters;
      final sessionJson = jsonDecode(utf8.decode(naclBoxDecrypt(
        ciphertext: _b64uDecode(resp['payload']!),
        nonce: _b64uDecode(resp['nonce']!),
        walletSecret: dapp.asTypedList,
        dappPublic: _b64uDecode(resp['walletKey']!),
      ))) as Map<String, dynamic>;
      // The witness address (resolveWitnessAddresses) is wired to the SAME
      // resolver in app_wiring, so this is the load-bearing consistency check.
      expect((sessionJson['addresses'] as List).first, injected);
    });

    test('signTx with an expired session -> -3 SessionExpired', () async {
      final wallet = await _wallet();
      final address =
          (await wallet.getPaymentAddressKit(addressIndex: 0)).address.bech32Encoded;
      final dapp = x.PrivateKey.generate();
      final walletX = x.PrivateKey.generate();
      final session = Cip186Session(
        walletX25519Secret: walletX.asTypedList,
        sessionSigningKey: ed.SigningKey.generate(),
        expiresAt: 1000, // long past
      );
      final commit =
          CardanoTransaction.deserializeFromHex(_minimalTxHex).body.computeBlake2bHash256();
      final reqNonce = Uint8List.fromList(List.generate(24, (i) => i + 7));
      final reqCipher = naclBoxEncrypt(
        plaintext: Uint8List.fromList(utf8.encode('{"tx":"$_minimalTxHex"}')),
        nonce: reqNonce,
        walletSecret: dapp.asTypedList,
        dappPublic: walletX.publicKey.asTypedList,
      );
      final url = Uri.parse('cip30dl-yuti:/v1/signTx?v=1'
          '&dappKey=${_b64u(dapp.publicKey.asTypedList)}'
          '&redirect=https%3A%2F%2Faegis.fluxpointstudios.com%2Fcb'
          '&nonce=${_b64u(reqNonce)}'
          '&commit=${_b64u(commit)}'
          '&ttl=1900000000' // request ttl is future, isolating session expiry
          '&payload=${_b64u(reqCipher)}');
      final service = Cip186DeepLinkService(
        wallet: wallet,
        walletId: 'yuti',
        walletScheme: 'cip30dl-yuti',
        approval: (req) async => true,
        clockEpochSeconds: () => 1810000000,
      );
      final outcome = await service.handle(
        url: url,
        signTxSemantics: SignTxPayloadDecoder.naclBox(
          walletX25519Secret: walletX.asTypedList,
          witnessAddresses: {address},
        ),
        session: session,
      );
      expect(outcome.errorCode, Cip186ErrorCode.sessionExpired);
      expect(outcome.responseUri!.queryParameters['errorCode'], '-3');
      expect(outcome.signResult, isNull);
    });
  });

  group('Redirect host binding (spec §-4 RedirectHostMismatch)', () {
    test('connect with a foreign redirect host -> -4, no session', () async {
      final service = Cip186DeepLinkService(
        wallet: await _wallet(),
        walletId: 'yuti',
        walletScheme: 'cip30dl-yuti',
        walletRootSecret: Uint8List.fromList(List.filled(32, 42)),
        // Consent alone must NOT override the host binding.
        approval: (req) async => true,
      );
      // dApp declares aegis.fluxpointstudios.com but points the reply elsewhere.
      final dappInfo = _b64u(Uint8List.fromList(utf8.encode(
          '{"name":"Aegis","url":"https://aegis.fluxpointstudios.com"}')));
      final url = Uri.parse('cip30dl-yuti:/v1/connect?v=1'
          '&dapp=$dappInfo'
          '&dappKey=${_b64u(x.PrivateKey.generate().publicKey.asTypedList)}'
          '&redirect=https%3A%2F%2Fevil.example%2Fcb'
          '&chain=cardano%3Apreprod'
          '&nonce=${_b64u(Uint8List.fromList(List.generate(24, (i) => i + 3)))}');
      final outcome = await service.handle(url: url);
      expect(outcome.errorCode, Cip186ErrorCode.redirectHostMismatch);
      expect(outcome.responseUri!.queryParameters['errorCode'], '-4');
      expect(outcome.establishedSession, isNull);
    });

    test('signTx whose redirect host != connected dApp -> -4, nothing signed',
        () async {
      final wallet = await _wallet();
      final address =
          (await wallet.getPaymentAddressKit(addressIndex: 0)).address.bech32Encoded;
      final dapp = x.PrivateKey.generate();
      final walletX = x.PrivateKey.generate();
      // Session was established with aegis; the signTx asks to reply to evil.
      final session = Cip186Session(
        walletX25519Secret: walletX.asTypedList,
        sessionSigningKey: ed.SigningKey.generate(),
        dappHost: 'aegis.fluxpointstudios.com',
      );
      final commit =
          CardanoTransaction.deserializeFromHex(_minimalTxHex).body.computeBlake2bHash256();
      final reqNonce = Uint8List.fromList(List.generate(24, (i) => i + 7));
      final reqCipher = naclBoxEncrypt(
        plaintext: Uint8List.fromList(utf8.encode('{"tx":"$_minimalTxHex"}')),
        nonce: reqNonce,
        walletSecret: dapp.asTypedList,
        dappPublic: walletX.publicKey.asTypedList,
      );
      final url = Uri.parse('cip30dl-yuti:/v1/signTx?v=1'
          '&dappKey=${_b64u(dapp.publicKey.asTypedList)}'
          '&redirect=https%3A%2F%2Fevil.example%2Fcb'
          '&nonce=${_b64u(reqNonce)}'
          '&commit=${_b64u(commit)}'
          '&ttl=1900000000'
          '&payload=${_b64u(reqCipher)}');
      final service = Cip186DeepLinkService(
        wallet: wallet,
        walletId: 'yuti',
        walletScheme: 'cip30dl-yuti',
        approval: (req) async => true,
      );
      final outcome = await service.handle(
        url: url,
        signTxSemantics: SignTxPayloadDecoder.naclBox(
          walletX25519Secret: walletX.asTypedList,
          witnessAddresses: {address},
        ),
        session: session,
      );
      expect(outcome.errorCode, Cip186ErrorCode.redirectHostMismatch);
      expect(outcome.responseUri!.queryParameters['errorCode'], '-4');
      expect(outcome.signResult, isNull);
    });
  });
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
