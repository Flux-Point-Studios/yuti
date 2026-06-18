import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hex/hex.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:pinenacl/x25519.dart' as x;
import 'package:yuti/cip186/crypto.dart';
import 'package:yuti/cip186/errors.dart';

void main() {
  group('HKDF-SHA512 (RFC 5869) — vs independent Python reference', () {
    test('simple vector (ikm=0x0b*22, salt=00..0c, info=f0f1f2f3, L=42)', () {
      final okm = hkdfSha512(
        ikm: Uint8List.fromList(List.filled(22, 0x0b)),
        salt: Uint8List.fromList(List.generate(13, (i) => i)),
        info: Uint8List.fromList(const [0xf0, 0xf1, 0xf2, 0xf3]),
        length: 42,
      );
      expect(
        HEX.encode(okm),
        '5002cb8295072391f6910b0558a662cfa4f40653381d29a1530cecb2cc69de65bf34d65138dde1bbe2aa',
      );
    });

    test('session-vkey salt == SHA-256("cip30dl/v1/session_vkey")', () {
      expect(
        HEX.encode(sessionVkeySalt),
        'd202f238d1a6b40ba0f8ff81fe944dc1d60d0c7c05212e88eaa1c1258dadc5e7',
      );
    });

    test('session OKM matches the Python HKDF-SHA512 golden', () {
      final okm = hkdfSha512(
        ikm: Uint8List.fromList(List.generate(32, (i) => i)),
        salt: sessionVkeySalt,
        info: Uint8List.fromList(
            utf8.encode('cip30dl/v1/session_vkey/aegis.example/sess-1')),
        length: 32,
      );
      expect(
        HEX.encode(okm),
        '6dc814f4591444f83ddd4719e9444497e8832a6d0f9fc535afae3561a1e4e412',
      );
    });
  });

  group('deriveSessionSigningKey (spec §Session-binding key derivation)', () {
    Uint8List secret(int b) => Uint8List.fromList(List.filled(32, b));

    test('deterministic for the same inputs; publishes a 32-byte vkey', () {
      final k1 = deriveSessionSigningKey(
          walletRootSecret: secret(7),
          sessionEntropy: secret(9),
          dappHost: 'aegis.example',
          sessionId: 'sess-1');
      final k2 = deriveSessionSigningKey(
          walletRootSecret: secret(7),
          sessionEntropy: secret(9),
          dappHost: 'aegis.example',
          sessionId: 'sess-1');
      expect(k1.verifyKey.asTypedList.length, 32);
      expect(k1.verifyKey.asTypedList, k2.verifyKey.asTypedList);
    });

    test('fresh session entropy yields a different vkey', () {
      final a = deriveSessionSigningKey(
          walletRootSecret: secret(7),
          sessionEntropy: secret(9),
          dappHost: 'aegis.example',
          sessionId: 'sess-1');
      final b = deriveSessionSigningKey(
          walletRootSecret: secret(7),
          sessionEntropy: secret(10),
          dappHost: 'aegis.example',
          sessionId: 'sess-1');
      expect(a.verifyKey.asTypedList, isNot(b.verifyKey.asTypedList));
    });

    test('different dApp host yields a different vkey', () {
      final a = deriveSessionSigningKey(
          walletRootSecret: secret(7),
          sessionEntropy: secret(9),
          dappHost: 'aegis.example',
          sessionId: 'sess-1');
      final b = deriveSessionSigningKey(
          walletRootSecret: secret(7),
          sessionEntropy: secret(9),
          dappHost: 'evil.example',
          sessionId: 'sess-1');
      expect(a.verifyKey.asTypedList, isNot(b.verifyKey.asTypedList));
    });
  });

  group('signCanonicalSubject (Ed25519 over canonical form)', () {
    final sk = deriveSessionSigningKey(
        walletRootSecret: Uint8List.fromList(List.filled(32, 1)),
        sessionEntropy: Uint8List.fromList(List.filled(32, 2)),
        dappHost: 'aegis.example',
        sessionId: 's');
    const subject =
        'cip30dl-v1\nhttps://aegis.example/cb?nonce=abc&response=approved';

    test('produces a 64-byte signature that verifies against the vkey', () {
      final sig =
          signCanonicalSubject(signingKey: sk, canonicalSubject: subject);
      expect(sig.length, 64);
      final ok = sk.verifyKey.verify(
        signature: ed.Signature(sig),
        message: Uint8List.fromList(utf8.encode(subject)),
      );
      expect(ok, isTrue);
    });

    test('a tampered subject fails verification', () {
      final sig =
          signCanonicalSubject(signingKey: sk, canonicalSubject: subject);
      expect(
        () => sk.verifyKey.verify(
          signature: ed.Signature(sig),
          message: Uint8List.fromList(utf8.encode('${subject}X')),
        ),
        throwsA(anything),
      );
    });
  });

  group('NaCl-box (X25519 + XSalsa20-Poly1305)', () {
    test('round-trips wallet->dapp and back', () {
      final wallet = x.PrivateKey.generate();
      final dapp = x.PrivateKey.generate();
      final nonce = Uint8List.fromList(List.generate(24, (i) => i + 1));
      final pt = Uint8List.fromList(utf8.encode('{"tx":"84a40080018002000300a0f5f6"}'));

      final ct = naclBoxEncrypt(
        plaintext: pt,
        nonce: nonce,
        walletSecret: wallet.asTypedList,
        dappPublic: dapp.publicKey.asTypedList,
      );
      // The dApp opens it with its own secret + the wallet's public key.
      final back = naclBoxDecrypt(
        ciphertext: ct,
        nonce: nonce,
        walletSecret: dapp.asTypedList,
        dappPublic: wallet.publicKey.asTypedList,
      );
      expect(back, pt);
    });

    test('a flipped ciphertext byte -> -7 DecryptFailed (Poly1305 MAC)', () {
      final wallet = x.PrivateKey.generate();
      final dapp = x.PrivateKey.generate();
      final nonce = Uint8List.fromList(List.generate(24, (i) => i + 1));
      final ct = naclBoxEncrypt(
        plaintext: Uint8List.fromList(utf8.encode('hello')),
        nonce: nonce,
        walletSecret: wallet.asTypedList,
        dappPublic: dapp.publicKey.asTypedList,
      );
      ct[0] ^= 0xff;
      expect(
        () => naclBoxDecrypt(
          ciphertext: ct,
          nonce: nonce,
          walletSecret: dapp.asTypedList,
          dappPublic: wallet.publicKey.asTypedList,
        ),
        throwsA(isA<Cip186Exception>().having(
            (e) => e.code, 'code', Cip186ErrorCode.decryptFailed)),
      );
    });

    test('low-order dappKey (all-zero point) -> -7 (RFC 7748 §6.1)', () {
      final wallet = x.PrivateKey.generate();
      final lowOrder = Uint8List(32); // all-zero u-coordinate
      expect(
        () => naclBoxEncrypt(
          plaintext: Uint8List.fromList(const [1, 2, 3, 4]),
          nonce: Uint8List(24),
          walletSecret: wallet.asTypedList,
          dappPublic: lowOrder,
        ),
        throwsA(isA<Cip186Exception>().having(
            (e) => e.code, 'code', Cip186ErrorCode.decryptFailed)),
      );
    });
  });
}
