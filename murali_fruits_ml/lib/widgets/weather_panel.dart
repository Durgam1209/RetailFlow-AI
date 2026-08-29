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
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0F382C).withValues(alpha: 0.92),
            const Color(0xFF1E5140).withValues(alpha: 0.96),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F382C).withValues(alpha: 0.25),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (todayWeather != null) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          weatherService?.getWeatherEmoji(todayWeather!) ?? '⛅',
                          style: const TextStyle(fontSize: 22),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.location_on_rounded,
                                color: Color(0xFF34D399),
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Mahadevapura, Bengaluru',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white.withValues(alpha: 0.8),
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            todayWeather!.condition,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      '${todayWeather!.temperature.toStringAsFixed(1)}°C',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _WeatherStatPill(
                    icon: Icons.water_drop_rounded,
                    label: 'Humidity',
                    value: '${todayWeather!.humidity}%',
                    accentColor: const Color(0xFF60A5FA),
                  ),
                  const SizedBox(width: 8),
                  _WeatherStatPill(
                    icon: Icons.air_rounded,
                    label: 'Wind',
                    value: '${todayWeather!.windSpeed.toStringAsFixed(1)} m/s',
                    accentColor: const Color(0xFF34D399),
                  ),
                  if (weatherService != null) ...[
                    const SizedBox(width: 8),
                    _WeatherStatPill(
                      icon: Icons.eco_rounded,
                      label: 'Impact',
                      value: _getImpactSummary(todayWeather!.condition),
                      accentColor: const Color(0xFFFBBF24),
                    ),
                  ],
                ],
              ),
            ],
            if (todayWeather == null && tomorrowWeather != null) ...[
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Text('⛅', style: TextStyle(fontSize: 22)),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Today weather unavailable',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
            if (showTomorrow && tomorrowWeather != null) ...[
              const SizedBox(height: 12),
              Divider(color: Colors.white.withValues(alpha: 0.15), height: 1),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        weatherService?.getWeatherEmoji(tomorrowWeather!) ?? '⛅',
                        style: const TextStyle(fontSize: 16),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Tomorrow: ${tomorrowWeather!.condition}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${tomorrowWeather!.temperature.toStringAsFixed(1)}°C',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _getImpactSummary(String condition) {
    final lower = condition.toLowerCase();
    if (lower.contains('rain') || lower.contains('drizzle')) {
      return 'High Citrus';
    } else if (lower.contains('sun') || lower.contains('clear') || lower.contains('hot')) {
      return 'High Melon';
    } else {
      return 'Steady';
    }
  }
}

class _WeatherStatPill extends StatelessWidget {
  const _WeatherStatPill({
    required this.icon,
    required this.label,
    required this.value,
    required this.accentColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 14, color: accentColor),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.65),
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

