import 'package:daleventa_pos/features/ecf/data/ecf_pending_credit_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'unknown preparation keeps its UUID across store recreation and owner scope',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final first = EcfPendingCreditRequest(prefs);
      const body = {'reason': 'Devolución', 'quantity': '1'};
      final id = await first.obtain('company-a:user-a:original-a', body);
      final reopened = EcfPendingCreditRequest(prefs);
      expect(await reopened.obtain('company-a:user-a:original-a', body), id);
      expect(
        await reopened.obtain('company-b:user-a:original-a', body),
        isNot(id),
      );
      expect(
        await reopened.obtain('company-a:user-b:original-a', body),
        isNot(id),
      );
    },
  );
  test(
    'a changed request cannot replace an unresolved operation; a final result permits a new one',
    () async {
      final store = EcfPendingCreditRequest(
        await SharedPreferences.getInstance(),
      );
      final id = await store.obtain('scope', {'quantity': '1'});
      await expectLater(
        store.obtain('scope', {'quantity': '2'}),
        throwsStateError,
      );
      await store.complete('scope', 'another-operation');
      expect(await store.obtain('scope', {'quantity': '1'}), id);
      await store.complete('scope', id);
      expect(await store.obtain('scope', {'quantity': '2'}), isNot(id));
    },
  );
}
