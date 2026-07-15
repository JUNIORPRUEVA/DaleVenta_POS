import 'package:flutter/material.dart';

class SimplifiedTicketPreviewWidget extends StatelessWidget {
  const SimplifiedTicketPreviewWidget({
    super.key,
    required this.text,
    this.paperWidthMm = 80,
  });

  final String text;
  final int paperWidthMm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final width = paperWidthMm == 58 ? 260.0 : 340.0;
    return Center(
      child: Container(
        width: width,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.black,
            fontFamily: 'Courier New',
            fontSize: 12,
            height: 1.18,
          ),
        ),
      ),
    );
  }
}
