import '../theme/app_theme.dart';
import 'package:flutter/material.dart';

import '../models/fruit_item.dart';

class FruitTile extends StatelessWidget {
  const FruitTile({
    super.key,
    required this.fruit,
    required this.quantityKg,
    required this.displayMetric,
    required this.unitPrice,
    required this.lineTotal,
    required this.onEditWeight,
    required this.onIncrement,
    required this.onDecrement,
    required this.onEditPrice,
  });

  final FruitItem fruit;
  final double quantityKg;
  final String displayMetric;
  final double unitPrice;
  final double lineTotal;
  final VoidCallback onEditWeight;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onEditPrice;

  @override
  Widget build(BuildContext context) {
    final palette = _paletteForFruit(fruit.id);
    final hasQuantity = quantityKg > 0;

    return Container(
      decoration: BoxDecoration(
        color: hasQuantity
            ? palette.soft.withValues(alpha: 0.4)
            : Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: hasQuantity ? palette.primary : RetailPalette.line,
          width: hasQuantity ? 2 : 1,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: hasQuantity
                ? palette.primary.withValues(alpha: 0.15)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: hasQuantity ? 20 : 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Header: Fruit name, icon, and active quantity badge
            Row(
              children: <Widget>[
                _IconBadge(
                  icon: fruit.icon,
                  backgroundColor: palette.soft,
                  foregroundColor: palette.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fruit.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: RetailPalette.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '₹${unitPrice.toStringAsFixed(0)} / kg',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: palette.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (hasQuantity)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: palette.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Details section: Weight, Price, Line Total
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: hasQuantity
                    ? Colors.white.withValues(alpha: 0.9)
                    : RetailPalette.warmSurface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: RetailPalette.line.withValues(alpha: 0.6),
                ),
              ),
              child: Column(
                children: <Widget>[
                  // Weight and Price row
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: GestureDetector(
                          onTap: onEditWeight,
                          behavior: HitTestBehavior.opaque,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Row(
                                children: [
                                  Text(
                                    'Weight',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: RetailPalette.mutedLabel,
                                    ),
                                  ),
                                  const SizedBox(width: 3),
                                  Icon(
                                    Icons.edit_rounded,
                                    size: 10,
                                    color: RetailPalette.mutedLabel,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatQuantity(quantityKg, displayMetric),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: RetailPalette.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        height: 24,
                        width: 1,
                        color: RetailPalette.line,
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: onEditPrice,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Row(
                                  children: [
                                    Text(
                                      'Price/kg',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: RetailPalette.mutedLabel,
                                      ),
                                    ),
                                    const SizedBox(width: 3),
                                    Icon(
                                      Icons.edit_rounded,
                                      size: 10,
                                      color: RetailPalette.mutedLabel,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '₹${unitPrice.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: RetailPalette.ink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Divider(height: 1, color: RetailPalette.line),
                  const SizedBox(height: 6),
                  // Line Total row
                  Row(
                    children: <Widget>[
                      const Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: RetailPalette.mutedLabel,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '₹${lineTotal.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: hasQuantity
                              ? palette.primary
                              : RetailPalette.ink,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Action buttons
            Row(
              children: <Widget>[
                Expanded(
                  child: _ActionButton(
                    label: '−',
                    backgroundColor: RetailPalette.toneF4EFE8,
                    foregroundColor: RetailPalette.ink,
                    borderColor: RetailPalette.toneE6DDD1,
                    onTap: onDecrement,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
                  child: _ActionButton(
                    label: '+${_formatIncrement(fruit.defaultIncrement)} kg',
                    backgroundColor: palette.primary,
                    foregroundColor: Colors.white,
                    borderColor: palette.primary,
                    onTap: onIncrement,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatIncrement(double value) {
    return value.truncateToDouble() == value
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
  }

  String _formatQuantity(double quantityKg, String displayMetric) {
    if (displayMetric == 'g') {
      return '${(quantityKg * 1000).toStringAsFixed(0)} g';
    }
    return '${quantityKg.toStringAsFixed(1)} kg';
  }

  _FruitPalette _paletteForFruit(String id) {
    switch (id) {
      case 'apple_poland':
      case 'apple_washington':
      case 'pomegranate':
        return const _FruitPalette(
          soft: RetailPalette.toneFFEEE8,
          primary: RetailPalette.toneC85D42,
        );
      case 'banana_big':
      case 'banana_yelakki':
      case 'papaya':
        return const _FruitPalette(
          soft: RetailPalette.toneFFF3D9,
          primary: RetailPalette.gold,
        );
      case 'orange_citrus':
      case 'orange_mandarin':
      case 'orange_nagpur':
      case 'musambi':
        return const _FruitPalette(
          soft: RetailPalette.toneFFF1E1,
          primary: RetailPalette.orange,
        );
      case 'grapes_green':
      case 'grapes_green_seedless':
      case 'watermelon':
      case 'watermelon_kiran':
        return const _FruitPalette(
          soft: RetailPalette.paleGreen,
          primary: RetailPalette.tone5E8E59,
        );
      case 'grapes_black':
      case 'grapes_black_seedless':
        return const _FruitPalette(
          soft: RetailPalette.toneF0ECF8,
          primary: RetailPalette.tone6E5AA5,
        );
      default:
        return const _FruitPalette(
          soft: RetailPalette.toneF4EFE8,
          primary: RetailPalette.mutedLabel,
        );
    }
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String icon;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(icon, style: TextStyle(fontSize: 30, color: foregroundColor)),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.borderColor,
    required this.onTap,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: foregroundColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FruitPalette {
  const _FruitPalette({required this.soft, required this.primary});

  final Color soft;
  final Color primary;
}
