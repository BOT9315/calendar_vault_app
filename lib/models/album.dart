class Album {
  final String id;
  String name;
  final DateTime createdAt;
  String? coverItemId;

  Album({
    required this.id,
    required this.name,
    required this.createdAt,
    this.coverItemId,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'createdAt': createdAt.toIso8601String(),
      'coverItemId': coverItemId,
    };
  }

  factory Album.fromJson(Map<String, dynamic> json) {
    return Album(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      coverItemId: json['coverItemId'] as String?,
    );
  }

  Album copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    String? coverItemId,
  }) {
    return Album(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      coverItemId: coverItemId ?? this.coverItemId,
    );
  }
}
