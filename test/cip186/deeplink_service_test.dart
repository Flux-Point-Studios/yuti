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
import 'package:yuti/cip186/errors.dart';

const String _testMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon art';

const String _minimalConwayTxHex = '84a40080018002000300a0f5f6';

const String _dappKeyB64 = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE';
const String _nonceB64 = 'AgICAgICAgICAgICAgICAgICAgICAgIC';

Future<CardanoWallet> _wallet() async => WalletFactory.fromMnemonic(
      NetworkId.testnet,
      _testMnemonic.split(' '),
    );

String _b64uNoPad(Uint8List bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List _commitOfTxHex(String hex) {
  final tx = CardanoTransaction.deserializeFromHex(hex);
  return tx.body.computeBlake2bHash256();
}

String _pad(String s) => s + ('=' * ((4 - s.length % 4) % 4));

Uint8List _b64uDecode(String s) =>
    Uint8List.fromList(base64Url.decode(_pad(s)));

/// A throwaway session for tests: a fresh ephemeral X25519 secret + an Ed25519
/// session signing key. (In production `connect` derives these.)
Cip186Session _testSession() => Cip186Session(
      walletX25519Secret: x.PrivateKey.generate().asTypedList,
      sessionSigningKey: ed.SigningKey.generate(),
    );

void main() {
  group(
      'Cip186DeepLinkService E2E — receive-decode-sign-respond '
      '(spec §Reference flow diagram)', () {
    test('processes a valid plaintext-payload signTx URL end-to-end',
        () async {
      final wallet = await _wallet();
      final kit = await wallet.getPaymentAddressKit(addressIndex: 0);
      final address = kit.address.bech32Encoded;
      final service = Cip186DeepLinkService(
        wallet: wallet,
        walletId: 'yuti',
        walletScheme: 'cip30dl-yuti',
      );

      final commit = _commitOfTxHex(_minimalConwayTxHex);
      final commitB64 = _b64uNoPad(commit);

      // Plaintext-payload mode (encryption test below). signTx-json shape per spec.
      const payloadJson =
          '{"session":"sess-1","tx":"$_minimalConwayTxHex","partialSign":true,"vkeyHints":[]}';
      final payloadB64 = _b64uNoPad(Uint8List.fromList(payloadJson.codeUnits));

      final url = Uri.parse(
        'cip30dl-yuti:/v1/signTx?v=1'
        '&dappKey=$_dappKeyB64'
        '&redirect=https%3A%2F%2Faegis.example%2Fcb'
        '&nonce=$_nonceB64'
        '&commit=$commitB64'
        '&ttl=1810000300'
        '&payload=$payloadB64',
      );

      final outcome = await service.handle(
        url: url,
        signTxSemantics: SignTxPayloadDecoder.plaintextJson(
          witnessAddresses: {address},
        ),
        session: _testSession(),
      );

      expect(outcome.responseUri, isNotNull);
      expect(outcome.responseUri!.queryParameters['response'], 'approved');
      expect(outcome.responseUri!.queryParameters['payload'], isNotNull);
    });

    test('full-loop rejection: commit-mismatch URL gets errorCode=-2 callback',
        () async {
      final wallet = await _wallet();
      final kit = await wallet.getPaymentAddressKit(addressIndex: 0);
      final address = kit.address.bech32Encoded;
      final service = Cip186DeepLinkService(
        wallet: wallet,
        walletId: 'yuti',
        walletScheme: 'cip30dl-yuti',
      );

      final wrongCommit = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        wrongCommit[i] = 0xff;
      }
      final wrongCommitB64 = _b64uNoPad(wrongCommit);

      const payloadJson =
          '{"session":"sess-1","tx":"$_minimalConwayTxHex","partialSign":true,"vkeyHints":[]}';
      final payloadB64 = _b64uNoPad(Uint8List.fromList(payloadJson.codeUnits));

      final url = Uri.parse(
        'cip30dl-yuti:/v1/signTx?v=1'
        '&dappKey=$_dappKeyB64'
        '&redirect=https%3A%2F%2Faegis.example%2Fcb'
        '&nonce=$_nonceB64'
        '&commit=$wrongCommitB64'
        '&ttl=1810000300'
        '&payload=$payloadB64',
      );

      final outcome = await service.handle(
        url: url,
        signTxSemantics: SignTxPayloadDecoder.plaintextJson(
          witnessAddresses: {address},
        ),
        session: _testSession(),
      );

      expect(outcome.responseUri!.queryParameters['response'], 'rejected');
      expect(outcome.responseUri!.queryParameters['errorCode'], '-2');
      expect(outcome.errorCode, Cip186ErrorCode.commitMismatch);
    });
  });

  group('payload.tx type-guard (MUST-FIX #2 — no uncaught CastError)', () {
    Future<DeepLinkOutcome> runWithPayload(String payloadJson) async {
      final wallet = await _wallet();
      final kit = await wallet.getPaymentAddressKit(addressIndex: 0);
      final address = kit.address.bech32Encoded;
      final service = Cip186DeepLinkService(
        wallet: wallet,
        walletId: 'yuti',
        walletScheme: 'cip30dl-yuti',
      );
      final commitB64 = _b64uNoPad(_commitOfTxHex(_minimalConwayTxHex));
      final payloadB64 = _b64uNoPad(Uint8List.fromList(payloadJson.codeUnits));
      final url = Uri.parse(
        'cip30dl-yuti:/v1/signTx?v=1'
        '&dappKey=$_dappKeyB64'
        '&redirect=https%3A%2F%2Faegis.example%2Fcb'
        '&nonce=$_nonceB64'
        '&commit=$commitB64'
        '&ttl=1810000300'
        '&payload=$payloadB64',
      );
      return service.handle(
        url: url,
        signTxSemantics: SignTxPayloadDecoder.plaintextJson(
          witnessAddresses: {address},
        ),
        session: _testSession(),
      );
    }

    for (final entry in <String, String>{
      'number': '{"session":"s","tx":123,"partialSign":true,"vkeyHints":[]}',
      'bool': '{"session":"s","tx":true,"partialSign":true,"vkeyHints":[]}',
      'list': '{"session":"s","tx":[],"partialSign":true,"vkeyHints":[]}',
      'object': '{"session":"s","tx":{},"partialSign":true,"vkeyHints":[]}',
    }.entries) {
      test('tx as ${entry.key} -> rejected -9, never throws', () async {
        final outcome = await runWithPayload(entry.value);
        expect(outcome.responseUri!.queryParameters['response'], 'rejected');
        expect(outcome.errorCode, Cip186ErrorCode.unsupportedVersion);
        expect(outcome.errorMessage, contains('hex string'));
      });
    }

    test('tx missing -> rejected -9 (missing message)', () async {
      final outcome =
          await runWithPayload('{"session":"s","partialSign":true}');
      expect(outcome.responseUri!.queryParameters['response'], 'rejected');
      expect(outcome.errorCode, Cip186ErrorCode.unsupportedVersion);
      expect(outcome.errorMessage, contains('missing'));
    });
  });

  group('Full NaCl-box envelope (MUST-FIX #1 — real response crypto)', () {
    test('decrypts the request + returns an encrypted, signed response',
        () async {
      final wallet = await _wallet();
      final kit = await wallet.getPaymentAddressKit(addressIndex: 0);
      final address = kit.address.bech32Encoded;

      final dapp = x.PrivateKey.generate();
      final walletX = x.PrivateKey.generate();
      final session = Cip186Session(
        walletX25519Secret: walletX.asTypedList,
        sessionSigningKey: ed.SigningKey.generate(),
      );

      final commit = _commitOfTxHex(_minimalConwayTxHex);
      final reqNonce = Uint8List.fromList(List.generate(24, (i) => i + 7));
      const payloadJson =
          '{"session":"s","tx":"$_minimalConwayTxHex","partialSign":true,"vkeyHints":[]}';
      // dApp -> wallet: encrypt the signTx-json to the wallet's session X25519 key.
      final reqCipher = naclBoxEncrypt(
        plaintext: Uint8List.fromList(utf8.encode(payloadJson)),
        nonce: reqNonce,
        walletSecret: dapp.asTypedList,
        dappPublic: walletX.publicKey.asTypedList,
      );

      final url = Uri.parse(
        'cip30dl-yuti:/v1/signTx?v=1'
        '&dappKey=${_b64uNoPad(dapp.publicKey.asTypedList)}'
        '&redirect=https%3A%2F%2Faegis.example%2Fcb'
        '&nonce=${_b64uNoPad(reqNonce)}'
        '&commit=${_b64uNoPad(commit)}'
        '&ttl=1810000300'
        '&payload=${_b64uNoPad(reqCipher)}',
      );

      final service = Cip186DeepLinkService(
          wallet: wallet, walletId: 'yuti', walletScheme: 'cip30dl-yuti');
      final outcome = await service.handle(
        url: url,
        signTxSemantics: SignTxPayloadDecoder.naclBox(
          walletX25519Secret: walletX.asTypedList,
          witnessAddresses: {address},
        ),
        session: session,
      );

      final resp = outcome.responseUri!;
      expect(resp.queryParameters['response'], 'approved');

      // (a) the response nonce is fresh (24 bytes, not all zeros).
      final respNonce = _b64uDecode(resp.queryParameters['nonce']!);
      expect(respNonce.length, 24);
      expect(respNonce.any((b) => b != 0), isTrue);

      // (b) the response payload decrypts (dApp side) to exactly the witness CBOR.
      final witnessCbor = naclBoxDecrypt(
        ciphertext: _b64uDecode(resp.queryParameters['payload']!),
        nonce: respNonce,
        walletSecret: dapp.asTypedList,
        dappPublic: walletX.publicKey.asTypedList,
      );
      expect(witnessCbor, outcome.signResult!.witnessSetCbor);
      expect(() => WitnessSet.deserializeBytes(witnessCbor), returnsNormally);

      // (c) `signature` is the FINAL param and verifies against the session
      //     vkey over the canonical subject.
      expect(resp.query.split('&').last.startsWith('signature='), isTrue);
      final subject = AttestationBuilder.canonicalSubject(resp);
      final ok = session.sessionSigningKey.verifyKey.verify(
        signature:
            ed.Signature(_b64uDecode(resp.queryParameters['signature']!)),
        message: Uint8List.fromList(utf8.encode(subject)),
      );
      expect(ok, isTrue);
    });

    test('a tampered request ciphertext -> rejected -7, never throws',
        () async {
      final wallet = await _wallet();
      final kit = await wallet.getPaymentAddressKit(addressIndex: 0);
      final address = kit.address.bech32Encoded;

      final dapp = x.PrivateKey.generate();
      final walletX = x.PrivateKey.generate();
      final commit = _commitOfTxHex(_minimalConwayTxHex);
      final reqNonce = Uint8List.fromList(List.generate(24, (i) => i + 7));
      final reqCipher = naclBoxEncrypt(
        plaintext:
            Uint8List.fromList(utf8.encode('{"tx":"$_minimalConwayTxHex"}')),
        nonce: reqNonce,
        walletSecret: dapp.asTypedList,
        dappPublic: walletX.publicKey.asTypedList,
      );
      reqCipher[0] ^= 0xff; // tamper -> MAC failure

      final url = Uri.parse(
        'cip30dl-yuti:/v1/signTx?v=1'
        '&dappKey=${_b64uNoPad(dapp.publicKey.asTypedList)}'
        '&redirect=https%3A%2F%2Faegis.example%2Fcb'
        '&nonce=${_b64uNoPad(reqNonce)}'
        '&commit=${_b64uNoPad(commit)}'
        '&ttl=1810000300'
        '&payload=${_b64uNoPad(reqCipher)}',
      );

      final service = Cip186DeepLinkService(
          wallet: wallet, walletId: 'yuti', walletScheme: 'cip30dl-yuti');
      final outcome = await service.handle(
        url: url,
        signTxSemantics: SignTxPayloadDecoder.naclBox(
          walletX25519Secret: walletX.asTypedList,
          witnessAddresses: {address},
        ),
        session: _testSession(),
      );
      expect(outcome.responseUri!.queryParameters['response'], 'rejected');
      expect(outcome.errorCode, Cip186ErrorCode.decryptFailed);
    });
  });

  group('Replay + TTL protection (spec §Replay protection)', () {
    Uri validSignTxUrl(int ttl) {
      final commitB64 = _b64uNoPad(_commitOfTxHex(_minimalConwayTxHex));
      const payloadJson =
          '{"session":"s","tx":"$_minimalConwayTxHex","partialSign":true,"vkeyHints":[]}';
      final payloadB64 = _b64uNoPad(Uint8List.fromList(payloadJson.codeUnits));
      return Uri.parse(
        'cip30dl-yuti:/v1/signTx?v=1'
        '&dappKey=$_dappKeyB64'
        '&redirect=https%3A%2F%2Faegis.example%2Fcb'
        '&nonce=$_nonceB64'
        '&commit=$commitB64'
        '&ttl=$ttl'
        '&payload=$payloadB64',
      );
    }

    test('ttl already passed -> rejected -6 TtlExpired', () async {
      final wallet = await _wallet();
      final address =
          (await wallet.getPaymentAddressKit(addressIndex: 0)).address.bech32Encoded;
      final service = Cip186DeepLinkService(
        wallet: wallet,
        walletId: 'yuti',
        walletScheme: 'cip30dl-yuti',
        clockEpochSeconds: () => 1810000301, // one second past ttl
      );
      final outcome = await service.handle(
        url: validSignTxUrl(1810000300),
        signTxSemantics:
            SignTxPayloadDecoder.plaintextJson(witnessAddresses: {address}),
        session: _testSession(),
      );
      expect(outcome.errorCode, Cip186ErrorCode.ttlExpired);
      expect(outcome.responseUri!.queryParameters['errorCode'], '-6');
    });

    test('a generous far-future ttl is honored, not rejected (retention is '
        'capped instead — see replay-guard backstop)', () async {
      final wallet = await _wallet();
      final address =
          (await wallet.getPaymentAddressKit(addressIndex: 0)).address.bech32Encoded;
      final service = Cip186DeepLinkService(
        wallet: wallet,
        walletId: 'yuti',
        walletScheme: 'cip30dl-yuti',
        clockEpochSeconds: () => 1810000000,
      );
      // A ttl far beyond the 24h retention window must still SIGN (request
      // validity is not clamped); only the replay guard's retention is bounded.
      final outcome = await service.handle(
        url: validSignTxUrl(2000000000),
        signTxSemantics:
            SignTxPayloadDecoder.plaintextJson(witnessAddresses: {address}),
        session: _testSession(),
      );
      expect(outcome.responseUri!.queryParameters['response'], 'approved');
    });

    test('the same (dappKey, nonce) twice -> second rejected -5 NonceReplay',
        () async {
      final wallet = await _wallet();
      final address =
          (await wallet.getPaymentAddressKit(addressIndex: 0)).address.bech32Encoded;
      final service = Cip186DeepLinkService(
        wallet: wallet,
        walletId: 'yuti',
        walletScheme: 'cip30dl-yuti',
        clockEpochSeconds: () => 1810000000, // before ttl
      );
      final url = validSignTxUrl(1810000300);
      final decoder =
          SignTxPayloadDecoder.plaintextJson(witnessAddresses: {address});

      final first = await service.handle(
          url: url, signTxSemantics: decoder, session: _testSession());
      final second = await service.handle(
          url: url, signTxSemantics: decoder, session: _testSession());

      expect(first.responseUri!.queryParameters['response'], 'approved');
      expect(second.errorCode, Cip186ErrorCode.nonceReplay);
      expect(second.responseUri!.queryParameters['errorCode'], '-5');
    });
  });

  group('Orchestrator negative paths (spec §error responses)', () {
    Future<DeepLinkOutcome> handleUrl(String url) async {
      final wallet = await _wallet();
      final service = Cip186DeepLinkService(
        wallet: wallet,
        walletId: 'yuti',
        walletScheme: 'cip30dl-yuti',
      );
      return service.handle(url: Uri.parse(url));
    }

    test('missing redirect -> -4 RedirectHostMismatch, null responseUri',
        () async {
      final outcome = await handleUrl(
        'cip30dl-yuti:/v1/signTx?v=1&dappKey=$_dappKeyB64&nonce=$_nonceB64'
        '&commit=${_b64uNoPad(_commitOfTxHex(_minimalConwayTxHex))}'
        '&ttl=1810000300&payload=${_b64uNoPad(Uint8List.fromList('x'.codeUnits))}',
      );
      expect(outcome.errorCode, Cip186ErrorCode.redirectHostMismatch);
      expect(outcome.responseUri, isNull);
    });

    test('non-signTx method (signData) -> rejected -9 not-yet-implemented',
        () async {
      // Custom-scheme (native) redirect: a pre-binding rejection still reaches
      // the dApp. An unbindable https/http redirect is dropped instead (below).
      final outcome = await handleUrl(
        'cip30dl-yuti:/v1/signData?v=1&dappKey=$_dappKeyB64'
        '&redirect=aegisdemo%3A%2F%2Fcb&nonce=$_nonceB64',
      );
      expect(outcome.errorCode, Cip186ErrorCode.unsupportedVersion);
      expect(outcome.responseUri!.queryParameters['response'], 'rejected');
    });

    test('unknown query key -> -9 with a (custom-scheme) rejected redirect',
        () async {
      final outcome = await handleUrl(
        'cip30dl-yuti:/v1/signTx?v=1&dappKey=$_dappKeyB64'
        '&redirect=aegisdemo%3A%2F%2Fcb&nonce=$_nonceB64&bogus=1',
      );
      expect(outcome.errorCode, Cip186ErrorCode.unsupportedVersion);
      expect(outcome.responseUri!.queryParameters['response'], 'rejected');
    });

    test('pre-binding error path drops a plain-http redirect (no open redirect)',
        () async {
      final outcome = await handleUrl(
        'cip30dl-yuti:/v1/signTx?v=1&dappKey=$_dappKeyB64'
        '&redirect=http%3A%2F%2Fattacker.example%2Fcollect'
        '&nonce=$_nonceB64&bogus=1',
      );
      expect(outcome.errorCode, Cip186ErrorCode.unsupportedVersion);
      // No dApp identity is bound on a parse failure, so an http redirect is
      // never launched — the wallet cannot be turned into an open redirect.
      expect(outcome.responseUri, isNull);
    });

    test('pre-binding error path drops an unbindable https redirect', () async {
      final outcome = await handleUrl(
        'cip30dl-yuti:/v1/signData?v=1&dappKey=$_dappKeyB64'
        '&redirect=https%3A%2F%2Fattacker.example%2Fcollect&nonce=$_nonceB64',
      );
      expect(outcome.errorCode, Cip186ErrorCode.unsupportedVersion);
      // https is only trusted when it matches a bound dApp host; with no session
      // there is nothing to bind it to, so it is not launched.
      expect(outcome.responseUri, isNull);
    });
  });

  group('Cip186ReplayGuard memory bound (replay-guard DoS backstop)', () {
    test('caps retained entries, evicting the soonest-to-expire under flood',
        () {
      final guard = Cip186ReplayGuard(maxEntries: 3);
      Uint8List nonce(int i) => Uint8List.fromList(List.filled(24, i));
      final dappKey = Uint8List.fromList(List.filled(32, 9));
      const now = 1000;
      // Flood 5 distinct, far-future tuples into a guard capped at 3.
      for (var i = 1; i <= 5; i++) {
        expect(
          guard.checkAndRecord(dappKey, nonce(i), now + 100000 + i, now),
          isTrue,
        );
      }
      // The most-recent tuple (highest expiry) is still remembered -> replay.
      expect(
        guard.checkAndRecord(dappKey, nonce(5), now + 100005, now),
        isFalse,
      );
      // The earliest-expiring tuple was evicted to honor the cap, so it is
      // (safely) treated as fresh rather than retained forever.
      expect(
        guard.checkAndRecord(dappKey, nonce(1), now + 100001, now),
        isTrue,
      );
    });
  });
}
