import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../config/app_config.dart';
import 'wallet_service.dart';
import 'blockfrost_service.dart';
import 'transaction_service.dart';
import 'uex_service.dart';
import 'saturn_swap_service.dart';
import 'cardano_wallet_service.dart';

enum ChatIntent {
  balance,
  send,
  receive,
  swap,
  swapStatus,
  transaction,
  general,
}

enum SwapPlatform {
  saturnSwap, // Cardano-only DEX
  uex,        // Cross-chain DEX
  auto        // Let system choose best option
}

class SwapRequest {
  String? amount;
  String? fromCurrency;
  String? toCurrency;
  String? toAddress;
  String? awaitingAddressFor;
  SwapPlatform platform;
  
  SwapRequest({this.platform = SwapPlatform.auto});
  
  bool get isComplete => 
      amount != null && 
      fromCurrency != null && 
      toCurrency != null &&
      (toCurrency == 'ADA' || toAddress != null);
      
  bool get needsPlatformChoice => 
      platform == SwapPlatform.auto &&
      fromCurrency != null &&
      toCurrency != null &&
      _isCardanoToken(fromCurrency!) &&
      _isCardanoToken(toCurrency!);
      
  bool _isCardanoToken(String currency) {
    final cardanoTokens = {'ADA', 'DJED', 'SHEN', 'INDIGO', 'OPTIM', 'AGIX', 'NMKR'};
    return cardanoTokens.contains(currency.toUpperCase());
  }
  
  bool get isCrossChain => 
      (fromCurrency != null && !_isCardanoToken(fromCurrency!)) ||
      (toCurrency != null && !_isCardanoToken(toCurrency!));
}

// Enhanced entity extraction results
class ExtractedEntities {
  String? amount;
  String? fromCurrency;
  String? toCurrency;
  String? address;
  SwapPlatform? platform;
  double confidence;
  
  ExtractedEntities({
    this.amount,
    this.fromCurrency, 
    this.toCurrency,
    this.address,
    this.platform,
    this.confidence = 0.0,
  });
}

class ChatService {
  final AppConfig _config = AppConfig();
  final WalletService _walletService = WalletService();
  final BlockfrostService _blockfrostService = BlockfrostService();
  final UEXService _uexService = UEXService();
  final SaturnSwapService _saturnSwapService = SaturnSwapService();
  late final TransactionService _transactionService;
  final CardanoWalletService _cardanoWalletService = CardanoWalletService();

  // Wallet context cache to avoid excessive API calls
  Map<String, dynamic>? _cachedWalletContext;
  DateTime? _cachedWalletContextAt;
  static const Duration _walletContextTtl = Duration(seconds: 30);
  
  // Session management
  late final String _sessionId;
  // Local swap orchestration removed; backend handles full swap flow
  
  // Singleton pattern
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal() {
    _sessionId = const Uuid().v4();
    _transactionService = TransactionService(_walletService, _blockfrostService);
  }
  
  // Main entry point for processing user messages
  Future<ChatMessage> processMessage(String userInput) async {
    try {
      print('🔍 DEBUG: Starting processMessage with input: "$userInput"');
      
      // Swap orchestration handled by backend; no local pending state
      final intent = _detectIntent(userInput);
      print('🔍 DEBUG: Detected intent: $intent');
      
      switch (intent) {
        case ChatIntent.balance:
          return await _handleBalanceQuery();
        case ChatIntent.send:
          return await _handleSendCommand(userInput);
        case ChatIntent.receive:
          return await _handleReceiveAddress();
        case ChatIntent.swap:
          return await _handleSwapCommand(userInput);
        case ChatIntent.swapStatus:
          return await _handleSwapStatus(userInput);
        case ChatIntent.transaction:
          return await _handleTransactionQuery(userInput);
        case ChatIntent.general:
          return await _handleGeneralQuery(userInput);
      }
    } catch (e, stackTrace) {
      print('🔍 DEBUG: Error in processMessage: $e');
      print('🔍 DEBUG: Stack trace: $stackTrace');
      return ChatMessage.text(
        text: "❌ I'm sorry, something went wrong. Please try again.\n\nError: $e",
        isUser: false,
      );
    }
  }

