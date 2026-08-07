import 'package:flutter/material.dart';

const Color desktopSalesSurface = Color(0xFFEFF5F8);
const Color desktopSalesPanel = Colors.white;
const Color desktopSalesLine = Color(0xFFD8E5EC);
const Color desktopSalesText = Color(0xFF172033);
const Color desktopSalesMuted = Color(0xFF64748B);
const Color desktopSalesAccent = Color(0xFF1957E6);
const Color desktopSalesAccentSoft = Color(0xFFEAF1FF);

class DesktopSalesFrame extends StatelessWidget {
  const DesktopSalesFrame({
    super.key,
    required this.child,
    this.padding,
    this.maxWidth = double.infinity,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: desktopSalesSurface,
      child: Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(18, 18, 18, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: child,
        ),
      ),
    );
  }
}

class DesktopSalesPanel extends StatelessWidget {
  const DesktopSalesPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: desktopSalesPanel,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: desktopSalesLine),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0B3550).withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

InputDecoration desktopSalesInputDecoration({
  required String hintText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    hintText: hintText,
    isDense: true,
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: desktopSalesLine),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: desktopSalesLine),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: desktopSalesAccent, width: 1.4),
    ),
  );
}
