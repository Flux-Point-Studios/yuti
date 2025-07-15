class AppConfig {
  // Singleton pattern
  static final AppConfig _instance = AppConfig._internal();
  factory AppConfig() => _instance;
  AppConfig._internal();

  // API URLs
  String get blockfrostApiUrl => 'https://cardano-mainnet.blockfrost.io';
  String get tBackendUrl => const String.fromEnvironment('T_BACKEND_URL',
      defaultValue: 'https://api.fluxpointstudios.com');
  String get uexApiUrl => const String.fromEnvironment('UEX_API_URL',
      defaultValue: 'https://uex.us/api');

  // API Keys (these should be loaded from secure storage or environment)
  String get blockfrostApiKey =>
      const String.fromEnvironment('BLOCKFROST_API_KEY', defaultValue: '');
  String get tBackendApiKey =>
      const String.fromEnvironment('T_BACKEND_API_KEY', defaultValue: '');

  // UEX OAuth credentials
  String get uexClientId =>
      const String.fromEnvironment('UEX_CLIENT_ID', defaultValue: '');
  String get uexSecretKey =>
      const String.fromEnvironment('UEX_SECRET_KEY', defaultValue: '');
  String get uexRefCode => const String.fromEnvironment('UEX_REF_CODE',
      defaultValue: '5xyjtzzkg1c8');

  // Network configuration
  bool get isMainnet =>
      const bool.fromEnvironment('IS_MAINNET', defaultValue: true);

  // App settings
  String get appName => 'bluelight';
  String get appVersion => '1.0.0';
  String get appDescription =>
      'A conversational Cardano wallet with Agent T AI assistant';

  // Company contact information
  String get companyName => 'Flux Point Studios, Inc.';
  String get contactEmail => 'contact@fluxpointstudios.com';
  String get companyWebsite => 'https://fluxpointstudios.com';
  String get privacyPolicyUrl => 'https://fluxpointstudios.com/privacy-policy';
  String get termsOfServiceUrl => 'https://fluxpointstudios.com/tos';
  String get supportUrl => 'https://fluxpointstudios.com/support';

  // Validation
  bool get isConfigured {
    return blockfrostApiKey.isNotEmpty && tBackendApiKey.isNotEmpty;
  }
}
