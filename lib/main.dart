import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'screens/welcome_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/pricing_screen.dart';
import 'services/supabase_service.dart';
import 'services/wallet_service.dart';
import 'screens/chat_screen.dart';
import 'screens/gamechanger_callback_screen.dart';
import 'screens/browser_screen.dart';
import 'utils/app_colors.dart';
import 'config/secure_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await SupabaseService.initialize();

  // Initialize API keys for all platforms (web, iOS, Android)
  await _initializeApiKeys();

  // Set up GameChanger callback handler for iOS
  _setupGameChangerCallbackHandler();

  // Set system UI overlay style for blue light theme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.backgroundDark,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const MyApp());
}

/// Initialize API keys for all platforms since .env files aren't supported in mobile
Future<void> _initializeApiKeys() async {
  try {
    final secureConfig = SecureConfig();

    // Initialize with production API keys
    // These are stored securely using FlutterSecureStorage
    await secureConfig.initializeKeys(
      // T-Backend API key for AI features
      tBackendKey:
          '<REDACTED>',
      // Blockfrost API key for Cardano blockchain data
      blockfrostKey: 'mainnetpzgQb7C0U7j75FeyY7pb5seDEC1Woq7E',
    );

    print('🔍 DEBUG: API keys initialized successfully (T-Backend + Blockfrost)');
  } catch (e) {
    print('🔍 DEBUG: Error initializing API keys: $e');
  }
}

// Global variable to store GameChanger callback data for iOS
String? _pendingGameChangerCallback;

/// Set up method channel handler for GameChanger callbacks from iOS
void _setupGameChangerCallbackHandler() {
  const platform = MethodChannel('com.bluelight/gamechanger');
  
  platform.setMethodCallHandler((call) async {
    if (call.method == 'handleGameChangerCallback') {
      final String callbackData = call.arguments as String;
      print('🔍 DEBUG: Received GameChanger callback data from iOS: $callbackData');
      
      // Store the callback data globally so the callback screen can access it
      _pendingGameChangerCallback = callbackData;
      
      print('🔍 DEBUG: Stored callback data for processing');
    }
  });
  
  print('🔍 DEBUG: GameChanger method channel handler set up');
}

/// Get and clear pending GameChanger callback data
String? getPendingGameChangerCallback() {
  final data = _pendingGameChangerCallback;
  _pendingGameChangerCallback = null; // Clear after reading
  return data;
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider(create: (_) => WalletService()),
      ],
      child: MaterialApp(
        title: 'bluelight',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          primaryColor: AppColors.primaryBlue,
          scaffoldBackgroundColor: AppColors.backgroundDark,
          brightness: Brightness.dark,
          appBarTheme: const AppBarTheme(
            backgroundColor: AppColors.glassBackground,
            elevation: 0,
            iconTheme: IconThemeData(color: AppColors.textPrimary),
            titleTextStyle: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
            systemOverlayStyle: SystemUiOverlayStyle(
              statusBarColor: Colors.transparent,
              statusBarIconBrightness: Brightness.light,
            ),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              backgroundColor: Colors.transparent,
              elevation: 0,
              shadowColor: AppColors.shadowColorDeep,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              side: const BorderSide(
                color: AppColors.glassBorder,
                width: 1,
              ),
            ).copyWith(
              backgroundColor: MaterialStateProperty.resolveWith<Color?>(
                (Set<MaterialState> states) {
                  if (states.contains(MaterialState.pressed)) {
                    return AppColors.glassBlue;
                  }
                  return AppColors.glassSurface;
                },
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: AppColors.glassSurface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.glassBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.glassBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide:
                  const BorderSide(color: AppColors.primaryBlue, width: 2),
            ),
            labelStyle: const TextStyle(color: AppColors.textSecondary),
            hintStyle: const TextStyle(color: AppColors.textTertiary),
          ),
          cardTheme: CardThemeData(
            color: Colors.transparent,
            elevation: 0,
            shadowColor: AppColors.shadowColorDeep,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppColors.glassBorder, width: 1),
            ),
          ),
          textTheme: const TextTheme(
            headlineLarge: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
            headlineMedium: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
            bodyLarge: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
            ),
            bodyMedium: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          colorScheme: const ColorScheme.dark(
            primary: AppColors.primaryBlue,
            secondary: AppColors.lightBlue,
            surface: AppColors.backgroundCard,
            error: AppColors.error,
            onPrimary: Colors.white,
            onSecondary: Colors.white,
            onSurface: AppColors.textPrimary,
            onError: Colors.white,
          ),
        ),
        home: const SplashScreen(),
        routes: {
          '/welcome': (context) => const WelcomeScreen(),
          '/onboarding': (context) => const OnboardingScreen(),
          '/pricing': (context) => const PricingScreen(),
          '/chat': (context) => const ChatScreen(),
          '/gamechanger-callback': (context) =>
              const GameChangerCallbackScreen(),
          '/browser': (context) => const BrowserScreen(),
        },
      ),
    );
  }
}
