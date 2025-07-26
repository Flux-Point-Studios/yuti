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
  
  // Session management
  late final String _sessionId;
  SwapRequest? _pendingSwapRequest;
  
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
      
      // Check if we're waiting for additional swap information
      if (_pendingSwapRequest != null) {
        return await _handlePendingSwapInput(userInput);
      }
      
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
  
  // Enhanced swap command handling with intelligent parsing
  Future<ChatMessage> _handleSwapCommand(String input) async {
    try {
      print('🔍 DEBUG: Processing swap command: "$input"');
      
      // Extract entities from natural language input
      final entities = _extractSwapEntities(input);
      print('🔍 DEBUG: Extracted entities: amount=${entities.amount}, from=${entities.fromCurrency}, to=${entities.toCurrency}, confidence=${entities.confidence}');
      
      // Create swap request from extracted entities
      final swap = SwapRequest(platform: entities.platform ?? SwapPlatform.auto);
      swap.amount = entities.amount;
      swap.fromCurrency = entities.fromCurrency;
      swap.toCurrency = entities.toCurrency;
      swap.toAddress = entities.address;
      
      // If we couldn't extract enough information, ask for clarification
      if (entities.confidence < 0.6 || swap.amount == null || swap.fromCurrency == null || swap.toCurrency == null) {
        return await _askForSwapClarification(swap, input);
      }
      
      // Normalize currencies
      swap.fromCurrency = _normalizeCurrency(swap.fromCurrency!);
      swap.toCurrency = _normalizeCurrency(swap.toCurrency!);
      
      // Check if we need to choose platform (Cardano-only vs cross-chain)
      if (swap.needsPlatformChoice) {
        _pendingSwapRequest = swap;
        return _askForPlatformChoice(swap);
      }
      
      // Determine platform automatically if cross-chain
      if (swap.isCrossChain) {
        swap.platform = SwapPlatform.uex;
      } else {
        swap.platform = SwapPlatform.saturnSwap;
      }
      
      // Check if we need destination address
      if (swap.toCurrency != 'ADA' && swap.toAddress == null) {
        _pendingSwapRequest = swap;
        swap.awaitingAddressFor = swap.toCurrency;
        
        return ChatMessage.text(
          text: "Great! I'll help you swap **${swap.amount} ${swap.fromCurrency}** to **${swap.toCurrency}**.\n\n"
                "What is your **${swap.toCurrency}** wallet address to receive the ${swap.toCurrency}?",
          isUser: false,
        );
      }
      
      // If swapping to ADA, use our wallet address
      if (swap.toCurrency == 'ADA') {
        swap.toAddress = await _walletService.getReceiveAddress();
      }
      
      // Create swap order
      return await _createSwapOrder(swap);
    } catch (e) {
      print('🔍 DEBUG: Error in _handleSwapCommand: $e');
      return ChatMessage.text(
        text: "❌ Failed to process swap: ${e.toString()}",
        isUser: false,
      );
    }
  }
  
  // Enhanced entity extraction with pattern matching and context
  ExtractedEntities _extractSwapEntities(String input) {
    final lower = input.toLowerCase();
    String? amount;
    String? fromCurrency;
    String? toCurrency;
    SwapPlatform? platform;
    double confidence = 0.0;
    
    // Platform detection
    if (lower.contains('saturn')) {
      platform = SwapPlatform.saturnSwap;
      confidence += 0.2;
    } else if (lower.contains('uex') || lower.contains('cross') || lower.contains('bridge')) {
      platform = SwapPlatform.uex;
      confidence += 0.2;
    }
    
    // Enhanced amount extraction
    final amountPatterns = [
      r'(\d+\.?\d*)\s*([a-zA-Z]+)',  // "1.5 ETH"
      r'(\d+\.?\d*)',  // Just number
      r'all\s+my\s+([a-zA-Z]+)',  // "all my ADA"
      r'everything',  // "everything"
    ];
    
    for (final pattern in amountPatterns) {
      final regex = RegExp(pattern, caseSensitive: false);
      final match = regex.firstMatch(input);
      if (match != null) {
        if (pattern.contains('all') || pattern.contains('everything')) {
          amount = 'max';
          if (match.groupCount > 0) {
            fromCurrency = match.group(1);
          }
        } else {
          amount = match.group(1);
          if (match.groupCount > 1) {
            fromCurrency = match.group(2);
          }
        }
        confidence += 0.3;
        break;
      }
    }
    
    // Enhanced currency extraction with multiple patterns
    final currencyPatterns = [
      r'swap\s+(\d+\.?\d*\s+)?([a-zA-Z]+)\s+(?:to|for|into)\s+([a-zA-Z]+)',  // "swap 1 ETH to BTC"
      r'(\d+\.?\d*\s+)?([a-zA-Z]+)\s+(?:to|for|into)\s+([a-zA-Z]+)',  // "1 ETH to BTC"
      r'exchange\s+(\d+\.?\d*\s+)?([a-zA-Z]+)\s+(?:to|for|into)\s+([a-zA-Z]+)',  // "exchange ETH for BTC"
      r'convert\s+(\d+\.?\d*\s+)?([a-zA-Z]+)\s+(?:to|for|into)\s+([a-zA-Z]+)',  // "convert ETH to BTC"
      r'trade\s+(\d+\.?\d*\s+)?([a-zA-Z]+)\s+(?:to|for|into)\s+([a-zA-Z]+)',  // "trade ETH for BTC"
      r'sell\s+(\d+\.?\d*\s+)?([a-zA-Z]+)\s+(?:for|to)\s+([a-zA-Z]+)',  // "sell ETH for BTC"
      r'buy\s+(\d+\.?\d*\s+)?([a-zA-Z]+)\s+(?:with|using)\s+([a-zA-Z]+)',  // "buy BTC with ETH"
      r'get\s+(\d+\.?\d*\s+)?([a-zA-Z]+)\s+(?:with|using|for)\s+([a-zA-Z]+)',  // "get BTC with ETH"
      r'(?:from|using)\s+([a-zA-Z]+)\s+(?:to|for|into)\s+([a-zA-Z]+)',  // "from ETH to BTC"
    ];
    
    for (final pattern in currencyPatterns) {
      final regex = RegExp(pattern, caseSensitive: false);
      final match = regex.firstMatch(input);
      if (match != null) {
        if (pattern.contains('buy') || pattern.contains('get')) {
          // For "buy BTC with ETH" pattern, currencies are swapped
          if (match.groupCount >= 3) {
            fromCurrency = match.group(3);  // ETH
            toCurrency = match.group(2);    // BTC
            if (match.group(1) != null && amount == null) {
              amount = match.group(1)?.trim().split(' ').first;
            }
          }
        } else {
          // Standard "sell/swap ETH for BTC" pattern
          if (match.groupCount >= 3) {
            fromCurrency = match.group(2);  // ETH
            toCurrency = match.group(3);    // BTC
            if (match.group(1) != null && amount == null) {
              amount = match.group(1)?.trim().split(' ').first;
            }
          } else if (match.groupCount >= 2) {
            fromCurrency = match.group(1);
            toCurrency = match.group(2);
          }
        }
        confidence += 0.4;
        break;
      }
    }
    
    // Validate and normalize extracted data
    if (fromCurrency != null) {
      fromCurrency = _normalizeCurrency(fromCurrency);
      confidence += 0.1;
    }
    
    if (toCurrency != null) {
      toCurrency = _normalizeCurrency(toCurrency);
      confidence += 0.1;
    }
    
    if (amount != null && amount != 'max') {
      if (double.tryParse(amount) != null) {
        confidence += 0.1;
      } else {
        amount = null;  // Invalid amount
        confidence -= 0.2;
      }
    }
    
    print('🔍 DEBUG: Entity extraction - amount: $amount, from: $fromCurrency, to: $toCurrency, confidence: $confidence');
    
    return ExtractedEntities(
      amount: amount,
      fromCurrency: fromCurrency,
      toCurrency: toCurrency,
      platform: platform,
      confidence: confidence,
    );
  }
  
  Future<ChatMessage> _askForSwapClarification(SwapRequest partialSwap, String originalInput) async {
    String clarificationText = "I'd like to help you with that swap! ";
    
    List<String> missingInfo = [];
    
    if (partialSwap.amount == null) {
      missingInfo.add("the amount");
    }
    
    if (partialSwap.fromCurrency == null) {
      missingInfo.add("which currency you want to swap from");
    }
    
    if (partialSwap.toCurrency == null) {
      missingInfo.add("which currency you want to swap to");
    }
    
    if (missingInfo.isNotEmpty) {
      clarificationText += "I need to know ${missingInfo.join(' and ')}.\n\n";
      clarificationText += "Please tell me in a format like:\n";
      clarificationText += "• \"Swap 1 ETH to BTC\"\n";
      clarificationText += "• \"Exchange 100 ADA for USDT\"\n";
      clarificationText += "• \"Convert 0.5 BTC to ETH\"";
    } else {
      clarificationText += "I understood you want to swap, but could you clarify the details?\n\n";
      clarificationText += "For example: \"Swap 1 ETH to BTC\"";
    }
    
    return ChatMessage.text(text: clarificationText, isUser: false);
  }
  
  ChatMessage _askForPlatformChoice(SwapRequest swap) {
    return ChatMessage.text(
      text: "Perfect! I can help you swap **${swap.amount} ${swap.fromCurrency}** to **${swap.toCurrency}**.\n\n"
            "Since both currencies are on Cardano, you have two options:\n\n"
            "🔹 **SaturnSwap** - Cardano native DEX (lower fees, faster)\n"
            "🔹 **UEX** - Cross-chain DEX (more liquidity options)\n\n"
            "Which would you prefer? You can say \"Saturn\" or \"UEX\", or I can choose the best option for you.",
      isUser: false,
    );
  }
  
  Future<ChatMessage> _handlePendingSwapInput(String input) async {
    final lower = input.toLowerCase();
    
    // Handle platform choice
    if (_pendingSwapRequest!.needsPlatformChoice) {
      if (lower.contains('saturn')) {
        _pendingSwapRequest!.platform = SwapPlatform.saturnSwap;
      } else if (lower.contains('uex')) {
        _pendingSwapRequest!.platform = SwapPlatform.uex;
      } else if (lower.contains('best') || lower.contains('choose') || lower.contains('auto')) {
        _pendingSwapRequest!.platform = SwapPlatform.saturnSwap; // Default to Saturn for Cardano pairs
      } else {
        return ChatMessage.text(
          text: "Please choose either **SaturnSwap** or **UEX**, or say \"choose for me\" and I'll pick the best option.",
          isUser: false,
        );
      }
      
      // Check if we need destination address
      if (_pendingSwapRequest!.toCurrency != 'ADA' && _pendingSwapRequest!.toAddress == null) {
        _pendingSwapRequest!.awaitingAddressFor = _pendingSwapRequest!.toCurrency;
        
        return ChatMessage.text(
          text: "Great choice! Now what is your **${_pendingSwapRequest!.toCurrency}** wallet address to receive the ${_pendingSwapRequest!.toCurrency}?",
          isUser: false,
        );
      }
      
      // If swapping to ADA, use our wallet address
      if (_pendingSwapRequest!.toCurrency == 'ADA') {
        _pendingSwapRequest!.toAddress = await _walletService.getReceiveAddress();
      }
      
      final result = await _createSwapOrder(_pendingSwapRequest!);
      _pendingSwapRequest = null;
      return result;
    }
    
    // Handle address input
    if (_pendingSwapRequest!.awaitingAddressFor != null) {
      return await _handleSwapAddressInput(input);
    }
    
    // Try to parse as additional swap information
    final entities = _extractSwapEntities(input);
    
    if (entities.confidence > 0.5) {
      // Update pending request with new information
      _pendingSwapRequest!.amount ??= entities.amount;
      _pendingSwapRequest!.fromCurrency ??= entities.fromCurrency;
      _pendingSwapRequest!.toCurrency ??= entities.toCurrency;
      
      if (_pendingSwapRequest!.isComplete) {
        final result = await _createSwapOrder(_pendingSwapRequest!);
        _pendingSwapRequest = null;
        return result;
      }
    }
    
    return await _askForSwapClarification(_pendingSwapRequest!, input);
  }
  
  Future<ChatMessage> _handleSwapAddressInput(String input) async {
    final address = input.trim();
    
    // TODO: Validate address based on currency type
    // For now, basic validation
    if (address.length < 20) {
      return ChatMessage.text(
        text: "❌ That doesn't look like a valid ${_pendingSwapRequest!.awaitingAddressFor} address. "
              "Please double-check and try again.",
        isUser: false,
      );
    }
    
    _pendingSwapRequest!.toAddress = address;
    _pendingSwapRequest!.awaitingAddressFor = null;
    
    final result = await _createSwapOrder(_pendingSwapRequest!);
    _pendingSwapRequest = null;
    
    return result;
  }
  
  Future<ChatMessage> _createSwapOrder(SwapRequest swap) async {
    try {
      String platformName = swap.platform == SwapPlatform.saturnSwap ? "SaturnSwap" : "UEX";
      print('🔍 DEBUG: Creating swap order on $platformName: ${swap.amount} ${swap.fromCurrency} -> ${swap.toCurrency}');
      
      if (swap.platform == SwapPlatform.saturnSwap) {
        return await _createSaturnSwapOrder(swap);
      } else {
        return await _createUEXSwapOrder(swap);
      }
    } catch (e) {
      print('🔍 DEBUG: Error creating swap order: $e');
      return ChatMessage.text(
        text: "❌ **Swap Service Error**\n\n"
              "I encountered an issue creating your swap order:\n"
              "${e.toString()}\n\n"
              "Please try again in a moment or contact support if the issue persists.",
        isUser: false,
      );
    }
  }
  
  Future<ChatMessage> _createSaturnSwapOrder(SwapRequest swap) async {
    try {
      // Get real quote from SaturnSwap
      final quote = await _saturnSwapService.getSwapQuote(
        fromToken: swap.fromCurrency!,
        toToken: swap.toCurrency!,
        amount: swap.amount!,
        isFromAmount: true,
      );
      
      // Create the swap transaction
      final swapTx = await _saturnSwapService.createSwapTransaction(
        fromToken: swap.fromCurrency!,
        toToken: swap.toCurrency!,
        fromAmount: swap.amount!,
        toAmount: quote.toAmount,
        userAddress: swap.toAddress!,
        slippageTolerance: 0.5, // 0.5% slippage
      );
      
      final orderId = swapTx['order_id'] ?? const Uuid().v4().substring(0, 8);
      
      return ChatMessage.swap(
        text: "✅ **SaturnSwap Order Created Successfully!**\n\n"
              "**Order ID:** `$orderId`\n"
              "**Platform:** 🪐 SaturnSwap (Cardano DEX)\n\n"
              "**Swap Details:**\n"
              "📤 **Send:** ${swap.amount} ${swap.fromCurrency}\n"
              "📥 **Receive:** ~${quote.toAmount} ${swap.toCurrency}\n"
              "📍 **To Address:** `${swap.toAddress?.substring(0, 10)}...`\n"
              "💱 **Rate:** 1 ${swap.fromCurrency} = ${quote.exchangeRate.toStringAsFixed(6)} ${swap.toCurrency}\n"
              "📊 **Price Impact:** ${(quote.priceImpact * 100).toStringAsFixed(2)}%\n"
              "⚡ **Network:** Cardano\n"
              "💰 **Platform Fee:** ${quote.fee.toStringAsFixed(6)} ${swap.fromCurrency}\n"
              "⏰ **Status:** ready_to_execute\n"
              "⏳ **Quote Expires:** ${_formatTime(quote.expiresAt)}\n\n"
              "💡 **Next Steps:**\n"
              "1. Confirm the transaction in your wallet\n"
              "2. Wait for network confirmation (~20 seconds)\n"
              "3. Your ${swap.toCurrency} will be delivered automatically\n\n"
              "*(Ask me \"What's the status of order $orderId?\" for updates)*\n\n"
              "⚠️ **Note:** SaturnSwap integration includes simulated data for demo purposes.",
        orderId: orderId,
        fromAmount: swap.amount!,
        fromCurrency: swap.fromCurrency!,
        toAmount: quote.toAmount,
        toCurrency: swap.toCurrency!,
        depositAddress: await _walletService.getReceiveAddress(),
      );
    } catch (e) {
      // Fallback to simulated response if SaturnSwap service fails
      return ChatMessage.text(
        text: "❌ **SaturnSwap Service Temporarily Unavailable**\n\n"
              "I'm having trouble connecting to the SaturnSwap service right now. "
              "This could be due to:\n"
              "• Network connectivity issues\n"
              "• Service maintenance\n"
              "• Invalid token pair\n\n"
              "For cross-chain swaps, you can try using UEX instead by saying:\n"
              "\"Swap ${swap.amount} ${swap.fromCurrency} to ${swap.toCurrency} on UEX\"\n\n"
              "*Error details: ${e.toString()}*",
        isUser: false,
      );
    }
  }
  
  Future<ChatMessage> _createUEXSwapOrder(SwapRequest swap) async {
    try {
      // Get real quote from UEX
      final quote = await _uexService.getSwapQuote(
        fromToken: swap.fromCurrency!,
        toToken: swap.toCurrency!,
        amount: swap.amount!,
        isFromAmount: true,
      );
      
      // Create the swap transaction
      final swapTx = await _uexService.createSwapTransaction(
        fromToken: swap.fromCurrency!,
        toToken: swap.toCurrency!,
        fromAmount: swap.amount!,
        toAmount: quote.toAmount,
        userAddress: swap.toAddress!,
        slippageTolerance: 0.5, // 0.5% slippage
      );
      
      final orderId = swapTx['order_id'] ?? const Uuid().v4().substring(0, 8);
      final depositAddress = swapTx['deposit_address'] ?? 'Error: No deposit address';
      
      return ChatMessage.swap(
        text: "✅ **UEX Cross-Chain Swap Created Successfully!**\n\n"
              "**Order ID:** `$orderId`\n"
              "**Platform:** 🌐 UEX (Cross-Chain DEX)\n\n"
              "**Instructions:**\n"
              "📤 **Send:** ${swap.amount} ${swap.fromCurrency}\n"
              "📍 **To Address:** `$depositAddress`\n\n"
              "📥 **You'll Receive:** ~${quote.toAmount} ${swap.toCurrency}\n"
              "📍 **To Your Address:** `${swap.toAddress?.substring(0, 10)}...`\n"
              "💱 **Rate:** 1 ${swap.fromCurrency} = ${quote.exchangeRate.toStringAsFixed(6)} ${swap.toCurrency}\n"
              "📊 **Price Impact:** ${(quote.priceImpact * 100).toStringAsFixed(2)}%\n"
              "💰 **Fee:** ${quote.fee.toStringAsFixed(6)} ${swap.fromCurrency}\n"
              "⏰ **Status:** waiting_for_deposit\n"
              "⏳ **Quote Expires:** ${_formatTime(quote.expiresAt)}\n\n"
              "💡 **Next Steps:**\n"
              "1. Send the exact amount to the deposit address above\n"
              "2. Wait for network confirmations\n"
              "3. Your ${swap.toCurrency} will be delivered automatically\n\n"
              "*(You can ask me \"What's the status of order $orderId?\" anytime)*",
        orderId: orderId,
        fromAmount: swap.amount!,
        fromCurrency: swap.fromCurrency!,
        toAmount: quote.toAmount,
        toCurrency: swap.toCurrency!,
        depositAddress: depositAddress,
      );
    } catch (e) {
      // Fallback to simulated response if UEX service fails
      return ChatMessage.text(
        text: "❌ **UEX Service Temporarily Unavailable**\n\n"
              "I'm having trouble connecting to the UEX service right now. "
              "This could be due to:\n"
              "• Network connectivity issues\n"
              "• Service maintenance\n"
              "• Invalid token pair\n\n"
              "For Cardano-to-Cardano swaps, you can try using SaturnSwap instead by saying:\n"
              "\"Swap ${swap.amount} ${swap.fromCurrency} to ${swap.toCurrency} on Saturn\"\n\n"
              "*Error details: ${e.toString()}*",
        isUser: false,
      );
    }
  }
  
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
    
    final body = jsonEncode({
      'message': message,
      'session_id': _sessionId,
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