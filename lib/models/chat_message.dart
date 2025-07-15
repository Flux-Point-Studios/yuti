import 'package:uuid/uuid.dart';

enum MessageType { text, image, transaction, swap, qrCode }

class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final MessageType type;
  final Map<String, dynamic>? metadata;

  ChatMessage({
    String? id,
    required this.text,
    required this.isUser,
    DateTime? timestamp,
    this.type = MessageType.text,
    this.metadata,
  }) : id = id ?? const Uuid().v4(),
       timestamp = timestamp ?? DateTime.now();

  // Factory constructors for different message types
  factory ChatMessage.text({required String text, required bool isUser}) {
    return ChatMessage(text: text, isUser: isUser, type: MessageType.text);
  }

  factory ChatMessage.transaction({
    required String text,
    required String txHash,
    required String amount,
    required String recipient,
    bool isUser = false,
  }) {
    return ChatMessage(
      text: text,
      isUser: isUser,
      type: MessageType.transaction,
      metadata: {'txHash': txHash, 'amount': amount, 'recipient': recipient},
    );
  }

  factory ChatMessage.swap({
    required String text,
    required String orderId,
    required String fromAmount,
    required String fromCurrency,
    required String toAmount,
    required String toCurrency,
    String? depositAddress,
    bool isUser = false,
  }) {
    return ChatMessage(
      text: text,
      isUser: isUser,
      type: MessageType.swap,
      metadata: {
        'orderId': orderId,
        'fromAmount': fromAmount,
        'fromCurrency': fromCurrency,
        'toAmount': toAmount,
        'toCurrency': toCurrency,
        if (depositAddress != null) 'depositAddress': depositAddress,
      },
    );
  }

  factory ChatMessage.qrCode({
    required String text,
    required String address,
    bool isUser = false,
  }) {
    return ChatMessage(
      text: text,
      isUser: isUser,
      type: MessageType.qrCode,
      metadata: {'address': address},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'isUser': isUser,
      'timestamp': timestamp.toIso8601String(),
      'type': type.toString(),
      'metadata': metadata,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'],
      text: json['text'],
      isUser: json['isUser'],
      timestamp: DateTime.parse(json['timestamp']),
      type: MessageType.values.firstWhere(
        (e) => e.toString() == json['type'],
        orElse: () => MessageType.text,
      ),
      metadata: json['metadata'] != null
          ? Map<String, dynamic>.from(json['metadata'])
          : null,
    );
  }
}
