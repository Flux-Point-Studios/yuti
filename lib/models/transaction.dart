class Transaction {
  final String id;
  final String type; // 'send', 'receive', 'swap'
  final String? fromAddress;
  final String? toAddress;
  final double amount;
  final String asset; // 'ADA' or token name
  final String? tokenPolicyId;
  final double fee;
  final String status; // 'pending', 'confirmed', 'failed'
  final DateTime timestamp;
  final String? txHash;
  final String? description;

  Transaction({
    required this.id,
    required this.type,
    this.fromAddress,
    this.toAddress,
    required this.amount,
    required this.asset,
    this.tokenPolicyId,
    required this.fee,
    required this.status,
    required this.timestamp,
    this.txHash,
    this.description,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'fromAddress': fromAddress,
      'toAddress': toAddress,
      'amount': amount,
      'asset': asset,
      'tokenPolicyId': tokenPolicyId,
      'fee': fee,
      'status': status,
      'timestamp': timestamp.toIso8601String(),
      'txHash': txHash,
      'description': description,
    };
  }

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'],
      type: json['type'],
      fromAddress: json['fromAddress'],
      toAddress: json['toAddress'],
      amount: json['amount'],
      asset: json['asset'],
      tokenPolicyId: json['tokenPolicyId'],
      fee: json['fee'],
      status: json['status'],
      timestamp: DateTime.parse(json['timestamp']),
      txHash: json['txHash'],
      description: json['description'],
    );
  }

  bool get isIncoming => type == 'receive';
  bool get isOutgoing => type == 'send' || type == 'swap';
  bool get isPending => status == 'pending';
  bool get isConfirmed => status == 'confirmed';
  bool get isFailed => status == 'failed';
}