  // Simplified method for UI - returns just the text
  Future<String> sendMessage(String userInput) async {
    try {
      print('🔍 DEBUG: sendMessage called with: "$userInput"');
      final chatMessage = await processMessage(userInput);
      print('🔍 DEBUG: sendMessage returning: "${chatMessage.text}"');
      return chatMessage.text;
    } catch (e) {
      print('🔍 DEBUG: sendMessage error: $e');
      return "Sorry, I encountered an error. Please try again.";
    }
  }
  
  ChatIntent _detectIntent(String input) {
    final lower = input.toLowerCase();
    
    // Balance queries
    if (lower.contains('balance') || 
        lower.contains('how much') ||
        (lower.contains('my') && (lower.contains('ada') || lower.contains('wallet')))) {
      return ChatIntent.balance;
    }
    
    // Send commands
    if (lower.startsWith('send') || 
        lower.contains('transfer') ||
        (lower.contains('pay') && lower.contains('to'))) {
      return ChatIntent.send;
    }
    
    // Receive address queries
    if ((lower.contains('address') && (lower.contains('my') || lower.contains('receive'))) ||
        lower.contains('qr code') ||
        lower.contains('deposit address')) {
      return ChatIntent.receive;
    }
    
    // Swap commands - enhanced detection
    if (lower.contains('swap') || 
        lower.contains('exchange') ||
        lower.contains('convert') ||
        lower.contains('trade') ||
        (lower.contains('buy') && _containsCurrency(lower)) ||
        (lower.contains('sell') && _containsCurrency(lower)) ||
        _hasSwapPattern(lower)) {
      return ChatIntent.swap;
    }
    
    // Swap status
    if (lower.contains('status') && lower.contains('order')) {
      return ChatIntent.swapStatus;
    }
    
    // Transaction queries
    if (lower.contains('transaction') || 
        lower.contains('history') ||
        lower.contains('recent')) {
      return ChatIntent.transaction;
    }
    
    return ChatIntent.general;
  }
  
  bool _containsCurrency(String text) {
    final currencies = ['ada', 'btc', 'eth', 'sol', 'usdt', 'usdc', 'bnb', 'dot', 'link', 'avax'];
    return currencies.any((currency) => text.contains(currency));
  }
  
  bool _hasSwapPattern(String text) {
    // Look for patterns like "X to Y", "X for Y", "get Y with X"
    final patterns = [
      r'\b\w+\s+(to|for|into)\s+\w+\b',
      r'\bget\s+\w+\s+(with|using)\s+\w+\b',
      r'\b\d+\.?\d*\s+\w+\s+(to|for|into)\s+\w+\b',
    ];
    
    return patterns.any((pattern) => RegExp(pattern, caseSensitive: false).hasMatch(text));
  }

  Future<ChatMessage> _handleBalanceQuery() async {
    try {
      final address = await _walletService.getReceiveAddress();
      final balanceLovelace = await _blockfrostService.getAdaBalance(address);
      final balanceAda = balanceLovelace.toDouble() / 1000000;
      
      // Get token balances
      final assets = await _blockfrostService.getAssets(address);
      
      String response = "Your current balance is **₳${balanceAda.toStringAsFixed(2)}** "
                       "($balanceAda ADA)";
      
      if (assets.isNotEmpty) {
        response += "\n\nYou also have ${assets.length} other token(s):";
        for (var asset in assets.take(5)) {
          final unit = asset['unit'] as String;
          final quantity = asset['quantity'] as String;
          response += "\n• $quantity of $unit";
        }
        if (assets.length > 5) {
          response += "\n...and ${assets.length - 5} more";
        }
      }
      
      return ChatMessage.text(text: response, isUser: false);
    } catch (e) {
      return ChatMessage.text(
        text: "❌ I couldn't fetch your balance. Please make sure you have an internet connection and try again.",
        isUser: false,
      );
    }
  }
  
