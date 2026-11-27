import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daleventa_pos/core/guardian/guardian_event.dart';
import 'package:daleventa_pos/core/guardian/guardian_web_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  GuardianEvent event(String id, String company) => GuardianEvent(
    eventId: id,
    severity: 'SEV2',
    module: 'sales',
    operation: 'save',
    occurredAt: DateTime.now(),
    context: {'_guardianCompanyId': company},
  );
  test(
    'concurrent web writes retain every severe event and isolate company selection',
    () async {
      final store = WebGuardianStore(maxPersistedEvents: 2);
      await Future.wait([
        store.upsert(event('one', 'a')),
        store.upsert(event('two', 'b')),
        store.upsert(event('three', 'a')),
      ]);
      expect(await store.count(), 3);
      expect(
        (await store.dueEvents(limit: 1, companyId: 'b')).single.eventId,
        'two',
      );
      await Future.wait([
        store.removeAll(['one']),
        store.upsert(event('four', 'b')),
      ]);
      expect(await store.count(), 3);
      final reopened = WebGuardianStore();
      expect(
        (await reopened.dueEvents(limit: 10, companyId: 'a')).single.eventId,
        'three',
      );
    },
  );
}
