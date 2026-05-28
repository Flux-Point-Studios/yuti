@Tags(['cip186-signing'])

import 'dart:typed_data';

import 'package:cardano_dart_types/cardano_dart_types.dart';
import 'package:cardano_flutter_sdk/cardano_flutter_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuti/cip186/errors.dart';
import 'package:yuti/cip186/signing_engine.dart';

// Deterministic 24-word BIP-39 mnemonic. All-`abandon` + valid checksum word.
// Spec-irrelevant; this is a canonical test vector used by Cardano tooling.
const String _testMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon abandon '
    'abandon abandon abandon abandon abandon abandon abandon art';

/// Minimal Conway transaction: empty inputs/outputs/fee Conway-tx for the
/// signing path. The wallet does NOT validate ledger rules; it only
/// recomputes BLAKE2b-256(tx_body) and signs the body hash.
/// This is the smallest CBOR shape that satisfies CardanoTransaction.deserializeFromHex.
const String _minimalConwayTxHex =
    '84a40080018002000300a0f5f6';

Future<CardanoWallet> _buildTestWallet() async {
  final wallet = await WalletFactory.fromMnemonic(
    NetworkId.testnet,
    _testMnemonic.split(' '),
  );
  return wallet;
}

Future<String> _testPaymentAddress(CardanoWallet w) async {
  final kit = await w.getPaymentAddressKit(addressIndex: 0);
  return kit.address.bech32Encoded;
}

Uint8List _bodyBlake2b256OfTxHex(String hex) {
  final tx = CardanoTransaction.deserializeFromHex(transactionHex: hex);
  return tx.body.computeBlake2bHash256();
}

void main() {
  group('Cip186SigningEngine positive — wallet.signTransaction integration', () {
    test('signTxBody returns a CBOR-encodable WitnessSet for the test wallet',
        () async {
      final wallet = await _buildTestWallet();
      final address = await _testPaymentAddress(wallet);
      final engine = Cip186SigningEngine(wallet: wallet);

      final result = await engine.signTxBody(
        transactionHex: _minimalConwayTxHex,
        expectedCommit: _bodyBlake2b256OfTxHex(_minimalConwayTxHex),
        witnessAddresses: {address},
      );

      expect(result.witnessSetCbor, isNotEmpty);
      expect(result.witnessSet, isA<WitnessSet>());
    });

    test('returned WitnessSet round-trips through CBOR deserialize', () async {
      final wallet = await _buildTestWallet();
      final address = await _testPaymentAddress(wallet);
      final engine = Cip186SigningEngine(wallet: wallet);

      final result = await engine.signTxBody(
        transactionHex: _minimalConwayTxHex,
        expectedCommit: _bodyBlake2b256OfTxHex(_minimalConwayTxHex),
        witnessAddresses: {address},
      );

      final roundTripped =
          WitnessSet.deserializeBytes(result.witnessSetCbor);
      expect(roundTripped.vkeyWitnesses.length,
          result.witnessSet.vkeyWitnesses.length);
    });

    test('txHash returned is BLAKE2b-256 of tx_body (32 bytes)', () async {
      final wallet = await _buildTestWallet();
      final address = await _testPaymentAddress(wallet);
      final engine = Cip186SigningEngine(wallet: wallet);

      final result = await engine.signTxBody(
        transactionHex: _minimalConwayTxHex,
        expectedCommit: _bodyBlake2b256OfTxHex(_minimalConwayTxHex),
        witnessAddresses: {address},
      );

      expect(result.txHash.length, 32);
      expect(result.txHash,
          orderedEquals(_bodyBlake2b256OfTxHex(_minimalConwayTxHex)));
    });

    test('each vkey witness carries 32-byte vkey + 64-byte Ed25519 signature',
        () async {
      final wallet = await _buildTestWallet();
      final address = await _testPaymentAddress(wallet);
      final engine = Cip186SigningEngine(wallet: wallet);

      final result = await engine.signTxBody(
        transactionHex: _minimalConwayTxHex,
        expectedCommit: _bodyBlake2b256OfTxHex(_minimalConwayTxHex),
        witnessAddresses: {address},
      );

      for (final w in result.witnessSet.vkeyWitnesses) {
        expect(w.vkey.length, 32,
            reason: 'CIP-30 vkey witness must be 32-byte Ed25519 pubkey');
        expect(w.signature.length, 64,
            reason: 'CIP-30 vkey witness must carry 64-byte Ed25519 sig');
      }
    });

    test('signing the same tx twice produces byte-identical witness CBOR '
        '(deterministic Ed25519, RFC 8032)', () async {
      final wallet = await _buildTestWallet();
      final address = await _testPaymentAddress(wallet);
      final engine = Cip186SigningEngine(wallet: wallet);
      final commit = _bodyBlake2b256OfTxHex(_minimalConwayTxHex);

      final r1 = await engine.signTxBody(
        transactionHex: _minimalConwayTxHex,
        expectedCommit: commit,
        witnessAddresses: {address},
      );
      final r2 = await engine.signTxBody(
        transactionHex: _minimalConwayTxHex,
        expectedCommit: commit,
        witnessAddresses: {address},
      );

      expect(r1.witnessSetCbor, orderedEquals(r2.witnessSetCbor));
    });
  });

  group('Cip186SigningEngine negative — commit binding (spec §Commit binding)',
      () {
    test('rejects when expectedCommit differs from BLAKE2b-256(tx_body)',
        () async {
      final wallet = await _buildTestWallet();
      final address = await _testPaymentAddress(wallet);
      final engine = Cip186SigningEngine(wallet: wallet);

      final wrongCommit = Uint8List(32);
      for (var i = 0; i < 32; i++) {
        wrongCommit[i] = 0xff;
      }

      expect(
        () => engine.signTxBody(
          transactionHex: _minimalConwayTxHex,
          expectedCommit: wrongCommit,
          witnessAddresses: {address},
        ),
        throwsA(isA<Cip186Exception>()
            .having((e) => e.code, 'code', Cip186ErrorCode.commitMismatch)),
      );
    });

    test('rejects malformed transaction hex with InternalError', () async {
      final wallet = await _buildTestWallet();
      final address = await _testPaymentAddress(wallet);
      final engine = Cip186SigningEngine(wallet: wallet);

      expect(
        () => engine.signTxBody(
          transactionHex: 'not-cbor-hex',
          expectedCommit: Uint8List(32),
          witnessAddresses: {address},
        ),
        throwsA(isA<Cip186Exception>()
            .having((e) => e.code, 'code', Cip186ErrorCode.internalError)),
      );
    });

    test('rejects empty witness-address set with UnsupportedChain '
        '(no signing path bound)', () async {
      final wallet = await _buildTestWallet();
      final engine = Cip186SigningEngine(wallet: wallet);

      expect(
        () => engine.signTxBody(
          transactionHex: _minimalConwayTxHex,
          expectedCommit: _bodyBlake2b256OfTxHex(_minimalConwayTxHex),
          witnessAddresses: const <String>{},
        ),
        throwsA(isA<Cip186Exception>()),
      );
    });

    test('rejects commit length != 32 bytes', () async {
      final wallet = await _buildTestWallet();
      final address = await _testPaymentAddress(wallet);
      final engine = Cip186SigningEngine(wallet: wallet);

      expect(
        () => engine.signTxBody(
          transactionHex: _minimalConwayTxHex,
          expectedCommit: Uint8List(16),
          witnessAddresses: {address},
        ),
        throwsA(isA<Cip186Exception>()),
      );
    });
  });
}
