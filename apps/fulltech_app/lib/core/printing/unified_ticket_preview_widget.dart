import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/ticket_data.dart';
import 'simplified_ticket_preview_widget.dart';
import 'unified_ticket_printer.dart';

class UnifiedTicketPreviewWidget extends ConsumerWidget {
  const UnifiedTicketPreviewWidget({super.key, this.data});

  final TicketData? data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder<TicketPreviewConfig>(
      future: ref
          .read(unifiedTicketPrinterProvider)
          .getPreviewConfig(data: data),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final config = snapshot.data!;
        return SimplifiedTicketPreviewWidget(
          text: config.text,
          paperWidthMm: config.paperWidthMm,
        );
      },
    );
  }
}
