@Tags(['cip186-signing'])

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuti/cip186/app_wiring.dart';

// Startup-safety smoke for the main.dart wiring: `await setupCip186Signing(...)`
// must resolve the persisted root secret and register the MethodChannel
// without throwing (a throw here would break app launch). The deep-link
// ROUTING itself is proven in router_test.dart, and the real native channel
// delivery is proven by the on-device smoke (adb am start).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('setupCip186Signing completes without error (generates root secret)',
      () async {
    // Fresh storage: no root secret yet -> it must be generated + persisted.
    FlutterSecureStorage.setMockInitialValues({});
    await setupCip186Signing(isMainnet: false);
    final stored =
        await const FlutterSecureStorage().read(key: 'cip186_root_secret');
    expect(stored, isNotNull);
    expect(base64Url.decode(stored!).length, 32);
  });

  test('setupCip186Signing reuses an existing root secret', () async {
    final seed = base64Url.encode(List.filled(32, 9));
    FlutterSecureStorage.setMockInitialValues({'cip186_root_secret': seed});
    await setupCip186Signing(isMainnet: false);
    final stored =
        await const FlutterSecureStorage().read(key: 'cip186_root_secret');
    expect(stored, seed);
  });
}
