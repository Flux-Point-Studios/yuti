import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuti/cip186/attestation.dart';
import 'package:yuti/cip186/errors.dart';

void main() {
  group('AttestationBuilder success — callback contract (spec §Callback contract)', () {
    test('appends approved=response and base64url payload to https redirect', () {
      final url = AttestationBuilder.buildApproved(
        redirect: Uri.parse('https://aegis.example/cb'),
        walletNonce: Uint8List.fromList(List.filled(24, 6)),
        ciphertext: Uint8List.fromList(List.filled(16, 9)),
        signature: Uint8List.fromList(List.filled(64, 7)),
      );
      expect(url.scheme, 'https');
      expect(url.host, 'aegis.example');
      expect(url.queryParameters['response'], 'approved');
      expect(url.queryParameters['nonce'], isNotNull);
      expect(url.queryParameters['payload'], isNotNull);
      expect(url.queryParameters['signature'], isNotNull);
    });

    test('appends signature as the FINAL query parameter (spec §Response signing)', () {
      final url = AttestationBuilder.buildApproved(
        redirect: Uri.parse('https://aegis.example/cb'),
        walletNonce: Uint8List.fromList(List.filled(24, 6)),
        ciphertext: Uint8List.fromList(List.filled(16, 9)),
        signature: Uint8List.fromList(List.filled(64, 7)),
      );
      final qs = url.toString().split('?')[1];
      final keys = qs.split('&').map((p) => p.split('=')[0]).toList();
      expect(keys.last, 'signature',
          reason: 'signature MUST be the final emitted parameter');
    });

    test('honors custom-scheme dApp redirect (e.g. aegis-bundle:)', () {
      final url = AttestationBuilder.buildApproved(
        redirect: Uri.parse('com.fluxpointstudios.aegis://cb'),
        walletNonce: Uint8List.fromList(List.filled(24, 6)),
        ciphertext: Uint8List.fromList(List.filled(16, 9)),
        signature: Uint8List.fromList(List.filled(64, 7)),
      );
      expect(url.scheme, 'com.fluxpointstudios.aegis');
      expect(url.queryParameters['response'], 'approved');
    });

    test('encodes payload using base64url with no padding', () {
      final url = AttestationBuilder.buildApproved(
        redirect: Uri.parse('https://aegis.example/cb'),
        walletNonce: Uint8List.fromList(List.filled(24, 6)),
        ciphertext: Uint8List.fromList([1, 2, 3]),
        signature: Uint8List.fromList(List.filled(64, 7)),
      );
      final payload = url.queryParameters['payload']!;
      expect(payload.contains('='), isFalse);
      expect(base64Url.decode(payload + '====='.substring(0, (4 - payload.length % 4) % 4)),
          equals([1, 2, 3]));
    });
  });

  group('AttestationBuilder connect (signed handshake — spec §connect)', () {
    test('signs the (method, walletKey, nonce, echo, payload) canonical subject', () {
      String? signed;
      final url = AttestationBuilder.buildConnectApprovedSigned(
        redirect: Uri.parse('https://aegis.example/cb'),
        walletKey: Uint8List.fromList(List.filled(32, 5)),
        walletNonce: Uint8List.fromList(List.filled(24, 6)),
        ciphertext: Uint8List.fromList(List.filled(16, 9)),
        echoNonce: Uint8List.fromList(List.filled(24, 1)),
        sign: (subject) {
          signed = subject;
          return Uint8List.fromList(List.filled(64, 7));
        },
      );
      expect(url.queryParameters['response'], 'approved');
      expect(url.queryParameters['method'], 'connect');
      expect(url.queryParameters['walletKey'], isNotNull);
      expect(url.queryParameters['echo'], isNotNull);
      expect(url.queryParameters['payload'], isNotNull);
      // The wallet signs exactly the bytes the dApp re-derives (sig stripped).
      expect(signed, AttestationBuilder.canonicalSubject(url));
    });

    test('appends signature as the FINAL parameter and echoes the nonce verbatim', () {
      final echo = Uint8List.fromList(List.generate(24, (i) => i));
      final url = AttestationBuilder.buildConnectApprovedSigned(
        redirect: Uri.parse('https://aegis.example/cb'),
        walletKey: Uint8List.fromList(List.filled(32, 5)),
        walletNonce: Uint8List.fromList(List.filled(24, 6)),
        ciphertext: Uint8List.fromList(List.filled(16, 9)),
        echoNonce: echo,
        sign: (_) => Uint8List.fromList(List.filled(64, 7)),
      );
      final keys = url.toString().split('?')[1].split('&').map((p) => p.split('=')[0]).toList();
      expect(keys.last, 'signature');
      final e = url.queryParameters['echo']!;
      expect(base64Url.decode(e + '=' * ((4 - e.length % 4) % 4)), equals(echo));
    });
  });

  group('AttestationBuilder rejection — error envelope (spec §Appendix A)', () {
    test('encodes errorCode and errorMessage on commit mismatch', () {
      final url = AttestationBuilder.buildRejected(
        redirect: Uri.parse('https://aegis.example/cb'),
        code: Cip186ErrorCode.commitMismatch,
        message: 'commit mismatch',
      );
      expect(url.queryParameters['response'], 'rejected');
      expect(url.queryParameters['errorCode'], '-2');
      expect(url.queryParameters['errorMessage'], 'commit mismatch');
    });

    test('emits errorCode=-9 for unknown query key family', () {
      final url = AttestationBuilder.buildRejected(
        redirect: Uri.parse('https://aegis.example/cb'),
        code: Cip186ErrorCode.unsupportedVersion,
        message: 'unknown key: extraField',
      );
      expect(url.queryParameters['errorCode'], '-9');
    });

    test('emits errorCode=-32 for payload-too-large', () {
      final url = AttestationBuilder.buildRejected(
        redirect: Uri.parse('https://aegis.example/cb'),
        code: Cip186ErrorCode.payloadTooLarge,
        message: 'payload over 12 KiB',
      );
      expect(url.queryParameters['errorCode'], '-32');
    });
  });

  group('AttestationBuilder canonical-subject (spec §Response signing §Signature construction)', () {
    test('prefixes with cip30dl-v1\\n domain separator', () {
      final subject = AttestationBuilder.canonicalSubject(
        Uri.parse('https://aegis.example/cb?response=approved'
            '&nonce=BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE'),
      );
      expect(subject.startsWith('cip30dl-v1\n'), isTrue);
    });

    test('sorts query parameters by lex byte order', () {
      final subject = AttestationBuilder.canonicalSubject(
        Uri.parse('https://aegis.example/cb?zeta=1&alpha=2&middle=3'),
      );
      final body = subject.substring('cip30dl-v1\n'.length);
      final qs = body.split('?')[1];
      final keys = qs.split('&').map((p) => p.split('=')[0]).toList();
      expect(keys, ['alpha', 'middle', 'zeta']);
    });

    test('lowercases host', () {
      final subject = AttestationBuilder.canonicalSubject(
        Uri.parse('https://AEGIS.Example/cb?a=1'),
      );
      expect(subject.contains('https://aegis.example/cb'), isTrue);
    });

    test('strips the signature parameter before canonicalising', () {
      final subject = AttestationBuilder.canonicalSubject(
        Uri.parse('https://aegis.example/cb?a=1&signature=abc&b=2'),
      );
      expect(subject.contains('signature='), isFalse);
    });

    test('encodes space as %20 (never +) and uses uppercase hex', () {
      final subject = AttestationBuilder.canonicalSubject(
        Uri.parse('https://aegis.example/cb?msg=hello%20world%2F'),
      );
      expect(subject.contains('%20'), isTrue);
      expect(subject.contains('+'), isFalse);
      expect(subject.contains('%2F'), isTrue);
      expect(subject.contains('%2f'), isFalse);
    });

    test('preserves path bytes verbatim (no host case in path)', () {
      final subject = AttestationBuilder.canonicalSubject(
        Uri.parse('https://aegis.example/CB/CamelCase?a=1'),
      );
      expect(subject.contains('/CB/CamelCase'), isTrue);
    });
  });
}
