import 'package:flutter_test/flutter_test.dart';

import 'package:daleventa_pos/features/contabilidad/data/contabilidad_repository.dart';

void main() {
  group('NcfSequenceModel.fromJson', () {
    test('parses camelCase response from GET /ncf/sequences', () {
      final model = NcfSequenceModel.fromJson(const {
        'id': 'seq-1',
        'voucherType': 'B01',
        'prefix': 'B01',
        'startNumber': 1,
        'nextNumber': 42,
        'endNumber': 100000,
        'validUntil': '2026-12-31T23:59:59Z',
        'active': true,
        'status': 'ACTIVE',
      });

      expect(model.id, 'seq-1');
      expect(model.voucherType, 'B01');
      expect(model.prefix, 'B01');
      expect(model.startNumber, 1);
      expect(model.nextNumber, 42);
      expect(model.endNumber, 100000);
      expect(model.validUntil, DateTime.utc(2026, 12, 31, 23, 59, 59));
      expect(model.active, isTrue);
      expect(model.status, 'ACTIVE');
    });

    test('parses snake_case response (database row) with status fallback', () {
      final model = NcfSequenceModel.fromJson(const {
        'id': 'seq-2',
        'voucher_type': 'B02',
        'prefix': 'B02',
        'start_number': 1,
        'next_number': 5,
        'end_number': 1000,
        'valid_until': null,
        'active': false,
      });

      expect(model.voucherType, 'B02');
      expect(model.startNumber, 1);
      expect(model.nextNumber, 5);
      expect(model.endNumber, 1000);
      expect(model.validUntil, isNull);
      expect(model.active, isFalse);
      expect(model.status, isEmpty);
    });

    test('missing numbers fall back safely', () {
      final model = NcfSequenceModel.fromJson(const {
        'id': 'seq-3',
        'voucherType': 'B01',
        'prefix': 'B01',
      });

      expect(model.startNumber, 1);
      expect(model.nextNumber, 1);
      expect(model.endNumber, 0);
    });
  });

  group('NcfSequenceModel computed fields', () {
    test('remaining counts available numbers from next to end (inclusive)', () {
      final model = NcfSequenceModel.fromJson(const {
        'id': 'seq-4',
        'voucherType': 'B01',
        'prefix': 'B01',
        'startNumber': 1,
        'nextNumber': 42,
        'endNumber': 100,
        'active': true,
        'status': 'ACTIVE',
      });

      expect(model.remaining, 59);
      expect(model.possibleNextNcf, 'B0100000042');
    });

    test('remaining never goes negative when sequence is exhausted', () {
      final model = NcfSequenceModel.fromJson(const {
        'id': 'seq-5',
        'voucherType': 'B02',
        'prefix': 'B02',
        'startNumber': 1,
        'nextNumber': 101,
        'endNumber': 100,
        'active': true,
        'status': 'EXHAUSTED',
      });

      expect(model.remaining, 0);
      expect(model.possibleNextNcf, 'B0200000101');
    });

    test('possibleNextNcf pads the serial to 8 digits', () {
      final model = NcfSequenceModel.fromJson(const {
        'id': 'seq-6',
        'voucherType': 'B01',
        'prefix': 'B01',
        'startNumber': 1,
        'nextNumber': 7,
        'endNumber': 100000,
        'active': true,
        'status': 'ACTIVE',
      });

      expect(model.possibleNextNcf, 'B0100000007');
    });
  });
}
