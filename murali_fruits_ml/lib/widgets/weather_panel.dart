import 'package:flutter/material.dart';
import '../data/weather_service.dart';

class WeatherDisplayPanel extends StatelessWidget {
  const WeatherDisplayPanel({
    super.key,
    required this.todayWeather,
    required this.tomorrowWeather,
    this.weatherService,
    this.showTomorrow = false,
  });

  final WeatherData? todayWeather;
  final WeatherData? tomorrowWeather;
  final WeatherService? weatherService;
  final bool showTomorrow;

  @override
  Widget build(BuildContext context) {
    if (todayWeather == null && tomorrowWeather == null) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (todayWeather != null) ...[
              Row(
                children: [
                  Text(
                    'Today: ${todayWeather!.condition}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    weatherService?.getWeatherEmoji(todayWeather!) ?? '\u26C5',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
              Row(
                children: [
                  Text(
                    '${todayWeather!.temperature.toStringAsFixed(1)} C',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Humidity ${todayWeather!.humidity}%',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Wind ${todayWeather!.windSpeed.toStringAsFixed(1)} m/s',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ],
            if (todayWeather == null && tomorrowWeather != null) ...[
              const SizedBox(height: 2),
              Row(
                children: const [
                  Text(
                    'Today: unavailable',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6A5F57),
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    '\u26C5',
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ],
            if (showTomorrow && todayWeather != null && tomorrowWeather != null)
              const SizedBox(height: 12),
            if (showTomorrow && tomorrowWeather != null) ...[
              Row(
                children: [
                  Text(
                    'Tomorrow: ${tomorrowWeather!.condition}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6A5F57),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    weatherService?.getWeatherEmoji(tomorrowWeather!) ??
                        '\u26C5',
                    style: const TextStyle(fontSize: 16),
                  ),
                ],
              ),
              Text(
                '${tomorrowWeather!.temperature.toStringAsFixed(1)} C',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6A5F57),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
