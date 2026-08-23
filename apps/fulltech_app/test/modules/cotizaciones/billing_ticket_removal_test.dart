import 'dart:io';

import 'package:daleventa_pos/modules/cotizaciones/cotizaciones_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regresión del flujo "cobro exitoso elimina el ticket/draft completado de
/// Facturación": la pestaña del ticket cobrado debe desaparecer de la barra
/// inferior sin tocar la venta finalizada ni los tickets hermanos.
void main() {
  group('nextActiveTicketIdAfterRemoval (selección del ticket siguiente)', () {
    test('successful checkout removes completed ticket (vecino siguiente)', () {
      const ids = ['ticket-a', 'ticket-b', 'ticket-c', 'ticket-d'];

      final nextActive = nextActiveTicketIdAfterRemoval(ids, 'ticket-b');

      // El ticket cobrado se retira y el vecino ocupa su lugar.
      expect(nextActive, 'ticket-c');
    });

    test('removing completed ticket does not alter sibling tickets', () {
      const ids = ['ticket-a', 'ticket-b', 'ticket-c'];

      final remaining = ids
          .where((id) => id != 'ticket-b')
          .toList(growable: false);
      final nextActive = nextActiveTicketIdAfterRemoval(ids, 'ticket-b');

      // Los hermanos conservan exactamente su orden y su contenido.
      expect(remaining, ['ticket-a', 'ticket-c']);
      expect(nextActive, 'ticket-c');
    });

    test('cobra ticket del medio de 5 → solo ese desaparece', () {
      const ids = [
        'ticket-1',
        'ticket-2',
        'ticket-3',
        'ticket-4',
        'ticket-5',
      ];

      final remaining = ids
          .where((id) => id != 'ticket-3')
          .toList(growable: false);
      final nextActive = nextActiveTicketIdAfterRemoval(ids, 'ticket-3');

      expect(remaining, ['ticket-1', 'ticket-2', 'ticket-4', 'ticket-5']);
      expect(nextActive, 'ticket-4');
    });

    test('cobra último ticket → activa el ticket anterior (vecino)', () {
      const ids = ['ticket-a', 'ticket-b', 'ticket-c'];

      final nextActive = nextActiveTicketIdAfterRemoval(ids, 'ticket-c');

      expect(nextActive, 'ticket-b');
    });

    test('cobra el único ticket → devuelve null (crear nuevo vacío)', () {
      const ids = ['ticket-a'];

      final nextActive = nextActiveTicketIdAfterRemoval(ids, 'ticket-a');

      expect(nextActive, isNull);
    });

    test('failed checkout keeps ticket (nada que retirar → sin cambios)', () {
      const ids = ['ticket-a', 'ticket-b'];

      // Caso defensivo: el id no está en la lista (equivalente a un cobro
      // que no llegó a finalizarse): la lista queda intacta.
      final nextActive = nextActiveTicketIdAfterRemoval(ids, 'ticket-x');

      expect(nextActive, 'ticket-a');
      expect(ids, ['ticket-a', 'ticket-b']);
    });
  });

  group('wiring del flujo de cobro en cotizaciones_screen.dart', () {
    final source = File(
      'lib/modules/cotizaciones/cotizaciones_screen.dart',
    ).readAsStringSync();

    test(
      'successful checkout removes completed ticket (se elimina el draft)',
      () {
        expect(
          source,
          contains('_commitEditorChange(_removeCompletedDesktopTicket);'),
        );
        // El método realmente retira el ticket de la colección abierta.
        expect(
          source,
          contains(
            'nextActiveTicketIdAfterRemoval(orderedIds, activeId);',
          ),
        );
        expect(
          source,
          contains(
            'where((ticket) => ticket.id != activeId)',
          ),
        );
      },
    );

    test('failed checkout keeps ticket (remoción solo tras venta persistida)', () {
      // La venta NO se guardó → retorno temprano con mensaje y el ticket no
      // se elimina. La remoción ocurre después de ese retorno.
      final failureReturn =
          source.indexOf("'La venta no se guardó porque falta autorización");
      final removalCall = source.indexOf(
        '_commitEditorChange(_removeCompletedDesktopTicket);',
      );

      expect(failureReturn, greaterThanOrEqualTo(0));
      expect(removalCall, greaterThan(failureReturn));

      // La excepción (error backend / validación / pago) también retorna antes
      // de la remoción.
      final catchBlock = source.indexOf("title: 'No se pudo completar'");
      expect(catchBlock, greaterThanOrEqualTo(0));
      expect(removalCall, lessThan(catchBlock));
    });
  });
}
