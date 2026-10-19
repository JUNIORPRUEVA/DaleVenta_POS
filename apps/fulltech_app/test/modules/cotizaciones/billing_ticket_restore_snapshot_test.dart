import 'package:daleventa_pos/modules/cotizaciones/cotizaciones_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('selectBillingDraftSnapshotForRestore', () {
    test('prefiere borrador local con carrito frente a remoto vacio', () {
      final remote = {
        'activeId': 'remote-ticket',
        'tickets': [
          {
            'id': 'remote-ticket',
            'title': 'Ticket 1',
            'items': const [],
            'selectedClientName': 'Sin cliente',
          },
        ],
      };
      final local = {
        'activeId': 'local-ticket',
        'updatedAt': '2026-10-13T20:00:00.000Z',
        'tickets': [
          {
            'id': 'local-ticket',
            'title': 'Ticket 1',
            'items': [
              {'id': 'p-1', 'name': 'Producto UAT', 'qty': 2},
            ],
            'selectedClientId': 'client-1',
            'selectedClientName': 'Cliente UAT',
          },
        ],
      };

      final selected = selectBillingDraftSnapshotForRestore(
        remote: remote,
        local: local,
      );

      expect(selected, same(local));
    });

    test(
      'conserva varios tickets locales cuando el remoto no tiene contenido',
      () {
        final remote = {
          'activeId': 'remote-ticket',
          'tickets': [
            {'id': 'remote-ticket', 'items': const []},
          ],
        };
        final local = {
          'activeId': 'ticket-2',
          'updatedAt': '2026-10-13T20:05:00.000Z',
          'tickets': [
            {
              'id': 'ticket-1',
              'items': [
                {'id': 'p-1', 'qty': 1},
              ],
            },
            {
              'id': 'ticket-2',
              'items': [
                {'id': 'p-2', 'qty': 3},
              ],
              'selectedClientName': 'Cliente 2',
            },
          ],
        };

        final selected = selectBillingDraftSnapshotForRestore(
          remote: remote,
          local: local,
        );

        expect(selected, same(local));
        expect(selected?['tickets'], hasLength(2));
        expect(selected?['activeId'], 'ticket-2');
      },
    );

    test('prefiere remoto cuando trae mas contenido real que local', () {
      final remote = {
        'activeId': 'remote-ticket',
        'tickets': [
          {
            'id': 'remote-ticket',
            'items': [
              {'id': 'p-1', 'qty': 1},
              {'id': 'p-2', 'qty': 1},
            ],
          },
        ],
      };
      final local = {
        'activeId': 'local-ticket',
        'updatedAt': '2026-10-13T20:10:00.000Z',
        'tickets': [
          {'id': 'local-ticket', 'items': const []},
        ],
      };

      final selected = selectBillingDraftSnapshotForRestore(
        remote: remote,
        local: local,
      );

      expect(selected, same(remote));
    });

    test('si ambos tienen igual contenido usa el updatedAt mas reciente', () {
      final remote = {
        'activeId': 'remote-ticket',
        'updatedAt': '2026-10-13T20:00:00.000Z',
        'tickets': [
          {
            'id': 'remote-ticket',
            'items': [
              {'id': 'p-1', 'qty': 1},
            ],
          },
        ],
      };
      final local = {
        'activeId': 'local-ticket',
        'updatedAt': '2026-10-13T20:15:00.000Z',
        'tickets': [
          {
            'id': 'local-ticket',
            'items': [
              {'id': 'p-1', 'qty': 1},
            ],
          },
        ],
      };

      final selected = selectBillingDraftSnapshotForRestore(
        remote: remote,
        local: local,
      );

      expect(selected, same(local));
    });
  });
}
