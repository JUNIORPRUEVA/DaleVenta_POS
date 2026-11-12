import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/branded_menu_button.dart';
import '../widgets/sales_ticket_bar.dart';

/// Escenario visual aislado. Sus tickets son fixtures y no consultan ni guardan datos.
void main() => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: const SalesTicketBarPreview(),
  ),
);

class SalesTicketBarPreview extends StatefulWidget {
  const SalesTicketBarPreview({super.key});

  @override
  State<SalesTicketBarPreview> createState() => _SalesTicketBarPreviewState();
}

class _SalesTicketBarPreviewState extends State<SalesTicketBarPreview> {
  List<({int id, String label, int count})> _tickets = [
    (id: 1, label: 'Ticket 1', count: 0),
    (id: 2, label: 'Mostrador', count: 4),
    (id: 3, label: 'Pedido para recoger', count: 2),
  ];
  int _active = 2;
  int _nextId = 4;

  void _create() => setState(() {
    final id = _nextId++;
    _tickets.insert(0, (id: id, label: 'Ticket $id', count: 0));
    _active = id;
  });

  Future<void> _rename(int id) async {
    final ticket = _tickets.firstWhere((ticket) => ticket.id == id);
    var value = ticket.label;
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar ticket'),
        content: TextFormField(
          initialValue: value,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre del ticket'),
          onChanged: (text) => value = text,
          onFieldSubmitted: (text) => Navigator.pop(context, text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, value),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (!mounted || title == null || title.trim().isEmpty) return;
    setState(() {
      final index = _tickets.indexWhere((ticket) => ticket.id == id);
      _tickets[index] = (id: id, label: title.trim(), count: ticket.count);
    });
  }

  void _delete(int id) => setState(() {
    if (_tickets.length == 1) {
      _tickets = [(id: id, label: 'Ticket 1', count: 0)];
    } else {
      _tickets.removeWhere((ticket) => ticket.id == id);
      if (_active == id) _active = _tickets.first.id;
    }
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      drawer: const Drawer(
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Menú principal'),
          ),
        ),
      ),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 8,
        title: Builder(
          builder: (context) => BrandedMenuButton(
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              'Vista previa de tickets',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const TextField(
                    decoration: InputDecoration(
                      hintText: 'Buscar producto por nombre o código…',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.receipt_long_outlined,
                            size: 48,
                            color: AppColors.primary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Cada venta, en su espacio',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Prueba crear, seleccionar y gestionar los tickets de la barra inferior.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 24),
                          OutlinedButton.icon(
                            onPressed: () => setState(() {
                              for (var i = 0; i < 10; i++) {
                                final id = _nextId++;
                                _tickets.add((
                                  id: id,
                                  label: 'Ticket $id',
                                  count: i,
                                ));
                              }
                            }),
                            icon: const Icon(
                              Icons.view_week_outlined,
                              size: 18,
                            ),
                            label: const Text('Probar muchos tickets'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Text(
                    'Vista aislada · No guarda ventas ni modifica datos de empresa.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          if (wide)
            Container(
              width: 320,
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(left: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _tickets.firstWhere((ticket) => ticket.id == _active).label,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  Text('Ticket seleccionado', style: theme.textTheme.bodySmall),
                  const Divider(height: 32),
                  Text(
                    'El contenido de cada ticket permanece independiente.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
        ],
      ),
      bottomNavigationBar: SalesTicketBar(
        ticketCount: _tickets.length,
        activeTicketIndex: _tickets.indexWhere(
          (ticket) => ticket.id == _active,
        ),
        onCreateTicket: _create,
        ticketBuilder: (context, index) {
          final ticket = _tickets[index];
          return SalesTicketTab(
            key: ValueKey(ticket.id),
            label: ticket.label,
            itemCount: ticket.count,
            selected: ticket.id == _active,
            onTap: () => setState(() => _active = ticket.id),
            onRename: () => _rename(ticket.id),
            onDelete: () => _delete(ticket.id),
          );
        },
      ),
    );
  }
}
