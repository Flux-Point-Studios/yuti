@Tags(['cip186-signing'])

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pinenacl/ed25519.dart' as ed;

// Guards the contract the persistent session store relies on: a session signing
// key is persisted as its 32-byte SEED (`.seed`, NOT the 64-byte `.asTypedList`)
// and reconstructs to an identical, identically-signing key.
void main() {
  test('Ed25519 SigningKey persists + restores via its 32-byte seed', () {
    final sk = ed.SigningKey.generate();
    final seed = Uint8List.fromList(sk.seed);
    expect(seed.length, 32);

    final restored = ed.SigningKey(seed: seed);
    expect(restored.verifyKey.asTypedList, sk.verifyKey.asTypedList);

    final msg = Uint8List.fromList('cip30dl-v1 subject'.codeUnits);
    expect(restored.sign(msg).signature.asTypedList,
        sk.sign(msg).signature.asTypedList);
  });
}
