import 'package:flutter/material.dart';

enum ProductArtworkKind { filter, delete, add }

/// Original transparent PNG files supplied by the owner for product screens.
class ProductArtwork extends StatelessWidget {
  const ProductArtwork(this.kind, {super.key, this.size = 20, this.color});
  final ProductArtworkKind kind;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/image/product_${kind.name}.png',
    width: size,
    height: size,
    fit: BoxFit.contain,
    color: color ?? IconTheme.of(context).color,
    colorBlendMode: BlendMode.srcIn,
    excludeFromSemantics: true,
  );
}
