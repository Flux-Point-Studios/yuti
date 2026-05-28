import 'dart:typed_data';

import 'package:cardano_dart_types/cardano_dart_types.dart';

import 'errors.dart';

/// Output of a single CIP-186 signTx call.
class Cip186SignResult {
  Cip186SignResult({
    required this.witnessSet,
    required this.witnessSetCbor,
    required this.txHash,
  });

  final WitnessSet witnessSet;
  final Uint8List witnessSetCbor;
  final Uint8List txHash;
}

/// Wraps `cardano_flutter_sdk` `wallet.signTransaction()` behind the CIP-186
/// commit-binding rule (spec §Commit binding) and returns a CBOR-serialised
/// witness set ready for the dApp callback payload.
class Cip186SigningEngine {
  Cip186SigningEngine({required CardanoWallet wallet}) : _wallet = wallet;

  final CardanoWallet _wallet;

  Future<Cip186SignResult> signTxBody({
    required String transactionHex,
    required Uint8List expectedCommit,
    required Set<String> witnessAddresses,
  }) async {
    if (expectedCommit.length != 32) {
      throw Cip186Exception(
        Cip186ErrorCode.commitMismatch,
        'commit must be 32 bytes (got ${expectedCommit.length})',
      );
    }
    if (witnessAddresses.isEmpty) {
      throw Cip186Exception(
        Cip186ErrorCode.unsupportedChain,
        'witnessAddresses set is empty; no signing key bound',
      );
    }

    final CardanoTransaction tx;
    try {
      tx = CardanoTransaction.deserializeFromHex(transactionHex: transactionHex);
    } catch (e) {
      throw Cip186Exception(
        Cip186ErrorCode.internalError,
        'transaction CBOR deserialization failed: $e',
      );
    }

    final actualCommit = tx.body.computeBlake2bHash256();
    if (!_constTimeEquals(actualCommit, expectedCommit)) {
      throw Cip186Exception(
        Cip186ErrorCode.commitMismatch,
        'BLAKE2b-256(tx_body) does not match URL commit',
      );
    }

    final WitnessSet witnessSet;
    try {
      witnessSet = await _wallet.signTransaction(
        tx: tx,
        witnessBech32Addresses: witnessAddresses,
      );
    } catch (e) {
      throw Cip186Exception(
        Cip186ErrorCode.internalError,
        'wallet signTransaction failed: $e',
      );
    }

    final witnessBytes = witnessSet.serializeAsBytes();

    return Cip186SignResult(
      witnessSet: witnessSet,
      witnessSetCbor: witnessBytes,
      txHash: actualCommit,
    );
  }

  static bool _constTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
