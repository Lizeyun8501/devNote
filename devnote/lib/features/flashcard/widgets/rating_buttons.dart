import 'package:flutter/material.dart';

class RatingButtons extends StatelessWidget {
  final void Function(int quality) onRate;

  const RatingButtons({super.key, required this.onRate});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RatingButton(
          label: 'Again',
          color: Colors.red,
          quality: 1,
          onRate: onRate,
        ),
        _RatingButton(
          label: 'Hard',
          color: Colors.orange,
          quality: 3,
          onRate: onRate,
        ),
        _RatingButton(
          label: 'Good',
          color: Colors.green,
          quality: 4,
          onRate: onRate,
        ),
        _RatingButton(
          label: 'Easy',
          color: Colors.blue,
          quality: 5,
          onRate: onRate,
        ),
      ],
    );
  }
}

class _RatingButton extends StatelessWidget {
  final String label;
  final Color color;
  final int quality;
  final void Function(int quality) onRate;

  const _RatingButton({
    required this.label,
    required this.color,
    required this.quality,
    required this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          onPressed: () => onRate(quality),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}
