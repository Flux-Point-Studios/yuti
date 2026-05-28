import 'package:flutter_test/flutter_test.dart';
import 'package:yuti/cip186/errors.dart';
import 'package:yuti/cip186/uri_parser.dart';

const _dappKeyB64 = 'AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE';
const _nonceB64 = 'AgICAgICAgICAgICAgICAgICAgICAgICAgIC';
const _commitB64 = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
const _payloadB64 = 'cGF5bG9hZC1zaWdudHgtdmFsaWQtZml4dHVyZS1iYXNlNjR1cmw';
const _dappInfoB64 =
    'eyJuYW1lIjoiQWVnaXMiLCJ1cmwiOiJodHRwczovL2FlZ2lzLmV4YW1wbGUiLCJpY29uVXJsIjoiaHR0cHM6Ly9hZWdpcy5leGFtcGxlL2ljb24ucG5nIn0';

String _httpsSignTx(String walletDomain, {Map<String, String>? overrides}) {
  final params = <String, String>{
    'v': '1',
    'dappKey': _dappKeyB64,
    'redirect': 'https%3A%2F%2Faegis.example%2Fcb',
    'nonce': _nonceB64,
    'commit': _commitB64,
    'ttl': '1810000300',
    'payload': _payloadB64,
  };
  if (overrides != null) params.addAll(overrides);
  final query = params.entries.map((e) => '${e.key}=${e.value}').join('&');
  return 'https://$walletDomain/cip30dl/v1/signTx?$query';
}

String _schemeSignTx(String walletId) =>
    'cip30dl-$walletId:/v1/signTx?v=1&dappKey=$_dappKeyB64'
    '&redirect=https%3A%2F%2Faegis.example%2Fcb&nonce=$_nonceB64'
    '&commit=$_commitB64&ttl=1810000300&payload=$_payloadB64';

