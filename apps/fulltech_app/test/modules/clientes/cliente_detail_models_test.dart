import 'package:flutter_test/flutter_test.dart';
import 'package:fulltech_app/modules/clientes/client_location_utils.dart';
import 'package:fulltech_app/modules/clientes/cliente_model.dart';
import 'package:fulltech_app/modules/clientes/cliente_profile_model.dart';
import 'package:fulltech_app/modules/clientes/cliente_timeline_model.dart';

void main() {
  group('ClienteModel.fromJson', () {
    test('drops out-of-range coordinates from backend payloads', () {
      final cliente = ClienteModel.fromJson({
        'id': 'client-1',
        'ownerId': 'owner-1',
        'nombre': 'Cliente demo',
        'telefono': '8095550101',
        'latitude': 145.8,
        'longitude': -190.2,
      });

      expect(cliente.latitude, isNull);
      expect(cliente.longitude, isNull);
    });
  });

  group('ClienteProfileClient.fromJson', () {
    test('drops invalid coordinates from profile payloads', () {
      final profileClient = ClienteProfileClient.fromJson({
        'id': 'client-1',
        'nombre': 'Cliente demo',
        'telefono': '8095550101',
        'phoneNormalized': '8095550101',
        'latitude': -91,
        'longitude': 181,
      });

      expect(profileClient.latitude, isNull);
      expect(profileClient.longitude, isNull);
    });
  });

  group('ClienteProfileMetrics.fromJson', () {
    test('parses decimal totals serialized as strings', () {
      final metrics = ClienteProfileMetrics.fromJson({
        'salesCount': 0,
        'servicesCount': 1,
        'serviceOrdersCount': 1,
        'legacyServicesCount': 0,
        'serviceReferencesCount': 2,
        'cotizacionesCount': 1,
        'cotizacionesTotal': '17900',
      });

      expect(metrics.cotizacionesTotal, 17900);
    });
  });

  group('ClienteTimelineEvent.fromJson', () {
    test('parses amount serialized as string', () {
      final event = ClienteTimelineEvent.fromJson({
        'eventType': 'cotizacion',
        'eventId': 'quote-1',
        'at': '2026-04-08T18:20:01.710Z',
        'title': 'Cotización',
        'amount': '17900',
      });

      expect(event.amount, 17900);
    });
  });

  group('ClientLocationPreview', () {
    test('rejects invalid coordinate pairs', () {
      const preview = ClientLocationPreview(latitude: 91, longitude: -70.1);

      expect(preview.hasCoordinates, isFalse);
    });

    test('accepts valid coordinate pairs', () {
      const preview = ClientLocationPreview(
        latitude: 18.4861,
        longitude: -69.9312,
      );

      expect(preview.hasCoordinates, isTrue);
    });
  });

  group('parseClientLocationPreview', () {
    test('ignores out-of-range coordinates found in url', () {
      final preview = parseClientLocationPreview(
        'https://www.google.com/maps?q=120.123,-200.456',
      );

      expect(preview.hasCoordinates, isFalse);
      expect(
        preview.resolvedUrl,
        'https://www.google.com/maps?q=120.123,-200.456',
      );
    });

    test('extracts valid coordinates from url', () {
      final preview = parseClientLocationPreview(
        'https://www.google.com/maps?q=18.486100,-69.931200',
      );

      expect(preview.hasCoordinates, isTrue);
      expect(preview.latitude, closeTo(18.4861, 0.000001));
      expect(preview.longitude, closeTo(-69.9312, 0.000001));
    });
  });
}
