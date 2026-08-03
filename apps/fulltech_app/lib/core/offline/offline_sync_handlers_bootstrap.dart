import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/catalogo/data/catalog_repository.dart';
import '../../modules/cash/cash_repository.dart';
import '../../modules/clientes/data/clientes_repository.dart';
import '../../modules/cotizaciones/data/cotizaciones_repository.dart';
import '../../modules/manual_interno/company_manual_repository.dart';
import '../../modules/ventas/data/ventas_repository.dart';
import '../company/company_settings_repository.dart';

final offlineSyncHandlersBootstrapProvider = Provider<void>((ref) {
  ref.read(catalogRepositoryProvider);
  ref.read(cashRepositoryProvider);
  ref.read(ventasRepositoryProvider);
  ref.read(clientesRepositoryProvider);
  ref.read(cotizacionesRepositoryProvider);
  ref.read(companyManualRepositoryProvider);
  ref.read(companySettingsRepositoryProvider);
});
