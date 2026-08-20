class ContestPrize {
  final String id;
  final int rank; // 1, 2, 3, 4, etc.
  final String? amount; // e.g., "$200", "$100", or null for recognition prizes
  final String type; // 'gold', 'silver', 'bronze', 'recognition', 'custom'
  final String description; // e.g., "Cash prize", "Certificate", "Gift card"
  
  ContestPrize({
    required this.id,
    required this.rank,
    this.amount,
    required this.type,
    required this.description,
  });
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'rank': rank,
      'amount': amount,
      'type': type,
      'description': description,
    };
  }
  
  factory ContestPrize.fromMap(Map<String, dynamic> map) {
    return ContestPrize(
      id: map['id'] ?? '',
      rank: map['rank'] ?? 1,
      amount: map['amount'],
      type: map['type'] ?? 'custom',
      description: map['description'] ?? '',
    );
  }
  
  ContestPrize copyWith({
    String? id,
    int? rank,
    String? amount,
    String? type,
    String? description,
  }) {
    return ContestPrize(
      id: id ?? this.id,
      rank: rank ?? this.rank,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      description: description ?? this.description,
    );
  }
  
  // Helper to get display type name
  String get displayName {
    switch (type.toLowerCase()) {
      case 'gold':
        return 'Gold Prize';
      case 'silver':
        return 'Silver Prize';
      case 'bronze':
        return 'Bronze Prize';
      case 'recognition':
        return 'Recognition Prize';
      default:
        return description;
    }
  }
  
  // Helper to get rank suffix
  String get rankSuffix {
    if (rank >= 11 && rank <= 13) return 'th';
    switch (rank % 10) {
      case 1: return 'st';
      case 2: return 'nd';
      case 3: return 'rd';
      default: return 'th';
    }
  }
  
  // Helper to get full rank display
  String get rankDisplay => '${rank}${rankSuffix}';
}
