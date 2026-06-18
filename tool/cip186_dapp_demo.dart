// CIP-186 dApp-side demo harness (DEMO ONLY).
//
// Plays the dApp half of a `connect` + `signTx` exchange against a running
// Yuti build:
//   connect-url                       deep-link to start a connect handshake
//   decode <uri> | decodefile <path>  decrypt the wallet's connect response
//   signtx-url <walletKeyB64>         deep-link to sign a sample tx (walletKey
//                                     from the connect response)
//   signtx-decodefile <path> <walletKeyB64> <signingPubB64>
//                                     decrypt the witness set + VERIFY the
//                                     Ed25519 response signature
//
// The dApp X25519 keypair is derived from a FIXED seed so the phases share the
// same keys without persisting state. NEVER use a fixed key in production.
//
// Run from the package root:  dart run tool/cip186_dapp_demo.dart connect-url
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cardano_dart_types/cardano_dart_types.dart';
import 'package:pinenacl/ed25519.dart' as ed;
import 'package:pinenacl/x25519.dart' as x;
import 'package:yuti/cip186/attestation.dart';

final Uint8List _dappSeed =
    Uint8List.fromList(List<int>.generate(32, (i) => i + 1));
x.PrivateKey _dappKey() => x.PrivateKey(_dappSeed);

/// A minimal valid Conway transaction (empty inputs/outputs, 0 fee/ttl). The
/// commit binds to BLAKE2b-256 of its body — exactly what the wallet recomputes.
const String _minimalTxHex = '84a40080018002000300a0f5f6';

String _b64u(List<int> b) => base64Url.encode(b).replaceAll('=', '');
Uint8List _b64uDecode(String s) =>
    Uint8List.fromList(base64Url.decode(s + ('=' * ((4 - s.length % 4) % 4))));

void _printConnectUrl() {
  final dapp = _dappKey();
  final dappInfo = _b64u(utf8.encode('{"name":"Aegis Demo",'
      '"url":"https://demo.aegis.fluxpointstudios.com",'
      '"iconUrl":"https://demo.aegis.fluxpointstudios.com/i.png"}'));
  final nonce = _b64u(Uint8List.fromList(List<int>.generate(24, (i) => i + 7)));
  stdout.writeln('cip30dl-yuti:/v1/connect?v=1'
      '&dapp=$dappInfo'
      '&dappKey=${_b64u(dapp.publicKey.asTypedList)}'
      '&redirect=https%3A%2F%2Fexample.com%2Fcb'
      '&chain=cardano%3Amainnet'
      '&nonce=$nonce');
}

void _decodeConnect(String responseUri) {
  final q = Uri.parse(responseUri).queryParameters;
  if (q['response'] != 'approved') {
    stdout.writeln('NOT APPROVED: response=${q['response']} '
        'errorCode=${q['errorCode']} errorMessage=${q['errorMessage']}');
    return;
  }
  final walletKey = _b64uDecode(q['walletKey']!);
  final box =
      x.Box(myPrivateKey: _dappKey(), theirPublicKey: x.PublicKey(walletKey));
  final pt = box.decrypt(x.EncryptedMessage(
      nonce: _b64uDecode(q['nonce']!), cipherText: _b64uDecode(q['payload']!)));
  final sessionJson = jsonDecode(utf8.decode(pt)) as Map<String, dynamic>;
  stdout.writeln('=== DECRYPTED SESSION JSON ===');
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(sessionJson));
  stdout.writeln('WALLETKEY=${q['walletKey']}');
  stdout.writeln('SIGNINGPUB=${sessionJson['signingPublicKey']}');
}

void _printSignTxUrl(String walletKeyB64) {
  final dapp = _dappKey();
  final walletPub = _b64uDecode(walletKeyB64);
  final commit =
      CardanoTransaction.deserializeFromHex(_minimalTxHex).body.computeBlake2bHash256();
  // A request nonce distinct from the connect nonce (also the replay key).
  final reqNonce = Uint8List.fromList(List<int>.generate(24, (i) => 100 + i));
  final payloadJson =
      '{"session":"demo","tx":"$_minimalTxHex","partialSign":true,"vkeyHints":[]}';
  final box =
      x.Box(myPrivateKey: dapp, theirPublicKey: x.PublicKey(walletPub));
  final enc = box.encrypt(Uint8List.fromList(utf8.encode(payloadJson)),
      nonce: reqNonce);
  final cipher = Uint8List.fromList(enc.cipherText.asTypedList);
  stdout.writeln('cip30dl-yuti:/v1/signTx?v=1'
      '&dappKey=${_b64u(dapp.publicKey.asTypedList)}'
      '&redirect=https%3A%2F%2Fexample.com%2Fcb'
      '&nonce=${_b64u(reqNonce)}'
      '&commit=${_b64u(commit)}'
      '&ttl=1900000000'
      '&payload=${_b64u(cipher)}');
}

void _decodeSignTx(String responseUri, String walletKeyB64, String signingPubB64) {
  final uri = Uri.parse(responseUri);
  final q = uri.queryParameters;
  if (q['response'] != 'approved') {
    stdout.writeln('NOT APPROVED: response=${q['response']} '
        'errorCode=${q['errorCode']} errorMessage=${q['errorMessage']}');
    return;
  }
  final walletPub = _b64uDecode(walletKeyB64);
  final box =
      x.Box(myPrivateKey: _dappKey(), theirPublicKey: x.PublicKey(walletPub));
  final witnessCbor = Uint8List.fromList(box.decrypt(x.EncryptedMessage(
      nonce: _b64uDecode(q['nonce']!), cipherText: _b64uDecode(q['payload']!))));

  // Verify the Ed25519 response signature over Yuti's own canonical subject.
  final subject = AttestationBuilder.canonicalSubject(uri);
  final vk = ed.VerifyKey(_b64uDecode(signingPubB64));
  final ok = vk.verify(
    signature: ed.Signature(_b64uDecode(q['signature']!)),
    message: Uint8List.fromList(utf8.encode(subject)),
  );

  stdout.writeln('=== signTx RESPONSE ===');
  stdout.writeln('witnessSet CBOR (hex): '
      '${witnessCbor.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
  stdout.writeln('response signature verifies vs signingPublicKey: $ok');
}

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('usage: connect-url | decode <uri> | decodefile <path> | '
        'signtx-url <walletKeyB64> | '
        'signtx-decodefile <path> <walletKeyB64> <signingPubB64>');
    exit(2);
  }
  switch (args[0]) {
    case 'connect-url':
    case 'url':
      _printConnectUrl();
    case 'decode':
      _decodeConnect(args[1]);
    case 'decodefile':
      _decodeConnect(File(args[1]).readAsStringSync().trim());
    case 'signtx-url':
      _printSignTxUrl(args[1]);
    case 'signtx-decodefile':
      _decodeSignTx(
          File(args[1]).readAsStringSync().trim(), args[2], args[3]);
    default:
      stderr.writeln('unknown command ${args[0]}');
      exit(2);
  }
}
