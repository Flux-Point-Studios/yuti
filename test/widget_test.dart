// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bluelight/main.dart';
import 'package:bluelight/screens/splash_screen.dart' as splash;
import 'package:bluelight/screens/onboarding_screen.dart';
import 'package:bluelight/screens/chat_screen.dart';
import 'package:bluelight/services/wallet_service.dart';

void main() {
  group('App Initialization Tests', () {
    testWidgets('App starts with correct structure',
        (WidgetTester tester) async {
      // Build our app and trigger a frame.
      await tester.pumpWidget(const MyApp());

      // Wait for the app to settle
      await tester.pumpAndSettle();

      // Verify that the app loads (specific widget checks depend on the initial route)
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });

  group('SplashScreen Tests', () {
    testWidgets('SplashScreen displays logo and loading indicator',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: splash.SplashScreen(),
        ),
      );

      // Check for logo or icon
      expect(find.byIcon(Icons.account_balance_wallet), findsOneWidget);

      // Check for loading indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('OnboardingScreen Tests', () {
    testWidgets('OnboardingScreen shows welcome message',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: OnboardingScreen(),
        ),
      );

      // Check for welcome text
      expect(find.text('Welcome to bluelight'), findsOneWidget);
    });
  });

  group('ChatScreen Tests', () {
    testWidgets('ChatScreen displays basic UI components',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ChatScreen(),
        ),
      );

      // Check for basic chat UI elements
      expect(find.byType(AppBar), findsOneWidget);
    });
  });

  group('WalletService Tests', () {
    test('WalletService initializes correctly', () async {
      final walletService = WalletService();
      await walletService.initialize();

      // Test basic getters
      expect(walletService.isWalletLoaded, false);
      expect(walletService.walletName, null);
      expect(walletService.hasWallet, false);
    });

    test('WalletService validates addresses correctly', () {
      final walletService = WalletService();

      // Test valid addresses
      expect(
          walletService.validateAddress(
              'addr1qx2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzer3jcu5d8ps7zex2k2xt3uqxgjqnnj83ws8lhrn648jjxtwq2ytjmg'),
          true);
      expect(
          walletService.validateAddress(
              'addr_test1qx2fxv2umyhttkxyxp8x0dlpdt3k6cwng5pxj3jhsydzer3jcu5d8ps7zex2k2xt3uqxgjqnnj83ws8lhrn648jjxtwq2ytjmg'),
          true);

      // Test invalid addresses
      expect(walletService.validateAddress(''), false);
      expect(walletService.validateAddress('invalid'), false);
      expect(walletService.validateAddress('addr1'), false);
    });

    test('WalletService mnemonic generation', () async {
      final walletService = WalletService();

      // Test mnemonic generation
      final mnemonic = await walletService.createWallet();
      expect(mnemonic, isNotNull);
      expect(mnemonic.split(' ').length,
          24); // 256-bit mnemonic should have 24 words

      // Test wallet creation
      expect(walletService.hasWallet, true);
      expect(walletService.isWalletLoaded, true);
      expect(walletService.walletName, isNotNull);
    });

    test('WalletService address generation', () async {
      final walletService = WalletService();
      await walletService.createWallet();

      final address = await walletService.getReceiveAddress();
      expect(address, isNotNull);
      expect(address.startsWith('addr1'), true);
      expect(walletService.validateAddress(address), true);
    });
  });
}
