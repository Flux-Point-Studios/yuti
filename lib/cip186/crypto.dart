import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as cr;
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:pinenacl/tweetnacl.dart' as tweet;
import 'package:pinenacl/x25519.dart' as x;

import 'errors.dart';

/// CIP-186 envelope cryptography (spec §Methods AEAD envelope + §Response
/// signing). Zero placeholders: NaCl-box (X25519 + XSalsa20-Poly1305) for the
/// payload, HKDF-SHA512 for the session-binding key, Ed25519 for the response
/// signature over the canonical subject. Pure, deterministic, unit-testable.

/// RFC 5869 HKDF with HMAC-SHA512.
Uint8List hkdfSha512({
  required Uint8List ikm,
  required Uint8List salt,
  required Uint8List info,
  required int length,
}) {
  // Extract.
  final prk = cr.Hmac(cr.sha512, salt).convert(ikm).bytes;
  // Expand.
  final out = <int>[];
  var t = <int>[];
  var counter = 1;
  while (out.length < length) {
    if (counter > 255) {
      throw ArgumentError('HKDF length too large for SHA-512');
    }
    t = cr.Hmac(cr.sha512, prk).convert(<int>[...t, ...info, counter]).bytes;
    out.addAll(t);
    counter++;
  }
  return Uint8List.fromList(out.sublist(0, length));
}

/// SHA-256(data).
Uint8List sha256Bytes(List<int> data) =>
    Uint8List.fromList(cr.sha256.convert(data).bytes);

/// Fresh CSPRNG bytes (platform secure random via TweetNaCl). Used for the
/// per-response 24-byte box nonce — MUST be fresh per response, never zeros.
Uint8List randomBytes(int length) => tweet.TweetNaCl.randombytes(length);

/// Fixed salt = SHA-256("cip30dl/v1/session_vkey") (spec §Session-binding key
/// derivation).
final Uint8List sessionVkeySalt =
    sha256Bytes(utf8.encode('cip30dl/v1/session_vkey'));

/// Derives the per-session, per-dApp Ed25519 signing key
/// (spec §Session-binding key derivation):
///   IKM  = walletRootSecret || sessionEntropy
///   salt = SHA-256("cip30dl/v1/session_vkey")
///   info = "cip30dl/v1/session_vkey/" || dappHost || "/" || sessionId
///   OKM  = HKDF-SHA512(IKM, salt, info, 32)  -> Ed25519 seed
ed.SigningKey deriveSessionSigningKey({
  required Uint8List walletRootSecret,
  required Uint8List sessionEntropy,
  required String dappHost,
  required String sessionId,
}) {
  final ikm = Uint8List.fromList([...walletRootSecret, ...sessionEntropy]);
  final info = Uint8List.fromList(
      utf8.encode('cip30dl/v1/session_vkey/$dappHost/$sessionId'));
  final okm = hkdfSha512(ikm: ikm, salt: sessionVkeySalt, info: info, length: 32);
  return ed.SigningKey(seed: okm);
}

/// The 64-byte Ed25519 signature over the canonical-subject string
/// (spec §Signature construction). The wallet appends this as the FINAL URL
/// parameter; the dApp verifies it against the published `session.signingPublicKey`.
Uint8List signCanonicalSubject({
  required ed.SigningKey signingKey,
  required String canonicalSubject,
}) {
  final sm = signingKey.sign(Uint8List.fromList(utf8.encode(canonicalSubject)));
  return Uint8List.fromList(sm.signature.asTypedList);
}

bool _isAllZero(List<int> bytes) {
  var acc = 0;
  for (final b in bytes) {
    acc |= b;
  }
  return acc == 0;
}

x.Box _box(Uint8List walletSecret, Uint8List dappPublic) {
  // RFC 7748 §6.1: reject low-order public keys whose raw X25519 DH output is
  // the all-zero string (the eight low-order points). crypto_scalarmult gives
  // the RAW DH — Box.sharedKey is post-HSalsa20 (crypto_box_beforenm) and so
  // never all-zero, which is why it must be checked here, before constructing
  // the box.
  final rawDh = Uint8List(32);
  tweet.TweetNaCl.crypto_scalarmult(
      rawDh, Uint8List.fromList(walletSecret), Uint8List.fromList(dappPublic));
  if (_isAllZero(rawDh)) {
    throw Cip186Exception(
      Cip186ErrorCode.decryptFailed,
      'low-order X25519 public key rejected (all-zero DH shared secret)',
    );
  }
  return x.Box(
    myPrivateKey: x.PrivateKey(walletSecret),
    theirPublicKey: x.PublicKey(dappPublic),
  );
}

/// NaCl-box decrypt of [ciphertext] under [nonce], returning the plaintext.
/// Throws Cip186Exception(-7 DecryptFailed) on MAC failure or low-order key.
Uint8List naclBoxDecrypt({
  required Uint8List ciphertext,
  required Uint8List nonce,
  required Uint8List walletSecret,
  required Uint8List dappPublic,
}) {
  final box = _box(walletSecret, dappPublic);
  try {
    final enc = x.EncryptedMessage(nonce: nonce, cipherText: ciphertext);
    return box.decrypt(enc);
  } catch (e) {
    throw Cip186Exception(
      Cip186ErrorCode.decryptFailed,
      'NaCl-box authentication failed',
    );
  }
}

/// NaCl-box encrypt of [plaintext] under [nonce]. Returns the ciphertext only;
/// the 24-byte [nonce] travels separately as the wire `nonce` field.
Uint8List naclBoxEncrypt({
  required Uint8List plaintext,
  required Uint8List nonce,
  required Uint8List walletSecret,
  required Uint8List dappPublic,
}) {
  final box = _box(walletSecret, dappPublic);
  final enc = box.encrypt(plaintext, nonce: nonce);
  return Uint8List.fromList(enc.cipherText.asTypedList);
}
