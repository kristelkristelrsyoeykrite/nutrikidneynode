part of '../food_log.dart';

class FoodItem {
  final String? id;
  final String? foodId;
  final String? servingId;
  final String emoji;
  final String name;
  final String portion;
  final double quantity;
  final int calories;
  final String time;
  final double protein;
  final double carbohydrate;
  final double fat;
  final double sodium;
  final double potassium;
  final double phosphorus;
  final String source;
  final bool needsManualReview;
  final Map<String, dynamic>? raw;

  FoodItem({
    this.id,
    this.foodId,
    this.servingId,
    required this.emoji,
    required this.name,
    required this.portion,
    this.quantity = 1,
    required this.calories,
    required this.time,
    this.protein = 0,
    this.carbohydrate = 0,
    this.fat = 0,
    this.sodium = 0,
    this.potassium = 0,
    this.phosphorus = 0,
    this.source = 'manual_entry',
    this.needsManualReview = false,
    this.raw,
  });

  factory FoodItem.fromLog(Map<String, dynamic> data) {
    final nutrients = data['finalNutrients'] is Map
        ? Map<String, dynamic>.from(data['finalNutrients'] as Map)
        : data['final_nutrients'] is Map
            ? Map<String, dynamic>.from(data['final_nutrients'] as Map)
            : const <String, dynamic>{};
    return FoodItem(
      id: data['id']?.toString(),
      foodId: data['foodId']?.toString(),
      servingId: (data['servingId'] ?? data['selectedServingId'])?.toString(),
      emoji: '\u{1F37D}\u{FE0F}',
      name: data['name']?.toString() ?? 'Food',
      portion: data['portion']?.toString() ?? '1 serving',
      quantity: _asDouble(data['quantity'] ?? data['selectedQuantity'] ?? 1),
      calories: _asInt(data['calories'] ?? nutrients['calories']),
      time: _formatDisplayTime(data['createdAt']),
      protein: _asDouble(data['protein'] ?? nutrients['protein']),
      carbohydrate:
          _asDouble(data['carbohydrate'] ?? nutrients['carbohydrate']),
      fat: _asDouble(data['fat'] ?? nutrients['fat']),
      sodium: _asDouble(data['sodium'] ?? nutrients['sodium']),
      potassium: _asDouble(data['potassium'] ?? nutrients['potassium']),
      phosphorus: _asDouble(data['phosphorus'] ?? nutrients['phosphorus']),
      source: data['source']?.toString() ?? 'manual_entry',
      needsManualReview: data['needsManualReview'] == true,
      raw: data['raw'] is Map
          ? Map<String, dynamic>.from(data['raw'] as Map)
          : null,
    );
  }

  factory FoodItem.fromCatalog(Map<String, dynamic> data) {
    return FoodItem(
      foodId: data['foodId']?.toString(),
      servingId: data['servingId']?.toString(),
      emoji: '\u{1F37D}\u{FE0F}',
      name: data['name']?.toString() ?? 'Food',
      portion: data['servingDescription']?.toString() ?? '1 serving',
      quantity: _asDouble(data['quantity'] ?? 1),
      calories: _asInt(data['calories']),
      time: DateFormat('h:mm a').format(DateTime.now()),
      protein: _asDouble(data['protein']),
      carbohydrate: _asDouble(data['carbohydrate']),
      fat: _asDouble(data['fat']),
      sodium: _asDouble(data['sodium']),
      potassium: _asDouble(data['potassium']),
      phosphorus: _asDouble(data['phosphorus']),
      source: data['source']?.toString() ?? 'fatsecret',
      needsManualReview: data['needsManualReview'] == true,
      raw: data,
    );
  }
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _asInt(dynamic value) => _asDouble(value).round();

String _formatDisplayTime(dynamic value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  if (parsed == null) return DateFormat('h:mm a').format(DateTime.now());
  return DateFormat('h:mm a').format(parsed.toLocal());
}
