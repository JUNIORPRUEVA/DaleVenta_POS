import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// El portal de certificación es una **página estática** que viaja dentro del
/// build de Flutter (`web/ecf/certificacion/index.html`) y se publica en el
/// dominio autorizado por DOSA. No la cubre ningún test de widgets, así que se
/// fija aquí el contrato de la experiencia: un solo gesto del usuario y el
/// asistente visible, sin pantalla intermedia ni ventanas nuevas.
void main() {
  late String html;

  setUpAll(() {
    final file = File('web/ecf/certificacion/index.html');
    expect(
      file.existsSync(),
      isTrue,
      reason: 'El portal debe viajar dentro del build de Flutter.',
    );
    html = file.readAsStringSync();
  });

  group('portal de certificación: experiencia', () {
    test('no muestra la pantalla intermedia del recorrido', () {
      expect(html, isNot(contains('Tu recorrido')));
      expect(html, isNot(contains('Continuar certificación')));
      expect(html, isNot(contains('id="resumen"')));
      expect(html, isNot(contains('id="paso-solicitud"')));
    });

    test('monta el componente oficial sin clic adicional', () {
      // Hay un único punto de montaje y no existe el botón que lo abría antes.
      expect(html, contains('<dosa-cert-wizard'));
      expect(html, isNot(contains("id=\"iniciar\"")));
      // Se monta justo después de canjear el ticket.
      expect(
        html,
        contains('canjearTicket(ticket).then(function (ok)'),
      );
      expect(html, contains('if (ok) montarAsistente();'));
    });

    test('conserva la validación del ticket de un solo uso', () {
      expect(html, contains('/ecf/certification-portal/sessions'));
      expect(html, contains('ALREADY_USED'));
      expect(html, contains('EXPIRED'));
      expect(html, contains('PILOT'));
      // El ticket se borra de la barra de direcciones.
      expect(html, contains('searchParams.delete(\'ticket\')'));
      expect(html, contains('replaceState'));
    });

    test('no abre ventanas nuevas', () {
      expect(html, isNot(contains('window.open')));
      expect(html, isNot(contains('target="_blank"')));
      expect(html, contains('window.location.assign'));
    });

    test('encabezado propio de FullPOS con la empresa y la vuelta', () {
      expect(html, contains('FullPOS Cloud'));
      expect(html, contains('id="empresa-nombre"'));
      expect(html, contains('Volver a FullPOS'));
      // DOSA sigue identificado donde corresponde, sin tocar su contenido.
      expect(html, contains('DGII vía DOSA'));
    });

    test('sin doble barra de desplazamiento y adaptable', () {
      expect(html, contains('overflow:hidden'));
      expect(html, contains('#marco{flex:1;min-height:0;overflow:hidden'));
      expect(html, contains('@media (max-width:720px)'));
      expect(html, contains('ajustarAltura'));
    });

    test('conserva los marcadores que rellena el build', () {
      // Sin estos dos marcadores la imagen no puede publicar el portal, y el
      // Dockerfile falla cerrado a propósito.
      expect(html, contains('__API_BASE__'));
      expect(html, contains('__DOSA_PUBLISHABLE_KEY__'));
      expect(html, contains('https://dosasystem.com/static/embed/dosa-cert.js'));
    });
  });
}
