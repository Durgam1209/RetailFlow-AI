class FruitItem {
  const FruitItem({
    required this.id,
    required this.name,
    required this.icon,
    required this.defaultPrice,
    required this.defaultIncrement,
  });

  final String id;
  final String name;
  final String icon;
  final double defaultPrice;
  final double defaultIncrement;

  factory FruitItem.fromMap(Map<String, dynamic> map) {
    return FruitItem(
      id: map['id'] as String,
      name: map['name'] as String,
      icon: map['icon'] as String,
      defaultPrice: (map['defaultPrice'] as num).toDouble(),
      defaultIncrement: (map['defaultIncrement'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'icon': icon,
      'defaultPrice': defaultPrice,
      'defaultIncrement': defaultIncrement,
    };
  }
}
