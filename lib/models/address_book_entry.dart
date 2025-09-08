class AddressBookEntry {
  final String id;
  final String name;
  final String address;
  final String? handle;
  final String? description;
  final DateTime createdAt;
  final DateTime? lastUsed;

  AddressBookEntry({
    required this.id,
    required this.name,
    required this.address,
    this.handle,
    this.description,
    required this.createdAt,
    this.lastUsed,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'handle': handle,
      'description': description,
      'createdAt': createdAt.toIso8601String(),
      'lastUsed': lastUsed?.toIso8601String(),
    };
  }

  factory AddressBookEntry.fromJson(Map<String, dynamic> json) {
    return AddressBookEntry(
      id: json['id'],
      name: json['name'],
      address: json['address'],
      handle: json['handle'],
      description: json['description'],
      createdAt: DateTime.parse(json['createdAt']),
      lastUsed: json['lastUsed'] != null ? DateTime.parse(json['lastUsed']) : null,
    );
  }

  AddressBookEntry copyWith({
    String? id,
    String? name,
    String? address,
    String? handle,
    String? description,
    DateTime? createdAt,
    DateTime? lastUsed,
  }) {
    return AddressBookEntry(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      handle: handle ?? this.handle,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }
}