void main() {
  group('Cip186UriParser positive — URI format (spec §URI format)', () {
    test('parses HTTPS connect URL from Appendix C.1', () {
      final req = Cip186UriParser.parse(Uri.parse(
        'https://lace.io/cip30dl/v1/connect'
        '?v=1&dapp=$_dappInfoB64'
        '&dappKey=$_dappKeyB64'
        '&redirect=https%3A%2F%2Faegis.example%2Fcb'
        '&chain=cardano%3Apreprod'
        '&nonce=$_nonceB64',
      ));
      expect(req.form, Cip186UriForm.https);
      expect(req.walletDomain, 'lace.io');
      expect(req.walletId, isNull);
      expect(req.method, Cip186Method.connect);
      expect(req.params['v'], '1');
      expect(req.params['chain'], 'cardano:preprod');
      expect(req.params['redirect'], 'https://aegis.example/cb');
    });

    test('parses custom-scheme signTx URL from Appendix C.2', () {
      final req = Cip186UriParser.parse(Uri.parse(_schemeSignTx('lace')));
      expect(req.form, Cip186UriForm.customScheme);
      expect(req.walletId, 'lace');
      expect(req.walletDomain, isNull);
      expect(req.method, Cip186Method.signTx);
      expect(req.params['commit'], _commitB64);
      expect(req.params['ttl'], '1810000300');
    });

    test('parses HTTPS signTx with yuti host', () {
      final req = Cip186UriParser.parse(
          Uri.parse(_httpsSignTx('yuti.fluxpointstudios.com')));
      expect(req.walletDomain, 'yuti.fluxpointstudios.com');
      expect(req.method, Cip186Method.signTx);
    });

    test('accepts all v1 methods from ABNF', () {
      for (final method in const [
        'connect',
        'disconnect',
        'signTx',
        'signData',
        'getUsedAddresses',
        'getUnusedAddresses',
        'getRewardAddresses',
        'getNetworkId',
        'submitTx',
      ]) {
        final url = 'cip30dl-yuti:/v1/$method?v=1&dappKey=$_dappKeyB64'
            '&redirect=https%3A%2F%2Faegis.example%2Fcb&nonce=$_nonceB64';
        final req = Cip186UriParser.parse(Uri.parse(url));
        expect(req.method.wireName, method);
      }
    });

    test('preserves percent-decoded redirect host for callback binding', () {
      final req = Cip186UriParser.parse(
          Uri.parse(_httpsSignTx('yuti.fluxpointstudios.com')));
      expect(req.redirectUri, isNotNull);
      expect(req.redirectUri!.host, 'aegis.example');
      expect(req.redirectUri!.scheme, 'https');
    });

    test('decodes base64url commit to 32 bytes (BLAKE2b-256 length)', () {
      final req = Cip186UriParser.parse(
          Uri.parse(_httpsSignTx('yuti.fluxpointstudios.com')));
      expect(req.commitBytes, isNotNull);
      expect(req.commitBytes!.length, 32);
    });

    test('decodes base64url nonce to 24 bytes (XSalsa20 nonce length)', () {
      final req = Cip186UriParser.parse(
          Uri.parse(_httpsSignTx('yuti.fluxpointstudios.com')));
      expect(req.nonceBytes, isNotNull);
      expect(req.nonceBytes!.length, 24);
    });

    test('decodes base64url dappKey to 32 bytes (X25519 pubkey length)', () {
      final req = Cip186UriParser.parse(
          Uri.parse(_httpsSignTx('yuti.fluxpointstudios.com')));
      expect(req.dappKeyBytes, isNotNull);
      expect(req.dappKeyBytes!.length, 32);
    });

    test('exposes ttl as integer seconds', () {
      final req = Cip186UriParser.parse(
          Uri.parse(_httpsSignTx('yuti.fluxpointstudios.com')));
      expect(req.ttl, 1810000300);
    });

    test('parses custom scheme with yuti id', () {
      final req = Cip186UriParser.parse(Uri.parse(_schemeSignTx('yuti')));
      expect(req.walletId, 'yuti');
    });
  });

  group('Cip186UriParser negative — unknown-key strict reject (spec §Unknown-key policy)', () {
    test('rejects HTTPS signTx with extra unknown query key', () {
      expect(
        () => Cip186UriParser.parse(Uri.parse(_httpsSignTx(
            'lace.io',
            overrides: {'extraField': 'evil'}))),
        throwsA(isA<Cip186Exception>()
            .having((e) => e.code, 'code', Cip186ErrorCode.unsupportedVersion)
            .having((e) => e.offendingKey, 'offendingKey', 'extraField')),
      );
    });

    test('rejects URL with empty path / no method', () {
      expect(
        () => Cip186UriParser.parse(
            Uri.parse('https://lace.io/cip30dl/v1/?v=1&dappKey=$_dappKeyB64')),
        throwsA(isA<Cip186Exception>()),
      );
    });

    test('rejects bare cip30dl: shared scheme (no wallet id suffix)', () {
      expect(
        () => Cip186UriParser.parse(Uri.parse(
            'cip30dl:/v1/signTx?v=1&dappKey=$_dappKeyB64'
            '&redirect=https%3A%2F%2Faegis.example%2Fcb&nonce=$_nonceB64'
            '&commit=$_commitB64&ttl=1810000300&payload=$_payloadB64')),
        throwsA(isA<Cip186Exception>()
            .having((e) => e.code, 'code', Cip186ErrorCode.unsupportedVersion)),
      );
    });

    test('rejects unknown method name not in ABNF', () {
      expect(
        () => Cip186UriParser.parse(Uri.parse(
            'https://lace.io/cip30dl/v1/eatMyShorts?v=1&dappKey=$_dappKeyB64'
            '&redirect=https%3A%2F%2Faegis.example%2Fcb&nonce=$_nonceB64')),
        throwsA(isA<Cip186Exception>()
            .having((e) => e.code, 'code', Cip186ErrorCode.unsupportedVersion)),
      );
    });

    test('rejects malformed HTTPS path prefix (missing /cip30dl/v1/)', () {
      expect(
        () => Cip186UriParser.parse(Uri.parse(
            'https://lace.io/signTx?v=1&dappKey=$_dappKeyB64'
            '&redirect=https%3A%2F%2Faegis.example%2Fcb&nonce=$_nonceB64')),
        throwsA(isA<Cip186Exception>()),
      );
    });

    test('rejects URL exceeding payload byte budget (spec §URI length, -32)', () {
      final huge = 'a' * (12 * 1024 + 1);
      expect(
        () => Cip186UriParser.parse(Uri.parse(
            'cip30dl-yuti:/v1/signTx?v=1&dappKey=$_dappKeyB64'
            '&redirect=https%3A%2F%2Faegis.example%2Fcb&nonce=$_nonceB64'
            '&commit=$_commitB64&ttl=1810000300&payload=$huge')),
        throwsA(isA<Cip186Exception>()
            .having((e) => e.code, 'code', Cip186ErrorCode.payloadTooLarge)),
      );
    });

    test('rejects base64url with padding (=) — strict-decode rule', () {
      expect(
        () => Cip186UriParser.parse(Uri.parse(_httpsSignTx(
            'lace.io',
            overrides: {'nonce': 'AgICAgICAgICAgICAgICAgICAgIC='}))),
        throwsA(isA<Cip186Exception>()),
      );
    });

    test('rejects base64url with non-alphabet character', () {
      expect(
        () => Cip186UriParser.parse(Uri.parse(_httpsSignTx(
            'lace.io',
            overrides: {'nonce': 'Ag/CAgICAgICAgICAgICAgICAgICAgICAgIC'}))),
        throwsA(isA<Cip186Exception>()),
      );
    });

    test('rejects commit not 32 bytes after base64url decode', () {
      expect(
        () => Cip186UriParser.parse(Uri.parse(_httpsSignTx(
            'lace.io',
            overrides: {'commit': _nonceB64}))),
        throwsA(isA<Cip186Exception>()),
      );
    });

    test('rejects nonce not 24 bytes after base64url decode', () {
      expect(
        () => Cip186UriParser.parse(Uri.parse(_httpsSignTx(
            'lace.io',
            overrides: {'nonce': _commitB64}))),
        throwsA(isA<Cip186Exception>()),
      );
    });

    test('rejects ttl that is not a positive integer (spec §Replay protection)', () {
      expect(
        () => Cip186UriParser.parse(Uri.parse(_httpsSignTx(
            'lace.io',
            overrides: {'ttl': 'tomorrow'}))),
        throwsA(isA<Cip186Exception>()),
      );
    });

    test('rejects v=2 with UnsupportedVersion (current is v=1)', () {
      expect(
        () => Cip186UriParser.parse(Uri.parse(_httpsSignTx(
            'lace.io',
            overrides: {'v': '2'}))),
        throwsA(isA<Cip186Exception>()
            .having((e) => e.code, 'code', Cip186ErrorCode.unsupportedVersion)),
      );
    });

    test('rejects v parameter with leading zero (spec §Versioning)', () {
      expect(
        () => Cip186UriParser.parse(Uri.parse(_httpsSignTx(
            'lace.io',
            overrides: {'v': '01'}))),
        throwsA(isA<Cip186Exception>()),
      );
    });
  });

  group('Cip186UriParser — wallet-id binding (spec §Per-wallet custom schemes)', () {
    test('only accepts the wallet\'s own custom scheme', () {
      const yutiScheme = 'cip30dl-yuti';
      final req = Cip186UriParser.parse(
        Uri.parse(_schemeSignTx('yuti')),
        expectedWalletId: 'yuti',
        expectedScheme: yutiScheme,
      );
      expect(req.walletId, 'yuti');
    });

    test('rejects a custom scheme bound to a different wallet id', () {
      expect(
        () => Cip186UriParser.parse(
          Uri.parse(_schemeSignTx('lace')),
          expectedWalletId: 'yuti',
          expectedScheme: 'cip30dl-yuti',
        ),
        throwsA(isA<Cip186Exception>()),
      );
    });
  });
}
