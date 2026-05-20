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
    final clouds = json['clouds'] as Map<String, dynamic>?;
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

  bool get isRainy => condition.toLowerCase().contains('rain');
  bool get isHot => temperature > 30;
  bool get isCold => temperature < 15;
  bool get isHumid => humidity > 70;
}

class WeatherService {
  static const String _baseUrl = 'https://api.openweathermap.org/data/2.5';
  final String apiKey;
  final String cityName;

  WeatherService({
    required this.apiKey,
    required this.cityName,
  });

  Future<WeatherData?> getTodayWeather() async {
    try {
      final url = Uri.parse(
        '$_baseUrl/weather?q=$cityName&units=metric&appid=$apiKey',
      );
      
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
      final url = Uri.parse(
        '$_baseUrl/forecast?q=$cityName&units=metric&appid=$apiKey&cnt=16',
      );
      
      final response = await _makeRequest(url);
      if (response == null) return null;

      final list = response['list'] as List?;
      if (list == null || list.isEmpty) return null;

      // Get forecast for tomorrow at noon (around 8th item in 5-day forecast)
      final tomorrowForecast = list.length > 8
          ? list[8] as Map<String, dynamic>
          : list.last as Map<String, dynamic>;

      return WeatherData.fromJson(tomorrowForecast);
    } catch (e) {
      debugPrint('Error fetching tomorrow weather: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _makeRequest(Uri url) async {
    try {
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
      );
      
      if (response.statusCode == 200) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      } else {
        debugPrint('Weather API error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Request error: $e');
      return null;
    }
  }

  List<String> getRecommendedFruits(WeatherData weather) {
    final recommendations = <String>[];

    if (weather.isHot) {
      recommendations.addAll([
        'Watermelon',
        'Muskmelon',
        'Orange',
        'Papaya',
      ]);
    }

    if (weather.isCold) {
      recommendations.addAll([
        'Banana',
        'Pomegranate',
        'Apple',
      ]);
    }

    if (weather.isRainy || (weather.rainProbability ?? 0) > 0.5) {
      recommendations.addAll([
        'Banana',
        'Pomegranate',
        'Apple',
        'Grapes',
      ]);
    }

    if (weather.isHumid) {
      recommendations.addAll([
        'Orange',
        'Musambi',
        'Papaya',
      ]);
    }

    // Remove duplicates
    return recommendations.toSet().toList();
  }

  String getWeatherEmoji(WeatherData weather) {
    if (weather.condition.toLowerCase().contains('cloud')) return '☁️';
    if (weather.condition.toLowerCase().contains('rain')) return '🌧️';
    if (weather.condition.toLowerCase().contains('clear')) return '☀️';
    if (weather.condition.toLowerCase().contains('sunny')) return '☀️';
    if (weather.condition.toLowerCase().contains('snow')) return '❄️';
    if (weather.condition.toLowerCase().contains('storm')) return '⛈️';
    return '🌤️';
  }
}