  Future<ChatMessage> _handleSendCommand(String input) async {
    try {
      // Parse send command
      final parsed = _parseSendCommand(input);
      if (parsed == null) {
        return ChatMessage.text(
          text: "❌ I didn't understand that send command. Please use the format: "
                "'Send [amount] ADA to [address]'",
          isUser: false,
        );
      }
      
      final amount = parsed['amount'] as double;
      final address = parsed['address'] as String;
      
      // Validate address
      if (!_walletService.validateAddress(address)) {
        return ChatMessage.text(
          text: "❌ That doesn't look like a valid Cardano address. Please check and try again.",
          isUser: false,
        );
      }
      
      // Convert to lovelace
      final amountLovelace = BigInt.from(amount * 1000000);
      
      // For now, return a simulated response since transaction building isn't fully implemented
      return ChatMessage.text(
        text: "✅ I would send **₳$amount** to `${address.substring(0, 10)}...${address.substring(address.length - 10)}`\n\n"
              "⚠️ Note: Transaction building is not yet fully implemented in this demo.",
        isUser: false,
      );
      
      // TODO: Implement actual transaction when SDK integration is complete
      // final txHash = await _transactionService.sendAda(
      //   toAddress: address,
      //   amountLovelace: amountLovelace,
      // );
      // 
      // return ChatMessage.transaction(
      //   text: "✅ Sent **₳$amount** to `${address.substring(0, 10)}...`\n\n"
      //         "Transaction ID: `$txHash`",
      //   txHash: txHash,
      //   amount: amount.toString(),
      //   recipient: address,
      // );
    } catch (e) {
      return ChatMessage.text(
        text: "❌ Failed to send transaction: ${e.toString()}",
        isUser: false,
      );
    }
  }
  
  Future<ChatMessage> _handleReceiveAddress() async {
    try {
      final address = await _walletService.getReceiveAddress();
      
      return ChatMessage.qrCode(
        text: "Your Cardano receive address is:\n`$address`\n\n"
              "You can share this QR code or copy the address to receive ADA.",
        address: address,
      );
    } catch (e) {
      return ChatMessage.text(
        text: "❌ I couldn't retrieve your address. Please try again.",
        isUser: false,
      );
    }
  }
  
  // Enhanced swap command handling now delegated to backend orchestrator
  Future<ChatMessage> _handleSwapCommand(String input) async {
    try {
      print('🔍 DEBUG: Forwarding swap request to backend orchestrator: "$input"');
      final reply = await _callTBackend(input);
      return ChatMessage.text(text: reply, isUser: false);
    } catch (e) {
      print('🔍 DEBUG: Error in _handleSwapCommand (orchestrator): $e');
      return ChatMessage.text(
        text: "❌ Failed to process swap: ${e.toString()}",
        isUser: false,
      );
    }
  }
  
  // Local swap entity extraction removed
 
  // Local swap clarification removed
 
  // Local platform choice prompt removed
 
  // Local pending swap handling removed
 
  // Local address capture removed
 
  // Local order creation removed
 
  // Removed Saturn flow
 
  // Removed UEX flow
 
  Future<ChatMessage> _handleSwapStatus(String input) async {
    // Parse order ID from input
    final regex = RegExp(r'([a-f0-9-]{8,})');
    final match = regex.firstMatch(input.toLowerCase());
    
    if (match == null) {
      return ChatMessage.text(
        text: "❌ I couldn't find an order ID. Please include the order ID in your query.",
        isUser: false,
      );
    }
    
    final orderId = match.group(1)!;
    
    try {
      // Use real UEX service to get swap status
      final status = await _uexService.getSwapStatus(orderId);
      
      String statusEmoji = '';
      String statusText = '';
      
      switch (status.status.toLowerCase()) {
        case 'pending':
          statusEmoji = '⏳';
          statusText = 'pending';
          break;
        case 'confirmed':
        case 'completed':
          statusEmoji = '✅';
          statusText = 'completed';
          break;
        case 'failed':
          statusEmoji = '❌';
          statusText = 'failed';
          break;
        default:
          statusEmoji = '❓';
          statusText = status.status;
      }
      
      String response = "**Order $orderId Status:** $statusEmoji **$statusText**\n\n";
      
      if (status.confirmations != null) {
        response += "**Confirmations:** ${status.confirmations}\n";
      }
      
      if (status.errorMessage != null) {
        response += "**Error:** ${status.errorMessage}\n";
      }
      
      response += "**Last Updated:** ${_formatTime(status.timestamp)}";
      
      return ChatMessage.text(text: response, isUser: false);
    } catch (e) {
      return ChatMessage.text(
        text: "❌ Unable to fetch status for order $orderId.\n\n"
              "Please check the order ID or try again later.\n\n"
              "*Error: ${e.toString()}*",
        isUser: false,
      );
    }
  }
  
