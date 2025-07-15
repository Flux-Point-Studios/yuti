import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../models/chat_message.dart';
import '../config/app_config.dart';
import 'wallet_service.dart';
import 'blockfrost_service.dart';
import 'transaction_service.dart';
import 'uex_service.dart';

enum ChatIntent {
  balance,
  send,
  receive,
  swap,
  swapStatus,
  transaction,
  general,
}

class SwapRequest {
  String? amount;
  String? fromCurrency;
  String? toCurrency;
  String? toAddress;
  String? awaitingAddressFor;
  
  bool get isComplete => 
      amount != null && 
      fromCurrency != null && 
      toCurrency != null &&
      (toCurrency == 'ADA' || toAddress != null);
}

class ChatService {
  final AppConfig _config = AppConfig();
  final WalletService _walletService = WalletService();
  final BlockfrostService _blockfrostService = BlockfrostService();
  final UEXService _uexService = UEXService();
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
  
  Future<ChatMessage> processMessage(String userInput) async {
    try {
      // Check if we're in the middle of a multi-turn conversation
      if (_pendingSwapRequest != null && _pendingSwapRequest!.awaitingAddressFor != null) {
        return _handleSwapAddressInput(userInput);
      }
      
      // Detect intent
      final intent = _detectIntent(userInput);
      
      switch (intent) {
        case ChatIntent.balance:
          return _handleBalanceQuery();
        case ChatIntent.send:
          return _handleSendCommand(userInput);
        case ChatIntent.receive:
          return _handleReceiveAddress();
        case ChatIntent.swap:
          return _handleSwapCommand(userInput);
        case ChatIntent.swapStatus:
          return _handleSwapStatus(userInput);
        case ChatIntent.transaction:
          return _handleTransactionQuery(userInput);
        case ChatIntent.general:
          return _handleGeneralQuery(userInput);
      }
    } catch (e) {
      return ChatMessage.text(
        text: "❌ I encountered an error: ${e.toString()}",
        isUser: false,
      );
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
    
    // Swap commands
    if (lower.contains('swap') || 
        lower.contains('exchange') ||
        lower.contains('convert')) {
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
  
  Future<ChatMessage> _handleSwapCommand(String input) async {
    try {
      final swap = _parseSwapCommand(input);
      if (swap == null) {
        return ChatMessage.text(
          text: "❌ I didn't understand that swap command. Please use the format: "
                "'Swap [amount] [from currency] to [to currency]'",
          isUser: false,
        );
      }
      
      // Normalize currencies
      swap.fromCurrency = _normalizeCurrency(swap.fromCurrency!);
      swap.toCurrency = _normalizeCurrency(swap.toCurrency!);
      
      // Check if we need additional information
      if (swap.toCurrency != 'ADA' && swap.toAddress == null) {
        _pendingSwapRequest = swap;
        swap.awaitingAddressFor = swap.toCurrency;
        
        return ChatMessage.text(
          text: "Sure! I can help with that. What is your **${swap.toCurrency}** "
                "wallet address to receive the ${swap.toCurrency}?",
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
      return ChatMessage.text(
        text: "❌ Failed to process swap: ${e.toString()}",
        isUser: false,
      );
    }
  }
  
  Future<ChatMessage> _handleSwapAddressInput(String input) async {
    final address = input.trim();
    
    // TODO: Validate address based on currency type
    // For now, basic validation
    if (address.length < 20) {
      return ChatMessage.text(
        text: "❌ That doesn't look like a valid ${_pendingSwapRequest!.awaitingAddressFor} address. "
              "Please double-check.",
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
        text: "✅ **Swap Order Created Successfully!**\n\n"
              "**Order ID:** `$orderId`\n\n"
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
        text: "❌ **Swap Service Temporarily Unavailable**\n\n"
              "I'm having trouble connecting to the swap service right now. "
              "This could be due to:\n"
              "• Network connectivity issues\n"
              "• Service maintenance\n"
              "• Invalid token pair\n\n"
              "Please try again in a few moments, or check if ${swap.fromCurrency} to ${swap.toCurrency} "
              "is a supported trading pair.\n\n"
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
    final url = Uri.parse("${_config.tBackendUrl}/chat");
    final headers = {
      'Content-Type': 'application/json',
      if (_config.tBackendApiKey.isNotEmpty) 'api-key': _config.tBackendApiKey,
    };
    final body = jsonEncode({
      'message': message,
      'session_id': _sessionId,
    });
    
    final response = await http.post(url, headers: headers, body: body);
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['reply'] ?? "I'm not sure how to respond to that.";
    } else {
      throw Exception('T-Backend error: ${response.statusCode}');
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
  
  SwapRequest? _parseSwapCommand(String input) {
    // Try to parse "swap X FROM to TO"
    final regex = RegExp(
      r'(\d+\.?\d*)\s*([a-zA-Z]+)\s*(to|for)\s*([a-zA-Z]+)',
      caseSensitive: false,
    );
    
    final match = regex.firstMatch(input);
    if (match == null) return null;
    
    final swap = SwapRequest();
    swap.amount = match.group(1)!;
    swap.fromCurrency = match.group(2)!;
    swap.toCurrency = match.group(4)!;
    
    return swap;
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