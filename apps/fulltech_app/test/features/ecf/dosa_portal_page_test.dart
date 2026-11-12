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
      // Lienzo de altura fija con el estado superpuesto: sin saltos por avisos.
      expect(html, contains('#marco{position:relative;flex:1;min-height:0'));
      expect(html, contains('.estado{position:absolute;inset:0'));
      expect(html, contains('@media (max-width:720px)'));
      expect(html, contains('ajustarAltura'));
    });

    test('regresa a Preparación sin cerrar la sesión de la app', () {
      // Flecha visible y botón de texto con el mismo destino.
      expect(html, contains('id="volver"'));
      expect(html, contains('id="volver-texto"'));
      expect(html, contains("var RUTA_FULLPOS = '/ecf';"));
      expect(html, contains('window.location.assign(RUTA_FULLPOS)'));
      // Solo se revoca la sesión temporal del portal.
      expect(html, contains("method: 'DELETE'"));
      expect(html, isNot(contains('sessionStorage.clear()')));
      expect(html, isNot(contains('localStorage.clear()')));
    });

    test('el botón Atrás del navegador no deja un ticket caducado', () {
      // El ticket sale de la URL antes de canjearlo y la vuelta desde caché
      // vuelve a montar el asistente si la sesión del portal sigue viva.
      expect(html, contains("addEventListener('pageshow'"));
      expect(html, contains('evento.persisted'));
      expect(html, contains("searchParams.delete('ticket')"));
    });

    test('transición discreta, nunca pantalla intermedia', () {
      expect(html, contains('id="estado"'));
      expect(html, contains('Cargando el asistente oficial'));
      expect(html, contains('transition:opacity .18s'));
      // Un solo punto de montaje y ni un botón que lo abra.
      expect(html, isNot(contains('id="iniciar"')));
      expect(html, isNot(contains('Continuar certificación')));
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