  Future<ChatMessage> _handleTransactionQuery(String input) async {
    try {
      final address = await _walletService.getReceiveAddress();
      final transactions = await _blockfrostService.getTransactions(address);
      
      if (transactions.isEmpty) {
        return ChatMessage.text(
          text: "You don't have any transactions yet.",
          isUser: false,
        );
      }
      
      String response = "Here are your recent transactions:\n";
      for (var tx in transactions.take(5)) {
        final hash = tx['tx_hash'] as String;
        response += "\n• `${hash.substring(0, 10)}...` - ${tx['block_time']}";
      }
      
      if (transactions.length > 5) {
        response += "\n\n...and ${transactions.length - 5} more";
      }
      
      return ChatMessage.text(text: response, isUser: false);
    } catch (e) {
      return ChatMessage.text(
        text: "❌ I couldn't fetch your transaction history. Please try again.",
        isUser: false,
      );
    }
  }
  
  Future<ChatMessage> _handleGeneralQuery(String input) async {
    try {
      // Forward to T-Backend for AI response
      final response = await _callTBackend(input);
      return ChatMessage.text(text: response, isUser: false);
    } catch (e) {
      return ChatMessage.text(
        text: "I'm having trouble connecting to my AI backend. "
              "I can still help with wallet commands like checking balance, "
              "sending ADA, or swapping tokens!",
        isUser: false,
      );
    }
  }
  
