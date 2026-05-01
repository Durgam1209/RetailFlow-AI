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
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: hasQuantity ? palette.primary : const Color(0xFFE5DED3),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _IconBadge(
                  icon: fruit.icon,
                  backgroundColor: palette.soft,
                  foregroundColor: palette.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        fruit.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1F1B18),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '+${_formatIncrement(fruit.defaultIncrement)} kg per tap',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF7B6F65),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: _InfoChip(
                    label: 'Weight',
                    value: _formatQuantity(quantityKg, displayMetric),
                    icon: Icons.scale_rounded,
                    tint: palette.soft,
                    onTap: onEditWeight,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoChip(
                    label: 'Price',
                    value: 'Rs ${unitPrice.toStringAsFixed(0)} / kg',
                    icon: Icons.currency_rupee_rounded,
                    tint: const Color(0xFFF4EFE8),
                    onTap: onEditPrice,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F4EE),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: <Widget>[
                  const Text(
                    'Line total',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF7B6F65),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Rs ${lineTotal.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1F1B18),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            Row(
              children: <Widget>[
                Expanded(
                  child: _ActionButton(
                    label: '-',
                    backgroundColor: const Color(0xFFF4EFE8),
                    foregroundColor: const Color(0xFF1F1B18),
                    borderColor: const Color(0xFFE6DDD1),
                    onTap: onDecrement,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _ActionButton(
                    label: 'Add ${_formatIncrement(fruit.defaultIncrement)} kg',
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
          soft: Color(0xFFFFEEE8),
          primary: Color(0xFFC85D42),
        );
      case 'banana_big':
      case 'banana_yelakki':
      case 'papaya':
        return const _FruitPalette(
          soft: Color(0xFFFFF3D9),
          primary: Color(0xFFCC8A2E),
        );
      case 'orange_citrus':
      case 'orange_mandarin':
      case 'orange_nagpur':
      case 'musambi':
        return const _FruitPalette(
          soft: Color(0xFFFFF1E1),
          primary: Color(0xFFCF7A32),
        );
      case 'grapes_green':
      case 'grapes_green_seedless':
      case 'watermelon':
      case 'watermelon_kiran':
        return const _FruitPalette(
          soft: Color(0xFFEAF5E8),
          primary: Color(0xFF5E8E59),
        );
      case 'grapes_black':
      case 'grapes_black_seedless':
        return const _FruitPalette(
          soft: Color(0xFFF0ECF8),
          primary: Color(0xFF6E5AA5),
        );
      default:
        return const _FruitPalette(
          soft: Color(0xFFF4EFE8),
          primary: Color(0xFF7B6F65),
        );
    }
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.tint,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tint,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(icon, size: 16, color: const Color(0xFF7B6F65)),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF7B6F65),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F1B18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
