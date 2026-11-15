import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Close affordance remains accessible when the visual tooltip is omitted.
Finder closeFeedbackButton() => find.byWidgetPredicate(
  (widget) => widget is IconButton &&
      (widget.tooltip == 'Cerrar notificación' ||
       (widget.icon is Icon &&
        (widget.icon as Icon).semanticLabel == 'Cerrar notificación')),
);