  Future<String> _callTBackend(String message) async {
    print('🔍 DEBUG: _callTBackend called with message: "$message"');
    
    final url = Uri.parse("${_config.tBackendUrl}/chat");
    print('🔍 DEBUG: API URL: $url');
    
    final headers = {
      'Content-Type': 'application/json',
      if (_config.tBackendApiKey.isNotEmpty) 'api-key': _config.tBackendApiKey,
    };
    print('🔍 DEBUG: Headers: $headers');
    print('🔍 DEBUG: API Key present: ${_config.tBackendApiKey.isNotEmpty}');
    print('🔍 DEBUG: API Key value: ${_config.tBackendApiKey.isEmpty ? 'EMPTY' : '${_config.tBackendApiKey.substring(0, 10)}...'}');
    
    // Build wallet context snapshot (best-effort)
    Map<String, dynamic>? walletContext;
    try {
      walletContext = await _getWalletContextSnapshot();
    } catch (e) {
      print('🔍 DEBUG: Failed to build wallet context: $e');
    }

    final body = jsonEncode({
      'message': message,
      'session_id': _sessionId,
      if (walletContext != null)
        'context': {
          'wallet': walletContext,
          'hints': 'Use wallet.context to answer user questions about balance, transactions, and holdings. All values are public chain data; never request or expose private keys. If user requests actions like send/swap, ask for missing details and call appropriate tools.'
        },
    });
    print('🔍 DEBUG: Request body: $body');
    
    try {
      print('🔍 DEBUG: Making HTTP POST request...');
      final response = await http.post(url, headers: headers, body: body);
      
      print('🔍 DEBUG: HTTP response status: ${response.statusCode}');
      print('🔍 DEBUG: HTTP response headers: ${response.headers}');
      print('🔍 DEBUG: HTTP response body: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('🔍 DEBUG: Parsed response data: $data');
        final reply = data['reply'] ?? "I'm not sure how to respond to that.";
        print('🔍 DEBUG: Extracted reply: "$reply"');
        return reply;
      } else {
        print('🔍 DEBUG: Non-200 status code, throwing exception');
        throw Exception('T-Backend error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('🔍 DEBUG: Exception in _callTBackend: $e');
      print('🔍 DEBUG: Exception type: ${e.runtimeType}');
      rethrow;
    }
  }
  
  // Build a short-lived snapshot of the user's wallet to provide context to T
  Future<Map<String, dynamic>?> _getWalletContextSnapshot() async {
    try {
      // Check cache
      final now = DateTime.now();
      if (_cachedWalletContext != null &&
          _cachedWalletContextAt != null &&
          now.difference(_cachedWalletContextAt!) < _walletContextTtl) {
        return _cachedWalletContext;
      }

      // Determine if wallet is available
      final hasCardano = _cardanoWalletService.isConnected;
      final hasLocalWallet = _walletService.hasWallet && _walletService.isWalletLoaded;
      if (!hasCardano && !hasLocalWallet) {
        return null;
      }

      // Resolve address
      final address = await _walletService.getReceiveAddress();
      final stakeAddr = _cardanoWalletService.stakeAddress;

      // Fetch on-chain data
      final balanceLovelace = await _blockfrostService.getAdaBalance(address);
      final balanceAda = balanceLovelace.toDouble() / 1000000.0;

      final assets = await _blockfrostService.getAssets(address);
      // Reduce assets to a concise summary (top 20 by quantity)
      final summarizedAssets = List<Map<String, dynamic>>.from(assets)
          .map((a) => {
                'unit': a['unit'],
                'quantity': a['quantity'],
              })
          .take(20)
          .toList();

      final txs = await _blockfrostService.getTransactions(address, page: 1);
      final summarizedTxs = txs
          .map((t) => {
                'tx_hash': t['tx_hash'],
                'block_height': t['block_height'],
                'tx_index': t['tx_index'],
                'block_time': t['block_time'],
              })
          .take(10)
          .toList();

      final snapshot = {
        'network': _config.isMainnet ? 'mainnet' : 'testnet',
        'address': address,
        if (stakeAddr != null) 'stake_address': stakeAddr,
        'ada_balance': {
          'lovelace': balanceLovelace.toString(),
          'ada': balanceAda.toStringAsFixed(6),
        },
        'assets': summarizedAssets,
        'recent_transactions': summarizedTxs,
        'capabilities': {
          'can_send': true,
          'can_swap': true,
        },
      };

      _cachedWalletContext = snapshot;
      _cachedWalletContextAt = now;
      return snapshot;
    } catch (e) {
      print('🔍 DEBUG: Error building wallet context snapshot: $e');
      return null;
    }
  }
  
  Map<String, dynamic>? _parseSendCommand(String input) {
    // Try to parse "send X ADA to address"
    final regex = RegExp(
      r'(\d+\.?\d*)\s*(ada)?\s*to\s*([a-zA-Z0-9]+)',
      caseSensitive: false,
    );
    
    final match = regex.firstMatch(input);
    if (match == null) return null;
    
    return {
      'amount': double.parse(match.group(1)!),
      'address': input.substring(match.end).trim(),
    };
  }
  
  String _normalizeCurrency(String currency) {
    final upper = currency.toUpperCase();
    final currencyMap = {
      'BITCOIN': 'BTC',
      'ETHEREUM': 'ETH', 
      'CARDANO': 'ADA',
      'SOLANA': 'SOL',
      'TETHER': 'USDT',
      'USD': 'USDT',
      'USDC': 'USDC',
      'BNB': 'BNB',
      'BINANCE': 'BNB',
      'DOT': 'DOT',
      'POLKADOT': 'DOT',
      'LINK': 'LINK',
      'CHAINLINK': 'LINK',
      'AVAX': 'AVAX',
      'AVALANCHE': 'AVAX',
      'MATIC': 'MATIC',
      'POLYGON': 'MATIC',
    };
    
    return currencyMap[upper] ?? upper;
  }
  
  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} minutes ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} hours ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      // Format as date if older than a week
      return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    }
  }
} 