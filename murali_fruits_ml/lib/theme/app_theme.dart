import 'package:flutter/material.dart';

/// Shared color tokens for RetailFlow screens.
abstract final class RetailPalette {
  static const Color forest = Color(0xFF0F382C);
  static const Color success = Color(0xFF117A37);
  static const Color deepForest = Color(0xFF123C2C);
  static const Color leaf = Color(0xFF165B46);
  static const Color blue = Color(0xFF1769AA);
  static const Color darkLeaf = Color(0xFF1E5140);
  static const Color ink = Color(0xFF1F1B18);
  static const Color charcoal = Color(0xFF2E2722);
  static const Color green = Color(0xFF2E7D32);
  static const Color deepGreen = Color(0xFF2F6F37);
  static const Color mint = Color(0xFF34D399);
  static const Color slateBlue = Color(0xFF355165);
  static const Color bodyText = Color(0xFF5E534B);
  static const Color tone5E8E59 = Color(0xFF5E8E59);
  static const Color tone60A5FA = Color(0xFF60A5FA);
  static const Color mutedText = Color(0xFF6A5F57);
  static const Color tone6E5AA5 = Color(0xFF6E5AA5);
  static const Color disabled = Color(0xFF716860);
  static const Color mutedLabel = Color(0xFF7B6F65);
  static const Color warningText = Color(0xFF8A3B12);
  static const Color amberText = Color(0xFF8B4C00);
  static const Color subtleText = Color(0xFF6A5F57);
  static const Color tone8FB6D9 = Color(0xFF8FB6D9);
  static const Color amber = Color(0xFF9A5A00);
  static const Color danger = Color(0xFFB3261E);
  static const Color toneB8D8F2 = Color(0xFFB8D8F2);
  static const Color warning = Color(0xFFC46005);
  static const Color toneC85D42 = Color(0xFFC85D42);
  static const Color gold = Color(0xFFCC8A2E);
  static const Color orange = Color(0xFFCF7A32);
  static const Color toneDFF3E5 = Color(0xFFDFF3E5);
  static const Color border = Color(0xFFE1D8CE);
  static const Color toneE4F5DD = Color(0xFFE4F5DD);
  static const Color line = Color(0xFFE5DED3);
  static const Color toneE6DDD1 = Color(0xFFE6DDD1);
  static const Color softBorder = Color(0xFFE7DED2);
  static const Color toneE7F1E3 = Color(0xFFE7F1E3);
  static const Color skeleton = Color(0xFFE8E2DB);
  static const Color toneE8F0FF = Color(0xFFE8F0FF);
  static const Color toneE8F4FF = Color(0xFFE8F4FF);
  static const Color paleGreen = Color(0xFFEAF5E8);
  static const Color paleMint = Color(0xFFEAF5EE);
  static const Color toneF0ECF8 = Color(0xFFF0ECF8);
  static const Color toneF1F6EA = Color(0xFFF1F6EA);
  static const Color toneF4EFE8 = Color(0xFFF4EFE8);
  static const Color toneF5EFE6 = Color(0xFFF5EFE6);
  static const Color canvas = Color(0xFFF7F3EE);
  static const Color warmSurface = Color(0xFFF8F4EE);
  static const Color toneFAF8F4 = Color(0xFFFAF8F4);
  static const Color toneFBBF24 = Color(0xFFFBBF24);
  static const Color toneFF8A80 = Color(0xFFFF8A80);
  static const Color toneFFD180 = Color(0xFFFFD180);
  static const Color toneFFE2B8 = Color(0xFFFFE2B8);
  static const Color toneFFE4DE = Color(0xFFFFE4DE);
  static const Color toneFFE7BA = Color(0xFFFFE7BA);
  static const Color toneFFE8CC = Color(0xFFFFE8CC);
  static const Color toneFFEEE8 = Color(0xFFFFEEE8);
  static const Color paleAmber = Color(0xFFFFF0BF);
  static const Color toneFFF0C7 = Color(0xFFFFF0C7);
  static const Color paleGold = Color(0xFFFFF1D9);
  static const Color toneFFF1E1 = Color(0xFFFFF1E1);
  static const Color toneFFF3D9 = Color(0xFFFFF3D9);
  static const Color toneFFF6EA = Color(0xFFFFF6EA);
  static const Color toneFFFCF7 = Color(0xFFFFFCF7);
  static const Color white = Color(0xFFFFFFFF);
}

abstract final class RetailSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class RetailTextStyles {
  static const TextStyle pageTitle = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w900,
    color: RetailPalette.ink,
  );
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w900,
    color: RetailPalette.ink,
  );
  static const TextStyle body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: RetailPalette.bodyText,
  );
  static const TextStyle label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w800,
    color: RetailPalette.mutedText,
  );
}

abstract final class RetailAppTheme {
  static final ThemeData light = ThemeData(
    scaffoldBackgroundColor: RetailPalette.canvas,
    colorScheme: const ColorScheme.light(
      primary: RetailPalette.charcoal,
      secondary: RetailPalette.gold,
      surface: RetailPalette.white,
    ),
    textTheme: const TextTheme(
      headlineMedium: RetailTextStyles.pageTitle,
      titleLarge: RetailTextStyles.sectionTitle,
      bodyMedium: RetailTextStyles.body,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: RetailPalette.ink,
      elevation: 0,
    ),
  );
}
