import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/chat_message.dart';
import '../config/app_config.dart';
import '../config/secure_config.dart';
import 'wallet_service.dart';
import 'blockfrost_service.dart';
import 'transaction_service.dart';
import 'uex_service.dart';
import 'saturn_swap_service.dart';
import 'cardano_wallet_service.dart';
import 'address_book_service.dart';
import 'smart_wallet_service.dart';
import 'auth_service.dart';
import '../models/address_book_entry.dart';
import 'dart:math' as math;

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
  final AddressBookService _addressBookService = AddressBookService();

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

  // Streaming chunks from T-Backend
  class ChatStreamChunk {
    ChatStreamChunk(this.delta, {this.isError = false});
    final String delta;
    final bool isError;
  }

  // Stream tokens via SSE (mobile/desktop). On web, fall back to one-shot body parse.
  Stream<ChatStreamChunk> streamMessage({
    required String message,
    String? imageDataUri,
  }) async* {
    final String endpoint = kIsWeb ? '/api/t/chat' : "${_config.tBackendUrl}/chat";
    final uri = Uri.parse(endpoint);

    // Load API key when not on web (serverless proxy injects on web)
    String apiKey = '';
    if (!kIsWeb) {
      try {
        apiKey = await SecureConfig().getTBackendApiKey();
      } catch (_) {
        apiKey = _config.tBackendApiKey;
      }
    }

    // Web fallback: issue a normal POST including stream:true, then split any SSE-like text
    if (kIsWeb) {
      try {
        final headers = {'Content-Type': 'application/json'};
        final body = jsonEncode({
          'message': message,
          'session_id': _sessionId,
          'stream': true,
          if (imageDataUri != null) 'image_data': imageDataUri,
        });
        final resp = await http.post(uri, headers: headers, body: body);
        if (resp.statusCode != 200) {
          yield ChatStreamChunk('[error] ${resp.statusCode} ${resp.body}', isError: true);
          return;
        }
        final contentType = resp.headers['content-type'] ?? '';
        final text = resp.body;
        if (contentType.contains('text/event-stream') || text.startsWith('data:')) {
          // Best-effort parse of SSE frames from buffered text
          final lines = const LineSplitter().convert(text);
          for (final line in lines) {
            if (line.startsWith('data: ')) {
              final payload = line.substring(6);
              final isError = payload.startsWith('[error]');
              yield ChatStreamChunk(payload, isError: isError);
            }
          }
        } else {
          // Treat body as final reply text
          yield ChatStreamChunk(text, isError: false);
        }
      } catch (e) {
        yield ChatStreamChunk('[error] $e', isError: true);
      }
      return;
    }

    // Mobile/desktop: use streamed request and parse SSE lines incrementally
    final client = http.Client();
    try {
      final req = http.Request('POST', uri);
      req.headers['Content-Type'] = 'application/json';
      if (apiKey.isNotEmpty) {
        req.headers['api-key'] = apiKey;
      }
      req.headers['Accept'] = 'text/event-stream';
      final body = <String, dynamic>{
        'message': message,
        'session_id': _sessionId,
        'stream': true,
        if (imageDataUri != null) 'image_data': imageDataUri,
      };
      req.body = jsonEncode(body);

      final resp = await client.send(req);
      // Decode streamed text and split lines
      final lines = resp.stream.transform(utf8.decoder).transform(const LineSplitter());
      await for (final line in lines) {
        if (line.startsWith('data: ')) {
          final payload = line.substring(6);
          final isError = payload.startsWith('[error]');
          yield ChatStreamChunk(payload, isError: isError);
        }
      }
    } catch (e) {
      yield ChatStreamChunk('[error] $e', isError: true);
    } finally {
      client.close();
    }
  }
  
  // System messages stream for background notifications (e.g., swap status updates)
  final StreamController<ChatMessage> _systemMessagesController = StreamController<ChatMessage>.broadcast();
  Stream<ChatMessage> get systemMessages => _systemMessagesController.stream;

  // Track active UEX watchers by address
  final Map<String, StreamSubscription> _uexWatchSubscriptions = {};

  // Start watching a UEX swap by deposit/destination address
  void startWatchingUexAddress({
    required String watchAddress,
    required String token,
  }) {
    // Cancel any existing watcher on the same address
    _uexWatchSubscriptions[watchAddress]?.cancel();

    final Stream<Map<String, dynamic>> stream = _uexService.watchSwapStatusByAddress(
      watchAddress: watchAddress,
      token: token,
    );

    final sub = stream.listen((event) {
      final status = (event['status'] ?? '').toString();

      String emoji;
      switch (status) {
        case 'PENDING':
        case 'MEMPOOL':
        case 'NO_DATA':
          emoji = '⏳';
          break;
        case 'COMPLETED':
        case 'SUCCESS':
        case 'FILLED':
          emoji = '✅';
          break;
        case 'FAILED':
        case 'CANCELED':
        case 'EXPIRED':
        case 'ERROR':
          emoji = '❌';
          break;
        default:
          emoji = 'ℹ️';
      }

      final item = event['item'] as Map<String, dynamic>?;
      final txDesc = item != null && item.containsKey('txHash')
          ? " tx: `${(item['txHash'] as String).substring(0, 10)}...`"
          : '';

      final text = "UEX swap status for `${watchAddress.substring(0, 12)}...` → $emoji $status.$txDesc";
      _systemMessagesController.add(ChatMessage.text(text: text, isUser: false));

      // Stop on terminal states
      if (status == 'COMPLETED' || status == 'SUCCESS' || status == 'FILLED' ||
          status == 'FAILED' || status == 'CANCELED' || status == 'EXPIRED') {
        _uexWatchSubscriptions[watchAddress]?.cancel();
        _uexWatchSubscriptions.remove(watchAddress);
      }
    });

    _uexWatchSubscriptions[watchAddress] = sub;

    // Immediate feedback to UI
    _systemMessagesController.add(ChatMessage.text(
      text: "Started watching UEX swap for `${watchAddress.substring(0, 12)}...`.",
      isUser: false,
    ));
  }

  // Main entry point for processing user messages
  Future<ChatMessage> processMessage(String userInput, {String? imageDataUri}) async {
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
          return await _handleGeneralQuery(userInput, imageDataUri: imageDataUri);
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
  Future<String> sendMessage(String userInput, {String? imageDataUri}) async {
    try {
      print('🔍 DEBUG: sendMessage called with: "$userInput"');
      final chatMessage = await processMessage(userInput, imageDataUri: imageDataUri);
      print('🔍 DEBUG: sendMessage returning: "${chatMessage.text}"');
      return chatMessage.text;
    } catch (e) {
      print('🔍 DEBUG: sendMessage error: $e');
      return "Sorry, I encountered an error. Please try again.";
    }
  }

  // Send a message with an attached image (data URI) to T Backend
  Future<String> sendMessageWithImage(String userInput, String imageDataUri) async {
    try {
      final message = (userInput.isEmpty) ? 'Analyze this image' : userInput;
      return await _callTBackend(message, imageDataUri: imageDataUri);
    } catch (e) {
      print('�� DEBUG: sendMessageWithImage error: $e');
      return "Sorry, I couldn't process that image. Please try again.";
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
      final stakeAddr = _cardanoWalletService.stakeAddress;

      BigInt balanceLovelace;
      if (stakeAddr != null && stakeAddr.isNotEmpty) {
        balanceLovelace = await _blockfrostService.getAggregatedAdaForStakeAddress(stakeAddr);
      } else {
        balanceLovelace = await _blockfrostService.getAdaBalance(address);
      }
      final balanceAda = balanceLovelace.toDouble() / 1000000;

      // Get token balances (prefer stake-aggregated)
      final rawAssets = (stakeAddr != null && stakeAddr.isNotEmpty)
          ? await _blockfrostService.getAggregatedAssetsForStakeAddress(stakeAddr)
          : await _blockfrostService.getAssets(address);

      String response = "Your current balance is **₳${balanceAda.toStringAsFixed(2)}** "
                       "($balanceAda ADA)";
      
      if (rawAssets.isNotEmpty) {
        response += "\n\nYou also have ${rawAssets.length} other token(s):";
        int count = 0;
        for (var asset in rawAssets) {
          if (count >= 5) break;
          final unit = asset['unit'] as String;
          final quantityStr = asset['quantity'] as String;
          Map<String, dynamic> display = {};
          try {
            display = await _blockfrostService.getAssetDisplayInfo(unit);
          } catch (_) {}
          final name = (display['ticker'] as String?) ?? (display['name'] as String?) ?? unit;
          final decimals = (display['decimals'] as int?) ?? 0;
          String humanStr;
          try {
            final human = BigInt.parse(quantityStr).toDouble() / math.pow(10, decimals);
            humanStr = decimals > 0 ? human.toStringAsFixed(decimals.clamp(0, 8)) : human.toStringAsFixed(0);
          } catch (_) {
            humanStr = quantityStr;
          }
          response += "\n• $humanStr $name";
          count++;
        }
        if (rawAssets.length > 5) {
          response += "\n...and ${rawAssets.length - 5} more";
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
                "'Send [amount] ADA to [address/name/handle/email]'",
          isUser: false,
        );
      }
      
      final amount = parsed['amount'] as double;
      String address = parsed['address'] as String;

      // Resolve by email via Smart Wallet
      if (address.contains('@') && !_walletService.validateAddress(address)) {
        try {
          final sw = SmartWalletService();
          final resolved = await sw.getWalletAddressByEmail(address);
          if (resolved != null && resolved.isNotEmpty) {
            address = resolved;
          }
        } catch (_) {}
      }

      // Resolve ADA Handle or contact name if still not an address
      if (!_walletService.validateAddress(address)) {
        try {
          // ADA Handle like $yuti or yuti
          final res = await AddressBookService().resolveIfHandle(address);
          address = res['address'] ?? address;
        } catch (_) {}
      }
      if (!_walletService.validateAddress(address)) {
        try {
          // Contact name match
          final book = AddressBookService();
          await book.initialize();
          final lowered = input.toLowerCase();
          final match = book.entries.firstWhere(
            (e) => lowered.contains(e.name.toLowerCase()),
            orElse: () => AddressBookEntry(
              id: '', name: '', address: '', createdAt: DateTime.now()),
          );
          if (match.address.isNotEmpty) {
            address = match.address;
          }
        } catch (_) {}
      }
      
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
        text: "❌ I couldn't process your send request. Please try again.",
        isUser: false,
      );
    }
  }
  
  Future<ChatMessage> _handleReceiveAddress() async {
    try {
      String? address;

      // Prefer live CardanoWalletService connection
      if (_cardanoWalletService.isConnected && _cardanoWalletService.currentAddress != null) {
        address = _cardanoWalletService.currentAddress!;
      }

      // Fallback to user profile wallet (linked Smart Wallet)
      address ??= AuthService().currentUser?.walletAddress;

      // Fallback to WalletService stored wallet
      address ??= await _walletService.getReceiveAddress();

      if (address.isEmpty) {
        throw Exception('empty');
      }

      return ChatMessage.qrCode(
        text: "You can share this QR or tap below to show and copy your address.",
        address: address,
      );
    } catch (_) {
      try {
        // Last resort: initialize services and retry once
        await _cardanoWalletService.initialize();
        final retry = _cardanoWalletService.currentAddress ?? AuthService().currentUser?.walletAddress;
        if (retry != null && retry.isNotEmpty) {
          return ChatMessage.qrCode(
            text: "You can share this QR or tap below to show and copy your address.",
            address: retry,
          );
        }
      } catch (_) {}
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
    // New behavior: allow watching by deposit/destination address with an optional token
    // Usage examples:
    // "watch addr1... token:ABCDEF..."
    // "swap status addr1... token:ABCDEF..."
    final addressMatch = RegExp(r'(addr1[0-9a-z]+)', caseSensitive: false).firstMatch(input);
    final tokenMatch = RegExp(r'token\s*:\s*([A-Za-z0-9]+)', caseSensitive: false).firstMatch(input);

    if (addressMatch != null && tokenMatch != null) {
      final address = addressMatch.group(1)!;
      final token = tokenMatch.group(1)!;
      startWatchingUexAddress(watchAddress: address, token: token);
      return ChatMessage.text(
        text: "Okay, I'll watch the swap at `${address.substring(0, 12)}...` and keep you posted.",
        isUser: false,
      );
    }

    if (addressMatch != null && tokenMatch == null) {
      return ChatMessage.text(
        text: "Please include the UEX token for histories API, e.g. `token:YOURTOKEN`.",
        isUser: false,
      );
    }

    // Fallback: retain old behavior expecting an order id
    final orderMatch = RegExp(r'([a-f0-9-]{8,})').firstMatch(input.toLowerCase());
    if (orderMatch == null) {
      return ChatMessage.text(
        text: "❌ I couldn't find a deposit address or order ID. Provide `addr1...` and `token:...`, or an order ID.",
        isUser: false,
      );
    }

    final orderId = orderMatch.group(1)!;
    try {
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
        text: "❌ Unable to fetch status for order $orderId.\n\nPlease check the order ID or try again later.\n\n*Error: ${e.toString()}*",
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
  
  Future<ChatMessage> _handleGeneralQuery(String input, {String? imageDataUri}) async {
    try {
      // Forward to T-Backend for AI response
      final response = await _callTBackend(input, imageDataUri: imageDataUri);
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
  
  Future<String> _callTBackend(String message, {String? imageDataUri}) async {
    print('🔍 DEBUG: _callTBackend called with message: "$message"');
    
    // Use serverless proxy on web to avoid CORS and expose no secrets
    final String endpoint = kIsWeb
        ? '/api/t/chat'
        : "${_config.tBackendUrl}/chat";
    final url = kIsWeb ? Uri.parse(endpoint) : Uri.parse(endpoint);
    print('🔍 DEBUG: API URL: $url');
    
    // Load API key from secure storage first; fallback to env/AppConfig
    String apiKey = '';
    try {
      apiKey = await SecureConfig().getTBackendApiKey();
    } catch (_) {
      apiKey = _config.tBackendApiKey;
    }
    
    final headers = {
      'Content-Type': 'application/json',
      // For web via proxy, do not send api-key from browser
      if (!kIsWeb && apiKey.isNotEmpty) 'api-key': apiKey,
    };
    print('🔍 DEBUG: Headers: $headers');
    print('🔍 DEBUG: API Key present: ${(!kIsWeb && apiKey.isNotEmpty)}');
    if (!kIsWeb && apiKey.isNotEmpty) {
      final masked = apiKey.length > 10 ? '${apiKey.substring(0, 10)}...' : 'SET';
      print('🔍 DEBUG: API Key value (masked): $masked');
    } else if (kIsWeb) {
      print('🔍 DEBUG: Using serverless proxy; API key not sent from browser');
    } else {
      print('🔍 DEBUG: API Key value: EMPTY');
    }
    
    // Build wallet context snapshot (best-effort)
    Map<String, dynamic>? walletContext;
    try {
      walletContext = await _getWalletContextSnapshot();
    } catch (e) {
      print('🔍 DEBUG: Failed to build wallet context: $e');
    }

    // Include lightweight contacts list for Agent T
    List<Map<String, String>>? contacts;
    try {
      await _addressBookService.initialize();
      final list = _addressBookService.summarizeForContext(limit: 25);
      contacts = list.isNotEmpty ? list : null;
    } catch (_) {}

    final body = jsonEncode({
      'message': message,
      'session_id': _sessionId,
      if (imageDataUri != null) 'image_data': imageDataUri,
      if (walletContext != null)
        'context': {
          'wallet': walletContext,
          if (contacts != null) 'contacts': contacts,
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

      // Resolve address and stake
      final address = await _walletService.getReceiveAddress();
      final stakeAddr = _cardanoWalletService.stakeAddress;

      // Fetch balances
      BigInt balanceLovelace;
      if (stakeAddr != null && stakeAddr.isNotEmpty) {
        // Use aggregated ADA if available
        balanceLovelace = await _blockfrostService.getAggregatedAdaForStakeAddress(stakeAddr);
      } else {
        balanceLovelace = await _blockfrostService.getAdaBalance(address);
      }
      final balanceAda = balanceLovelace.toDouble() / 1000000.0;

      // Assets: prefer stake-aggregated when stake is known; otherwise address-only
      List<Map<String, dynamic>> rawAssets;
      if (stakeAddr != null && stakeAddr.isNotEmpty) {
        rawAssets = await _blockfrostService.getAggregatedAssetsForStakeAddress(stakeAddr);
      } else {
        rawAssets = await _blockfrostService.getAssets(address);
      }
      // Enrich top assets with display metadata and decimals
      final topAssets = rawAssets.take(20).toList();
      final List<Map<String, dynamic>> summarizedAssets = [];
      for (final asset in topAssets) {
        final unit = asset['unit'] as String;
        final quantityStr = asset['quantity'] as String;
        Map<String, dynamic> display = {};
        try {
          display = await _blockfrostService.getAssetDisplayInfo(unit);
        } catch (_) {}
        final decimals = (display['decimals'] as int?) ?? 0;
        double human = 0.0;
        try {
          human = BigInt.parse(quantityStr).toDouble() / math.pow(10, decimals);
        } catch (_) {}
        summarizedAssets.add({
          'unit': unit,
          'quantity': quantityStr,
          'name': display['name'],
          'ticker': display['ticker'],
          'decimals': decimals,
          'human_readable': human.toStringAsFixed(decimals.clamp(0, 8)),
        });
      }

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
    final lower = input.toLowerCase().trim();
    if (!lower.startsWith('send')) return null;

    // Find amount (e.g., '1 ada' or just '1')
    final amountMatch = RegExp(r'(\d+(?:\.\d+)?)\s*ada?', caseSensitive: false)
        .firstMatch(lower);
    if (amountMatch == null) return null;
    final amount = double.tryParse(amountMatch.group(1)!);
    if (amount == null) return null;

    // Preferred recipient after 'to'
    String? recipient;
    final toMatch = RegExp(r'\bto\b\s+(.+)$', caseSensitive: false)
        .firstMatch(lower);
    if (toMatch != null) {
      recipient = toMatch.group(1)!.trim();
    }

    // If no explicit 'to', try common patterns: address/handle/email/name anywhere
    recipient ??= _firstRecipientCandidate(lower);
    if (recipient == null || recipient.isEmpty) return null;

    return {
      'amount': amount,
      'address': recipient,
    };
  }

  String? _firstRecipientCandidate(String text) {
    // Cardano address
    final addr = RegExp(r'(addr1[0-9a-z]+|addr_test1[0-9a-z]+)', caseSensitive: false)
        .firstMatch(text);
    if (addr != null) return addr.group(1);
    // ADA Handle like $name or name starting with $
    final handle = RegExp(r'(\$[a-z0-9_]+)', caseSensitive: false).firstMatch(text);
    if (handle != null) return handle.group(1);
    // Email (for Smart Wallet)
    final email = RegExp(r'[\w.+-]+@[\w.-]+', caseSensitive: false).firstMatch(text);
    if (email != null) return email.group(0);
    // Otherwise, return the word after 'send' if present (could be a contact name)
    final afterSend = RegExp(r'^send\s+([^\s]+)').firstMatch(text);
    if (afterSend != null) return afterSend.group(1);
    return null;
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