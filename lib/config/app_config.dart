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
  String get uexSwapApiUrl => const String.fromEnvironment('UEX_SWAP_API_URL',
      defaultValue: 'https://uexswap.com/api');
  String get handleApiBase => const String.fromEnvironment('HANDLE_API_BASE',
      defaultValue: 'https://api.handle.me');

  // API Keys (these should be loaded from secure storage or environment)
  String get blockfrostApiKey =>
      const String.fromEnvironment('BLOCKFROST_API_KEY', defaultValue: '');
  String get tBackendApiKey =>
      const String.fromEnvironment('T_BACKEND_API_KEY', defaultValue: '');
  String get handleApiKey =>
      const String.fromEnvironment('HANDLE_API_KEY', defaultValue: '');

  // UEX OAuth credentials
  String get uexClientId =>
      const String.fromEnvironment('UEX_CLIENT_ID', defaultValue: '');
  String get uexSecretKey =>
      const String.fromEnvironment('UEX_SECRET_KEY', defaultValue: '');
  String get uexRefCode => const String.fromEnvironment('UEX_REF_CODE',
      defaultValue: '5xyjtzzkg1c8');

  // Oracle/Price config
  String get charli3AgentAdaFeedAddress => const String.fromEnvironment(
      'CHARLI3_AGENT_ADA_FEED_ADDRESS',
      defaultValue:
          'addr1w8zrt30lsdj4x2z0adsvyfrx5rxpxz9vtss6jqv63mhtk9q0063c0');
  double get premiumUsdPrice => double.parse(
      const String.fromEnvironment('PREMIUM_USD_PRICE', defaultValue: '500.0'));

  // Network configuration
  bool get isMainnet =>
      const bool.fromEnvironment('IS_MAINNET', defaultValue: true);

  // Smart Wallet (zkFold) configuration
  bool get smartWalletEnabled =>
      const bool.fromEnvironment('SMART_WALLET_ENABLED', defaultValue: true);
  String get smartWalletApiBase => const String.fromEnvironment(
      'SMART_WALLET_API_BASE',
      defaultValue: 'https://wallet-api.zkfold.io');
  String get smartWalletProverBase => const String.fromEnvironment(
      'SMART_WALLET_PROVER_BASE',
      defaultValue: 'https://wallet-prover.zkfold.io');
  String get smartWalletApiKey => const String.fromEnvironment(
      'SMART_WALLET_API_KEY',
      defaultValue: '');
  // Optional: if using GoogleSignIn directly on Web/mobile
  String get smartWalletGoogleWebClientId => const String.fromEnvironment(
      'SMART_WALLET_GOOGLE_WEB_CLIENT_ID',
      defaultValue: '');

  // App settings
  String get appName => 'Yuti';
  String get appVersion => '1.0.0';
  String get appDescription =>
      'A conversational Cardano wallet with Agent T AI assistant';

  // Company contact information
  String get companyName => 'Flux Point Studios, Inc.';
  String get contactEmail => 'contact@fluxpointstudios.com';
  String get companyWebsite => 'https://fluxpointstudios.com';
  String get privacyPolicyUrl => 'https://fluxpointstudios.com/privacy-policy';
  String get termsOfServiceUrl => 'https://fluxpointstudios.com/tos';
  String get supportUrl => 'https://discord.gg/fluxpointstudios';

  // Validation
  bool get isConfigured {
    return blockfrostApiKey.isNotEmpty && tBackendApiKey.isNotEmpty;
  }
}
