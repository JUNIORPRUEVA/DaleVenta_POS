import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Local identity of an unresolved manual preparation. It stores only an
/// operation UUID and a digest, scoped to company, user and original document.
class EcfPendingCreditRequest {
  EcfPendingCreditRequest(this.preferences);
  final SharedPreferences preferences;
  String _key(String scope) => 'ecf.credit.pending.v1:$scope';

  Future<String> obtain(String scope, Map<String, dynamic> payload) async {
    final digest = sha256.convert(utf8.encode(jsonEncode(payload))).toString();
    final stored = preferences.getString(_key(scope));
    if (stored != null) {
      final existing = jsonDecode(stored) as Map;
      if (existing['digest'] != digest) {
        throw StateError(
          'Hay una preparación sin confirmar. Revisa su resultado antes de cambiar la nota.',
        );
      }
      return existing['id'] as String;
    }
    final id = const Uuid().v4();
    if (!await preferences.setString(
      _key(scope),
      jsonEncode({'id': id, 'digest': digest}),
    )) {
      throw StateError(
        'No se pudo conservar la identidad de la nota. No se envió la solicitud.',
      );
    }
    return id;
  }

  Future<void> complete(String scope, String id) async {
    final stored = preferences.getString(_key(scope));
    if (stored != null && (jsonDecode(stored) as Map)['id'] == id) {
      if (!await preferences.remove(_key(scope))) {
        throw StateError(
          'La nota respondió, pero su identidad local requiere revisión.',
        );
      }
    }
  }
}
