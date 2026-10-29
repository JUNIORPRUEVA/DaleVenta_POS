import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/catalogo/data/catalog_repository.dart';
import '../../modules/cash/cash_repository.dart';
import '../../modules/clientes/data/clientes_repository.dart';
import '../../modules/cotizaciones/data/cotizaciones_repository.dart';
import '../../modules/manual_interno/company_manual_repository.dart';
import '../../modules/ventas/data/ventas_repository.dart';
import '../company/company_settings_repository.dart';
import 'sale_attempt_declaration_providers.dart';

final offlineSyncHandlersBootstrapProvider = Provider<void>((ref) {
  ref.read(catalogRepositoryProvider);
  ref.read(cashRepositoryProvider);
  ref.read(ventasRepositoryProvider);
  ref.read(clientesRepositoryProvider);
  ref.read(cotizacionesRepositoryProvider);
  ref.read(companyManualRepositoryProvider);
  ref.read(companySettingsRepositoryProvider).registerSyncHandlers();
  // Declaraciones de cobro recibido: viajan por la misma cola que el resto.
  ref.read(saleAttemptDeclarationSyncHandlersProvider);
  // Si una declaración quedó bloqueada por sesión caducada, se reintenta al
  // volver a entrar.
  ref.read(saleAttemptDeclarationAuthRecoveryProvider);
});
