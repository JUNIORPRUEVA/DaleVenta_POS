import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/auth_provider.dart';
import 'pending_sync_action.dart';

/// In-memory handoff to the existing POS. Never sends a sale or copies its ID.
final recoverySaleDraftProvider = StateProvider<PendingSyncAction?>((ref) {
  ref.watch(authStateProvider.select((s) => (s.user?.id, s.user?.companyId, s.user?.role)));
  return null;
});

bool recoverySaleItemsAreValid(PendingSyncAction action) {
  final raw = action.payload['items'];
  return raw is List && raw.isNotEmpty && raw.every((entry) {
    if (entry is! Map) return false;
    final quantity = num.tryParse('${entry['qty']}');
    final price = num.tryParse('${entry['priceSoldUnit']}');
    return quantity != null && quantity.isFinite && quantity > 0 &&
        price != null && price.isFinite && price >= 0;
  });
}
