import 'package:flutter/material.dart';

/// Collapsible section with smooth animations - SaaS premium style
class CampaignCollapsibleSection extends StatefulWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  final bool initiallyExpanded;
  final EdgeInsets padding;
  final VoidCallback? onToggle;
  final bool isDense;

  const CampaignCollapsibleSection({
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.initiallyExpanded = true,
    this.padding = const EdgeInsets.all(14),
    this.onToggle,
    this.isDense = false,
    super.key,
  });

  @override
  State<CampaignCollapsibleSection> createState() =>
      _CampaignCollapsibleSectionState();
}

class _CampaignCollapsibleSectionState extends State<CampaignCollapsibleSection>
    with SingleTickerProviderStateMixin {
  late bool _isExpanded;
  late AnimationController _controller;
  late Animation<double> _heightAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;

    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );

    _heightAnimation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _rotationAnimation = Tween<double>(
      begin: 0,
      end: 0.5,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    if (_isExpanded) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
    widget.onToggle?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header (always visible)
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggleExpanded,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    if (widget.icon != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          widget.icon,
                          size: 18,
                          color: scheme.primary,
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (widget.subtitle != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                widget.subtitle!,
                                style: textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    RotationTransition(
                      turns: _rotationAnimation,
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Divider
          Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.15),
          ),
          // Content (collapsible)
          AnimatedBuilder(
            animation: _heightAnimation,
            builder: (context, child) {
              return ClipRect(
                child: Align(
                  alignment: Alignment.topCenter,
                  heightFactor: _heightAnimation.value,
                  child: child,
                ),
              );
            },
            child: Padding(
              padding: widget.isDense
                  ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
                  : widget.padding,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact form field with reduced padding - designed for density
class CompactFormField extends StatefulWidget {
  final String label;
  final String? hint;
  final TextEditingController? controller;
  final String? initialValue;
  final TextInputType keyboardType;
  final int maxLines;
  final int minLines;
  final ValueChanged<String>? onChanged;
  final String? Function(String?)? validator;
  final bool obscureText;
  final Widget? prefix;
  final Widget? suffix;

  const CompactFormField({
    required this.label,
    this.hint,
    this.controller,
    this.initialValue,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.minLines = 1,
    this.onChanged,
    this.validator,
    this.obscureText = false,
    this.prefix,
    this.suffix,
    super.key,
  });

  @override
  State<CompactFormField> createState() => _CompactFormFieldState();
}

class _CompactFormFieldState extends State<CompactFormField> {
  late TextEditingController _controller;
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        TextEditingController(text: widget.initialValue ?? '');
    _controller.addListener(() {
      widget.onChanged?.call(_controller.text);
      setState(() {});
    });
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Focus(
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      child: TextField(
        controller: _controller,
        onChanged: widget.onChanged,
        keyboardType: widget.keyboardType,
        maxLines: widget.maxLines,
        minLines: widget.minLines,
        obscureText: widget.obscureText,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 13),
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          labelStyle: Theme.of(context).textTheme.labelSmall,
          hintStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
          ),
          prefixIcon: widget.prefix,
          suffixIcon: widget.suffix,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          isDense: true,
          filled: true,
          fillColor: _isFocused
              ? scheme.primaryContainer.withValues(alpha: 0.15)
              : scheme.surfaceContainer.withValues(alpha: 0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.2),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: scheme.primary, width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: scheme.error),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: scheme.error, width: 1.5),
          ),
        ),
      ),
    );
  }
}

/// Compact horizontal layout for two fields side-by-side
class CompactFieldRow extends StatelessWidget {
  final CompactFormField field1;
  final CompactFormField field2;
  final double spacing;

  const CompactFieldRow({
    required this.field1,
    required this.field2,
    this.spacing = 8,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: field1),
        SizedBox(width: spacing),
        Expanded(child: field2),
      ],
    );
  }
}
