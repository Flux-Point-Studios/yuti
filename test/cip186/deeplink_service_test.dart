@Tags(['cip186-signing'])

import 'dart:convert';
import 'dart:typed_data';

import 'package:cardano_dart_types/cardano_dart_types.dart';
import 'package:cardano_flutter_sdk/cardano_flutter_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuti/cip186/deeplink_service.dart';
import 'package:yuti/cip186/errors.dart';

const String _testMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon art';

const String _minimalConwayTxHex = '84a40080018002000300a0f5f6';

const String _dappKeyB64 = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE';
const String _nonceB64 = 'AgICAgICAgICAgICAgICAgICAgICAgICAgIC';

Future<CardanoWallet> _wallet() async => WalletFactory.fromMnemonic(
      NetworkId.testnet,
      _testMnemonic.split(' '),
    );

String _b64uNoPad(Uint8List bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List _commitOfTxHex(String hex) {
  final tx = CardanoTransaction.deserializeFromHex(transactionHex: hex);
  return tx.body.computeBlake2bHash256();
}

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
      );

      expect(outcome.responseUri!.queryParameters['response'], 'rejected');
      expect(outcome.responseUri!.queryParameters['errorCode'], '-2');
      expect(outcome.errorCode, Cip186ErrorCode.commitMismatch);
    });
  });
}
