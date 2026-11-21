import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../data/datasources/ai_assistant_datasource.dart';
import '../../domain/models/ai_support_case.dart';
import '../../../errors/api_exception.dart';

class AiSupportCaseLink extends StatelessWidget {
  const AiSupportCaseLink({super.key, required this.supportCase});
  final AiSupportCase supportCase;
  @override
  Widget build(BuildContext context) => TextButton.icon(
    icon: const Icon(Icons.forum_outlined, size: 16),
    label: Text('Ver soporte · ${supportCase.reference}'),
    onPressed: () => showDialog<void>(context: context, useRootNavigator: false,
      builder: (_) => _SupportThread(supportCase: supportCase)),
  );
}

class _SupportThread extends ConsumerStatefulWidget {
  const _SupportThread({required this.supportCase});
  final AiSupportCase supportCase;
  @override
  ConsumerState<_SupportThread> createState() => _SupportThreadState();
}

class _SupportThreadState extends ConsumerState<_SupportThread> {
  final _text = TextEditingController();
  Timer? _timer;
  Map<String, dynamic>? _data;
  String? _error;
  String? _requestId;
  String? _pendingText;
  bool _busy = false;
  bool _sending = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => unawaited(_load()));
  }
  @override
  void dispose() { _timer?.cancel(); _text.dispose(); super.dispose(); }
  Future<void> _load({bool send = false}) async {
    if (_busy || (send && _text.text.trim().isEmpty)) return;
    _busy = true;
    if (send) setState(() => _sending = true);
    final text = _text.text.trim();
    if (send && _pendingText != text) { _pendingText = text; _requestId = const Uuid().v4(); }
    try {
      final data = await ref.read(aiAssistantDataSourceProvider).supportCase(widget.supportCase.id,
        message: send ? text : null, requestId: send ? _requestId : null);
      if (!mounted) return;
      setState(() { _data = data; _error = null; });
      if (send) { _text.clear(); _pendingText = null; _requestId = null; }
    } catch (error) {
      if (mounted) setState(() => _error = error is ApiException ? error.message : 'No se pudo confirmar la consulta. Reintenta.');
    } finally { _busy = false; if (mounted) setState(() => _sending = false); }
  }
  @override
  Widget build(BuildContext context) {
    final status = _data?['status'];
    final closed = status == 'resolved' || status == 'cancelled';
    final label = const {'open': 'Abierto', 'in_progress': 'En curso', 'waiting': 'En espera',
      'resolved': 'Resuelto', 'cancelled': 'Cerrado'}[status] ?? 'Consultando…';
    final messages = (_data?['messages'] as List? ?? []).whereType<Map>();
    return AlertDialog(
      insetPadding: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      title: Text('Soporte · ${widget.supportCase.reference}'),
      content: SizedBox(width: 420, height: MediaQuery.sizeOf(context).height * .55,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          Expanded(child: ListView(children: [for (final message in messages)
            Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(
              '${message['authorType'] == 'customer' ? 'Tú' : 'Soporte'}: ${message['body'] ?? ''}')),
          ])),
          if (!closed) ...[
            TextField(controller: _text, maxLines: 3, minLines: 1, maxLength: 4000,
              decoration: const InputDecoration(hintText: 'Responder a soporte…')),
            Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _sending ? null : () => _load(send: true),
              child: Text(_sending ? 'Enviando…' : 'Enviar a soporte'))),
          ],
        ])),
      actions: [TextButton(onPressed: () => _load(), child: const Text('Actualizar')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Volver al chat'))],
    );
  }
}
