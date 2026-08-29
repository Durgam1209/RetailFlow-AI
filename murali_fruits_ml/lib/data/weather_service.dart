import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WeatherData {
  final double temperature;
  final double feelsLike;
  final int humidity;
  final double windSpeed;
  final String condition;
  final String icon;
  final DateTime dateTime;
  final double? rainProbability;

  WeatherData({
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.windSpeed,
    required this.condition,
    required this.icon,
    required this.dateTime,
    this.rainProbability,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final main = json['main'] as Map<String, dynamic>?;
    final weather = (json['weather'] as List?)?[0] as Map<String, dynamic>?;
    final wind = json['wind'] as Map<String, dynamic>?;

    return WeatherData(
      temperature: (main?['temp'] as num?)?.toDouble() ?? 0,
      feelsLike: (main?['feels_like'] as num?)?.toDouble() ?? 0,
      humidity: (main?['humidity'] as num?)?.toInt() ?? 0,
      windSpeed: (wind?['speed'] as num?)?.toDouble() ?? 0,
      condition: weather?['main'] as String? ?? 'Unknown',
      icon: weather?['icon'] as String? ?? '01d',
      dateTime: DateTime.fromMillisecondsSinceEpoch(
        ((json['dt'] as num?)?.toInt() ?? 0) * 1000,
      ),
      rainProbability: (json['pop'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap({String? label}) {
    return <String, dynamic>{
      if (label != null) 'label': label,
      'temperature': temperature,
      'feelsLike': feelsLike,
      'humidity': humidity,
      'windSpeed': windSpeed,
      'condition': condition,
      'icon': icon,
      'dateTime': dateTime.toIso8601String(),
      if (rainProbability != null) 'rainProbability': rainProbability,
    };
  }

  bool get isRainy => condition.toLowerCase().contains('rain');
  bool get isHot => temperature > 30;
  bool get isCold => temperature < 15;
  bool get isHumid => humidity > 70;
}

class WeatherService {
  final String apiKey;
  final String cityName;
  final double? latitude;
  final double? longitude;

  WeatherService({
    required this.apiKey,
    required this.cityName,
    this.latitude,
    this.longitude,
  });

  Future<WeatherData?> getTodayWeather() async {
    try {
      final url = _weatherUri('weather');

      final response = await _makeRequest(url);
      if (response == null) return null;

      return WeatherData.fromJson(response);
    } catch (e) {
      debugPrint('Error fetching today weather: $e');
      return null;
    }
  }

  Future<WeatherData?> getTomorrowWeather() async {
    try {
      final url = _weatherUri('forecast', extra: <String, String>{'cnt': '16'});

      final response = await _makeRequest(url);
      if (response == null) return null;

      final list = response['list'] as List?;
      if (list == null || list.isEmpty) return null;

      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final nextDay = tomorrow.add(const Duration(days: 1));
      Map<String, dynamic>? tomorrowForecast;

      for (final item in list.whereType<Map<String, dynamic>>()) {
        final forecastTime = DateTime.fromMillisecondsSinceEpoch(
          ((item['dt'] as num?)?.toInt() ?? 0) * 1000,
        );
        if (forecastTime.isAfter(tomorrow) && forecastTime.isBefore(nextDay)) {
          tomorrowForecast = item;
          if (forecastTime.hour >= 11 && forecastTime.hour <= 14) {
            break;
          }
        }
      }

      tomorrowForecast ??= list.last as Map<String, dynamic>;

      return WeatherData.fromJson(tomorrowForecast);
    } catch (e) {
      debugPrint('Error fetching tomorrow weather: $e');
      return null;
    }
  }

  Uri _weatherUri(String path, {Map<String, String> extra = const {}}) {
    final query = <String, String>{
      if (latitude != null && longitude != null) ...<String, String>{
        'lat': latitude!.toString(),
        'lon': longitude!.toString(),
      } else
        'q': cityName,
      'units': 'metric',
      'appid': apiKey,
      ...extra,
    };
    return Uri.https('api.openweathermap.org', '/data/2.5/$path', query);
  }

  Future<Map<String, dynamic>?> _makeRequest(Uri url) async {
    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        debugPrint('Weather API: unexpected JSON shape for ${url.path}');
        return null;
      }

      debugPrint('Weather API error: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      debugPrint('Weather request error: $e');
      return null;
    }
  }


  List<String> getRecommendedFruits(WeatherData weather) {
    final recommendations = <String>[];

    if (weather.isHot) {
      recommendations.addAll(['Watermelon', 'Muskmelon', 'Orange', 'Papaya']);
    }

    if (weather.isCold) {
      recommendations.addAll(['Banana', 'Pomegranate', 'Apple']);
    }

    if (weather.isRainy || (weather.rainProbability ?? 0) > 0.5) {
      recommendations.addAll(['Banana', 'Pomegranate', 'Apple', 'Grapes']);
    }

    if (weather.isHumid) {
      recommendations.addAll(['Orange', 'Musambi', 'Papaya']);
    }

    // Remove duplicates
    return recommendations.toSet().toList();
  }

  String getWeatherEmoji(WeatherData weather) {
    if (weather.condition.toLowerCase().contains('cloud')) return '\u2601';
    if (weather.condition.toLowerCase().contains('rain')) return '\u2614';
    if (weather.condition.toLowerCase().contains('clear')) return '\u2600';
    if (weather.condition.toLowerCase().contains('sunny')) return '\u2600';
    if (weather.condition.toLowerCase().contains('snow')) return '\u2744';
    if (weather.condition.toLowerCase().contains('storm')) return '\u26C8';
    return '\u26C5';
  }
}
