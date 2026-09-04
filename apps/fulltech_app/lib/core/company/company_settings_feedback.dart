import '../errors/api_exception.dart';
import '../utils/app_feedback.dart';
import 'company_settings_model.dart';

enum CompanySettingsToggle {
  inventory,
  measurementUnits,
  multiWarehouse,
  taxes,
  ncf,
}

class CompanySettingsFeedback {
  const CompanySettingsFeedback._();

  static CompanySettingsToggle? firstChangedToggle(
    CompanySettings before,
    CompanySettings after,
  ) {
    if (before.inventoryEnabled != after.inventoryEnabled) {
      return CompanySettingsToggle.inventory;
    }
    if (before.measurementUnitsEnabled != after.measurementUnitsEnabled) {
      return CompanySettingsToggle.measurementUnits;
    }
    if (before.multiWarehouseEnabled != after.multiWarehouseEnabled) {
      return CompanySettingsToggle.multiWarehouse;
    }
    if (before.taxEnabled != after.taxEnabled) {
      return CompanySettingsToggle.taxes;
    }
    if (before.ncfEnabled != after.ncfEnabled) return CompanySettingsToggle.ncf;
    return null;
  }

  static bool hasCoveredToggleChange(
    CompanySettings before,
    CompanySettings after,
  ) {
    return firstChangedToggle(before, after) != null;
  }

  static AppFeedbackNotification success(
    CompanySettings before,
    CompanySettings after, {
    bool queued = false,
  }) {
    final toggle = firstChangedToggle(before, after);
    final body = queued
        ? 'El cambio quedó guardado localmente y se sincronizará cuando vuelva la conexión.'
        : 'La configuración se guardó correctamente.';

    return AppFeedbackNotification(
      title: _successTitle(toggle, before, after),
      body: body,
      kind: queued ? AppFeedbackKind.warning : AppFeedbackKind.success,
    );
  }

  static AppFeedbackNotification failure(
    CompanySettings before,
    CompanySettings attempted,
    Object error,
  ) {
    final toggle = firstChangedToggle(before, attempted);
    final rawMessage = _rawMessage(error);
    final normalized = _normalize(rawMessage);
    final known = _knownBusinessRule(toggle, normalized);
    if (known != null) return known;

    if (error is ApiException && error.isNetworkError) {
      return const AppFeedbackNotification(
        title: 'No pudimos guardar el cambio',
        body:
            'No se pudo conectar con el servidor. Revisa la conexión e inténtalo nuevamente.',
        kind: AppFeedbackKind.error,
      );
    }

    return const AppFeedbackNotification(
      title: 'No pudimos guardar el cambio',
      body:
          'Ocurrió un problema al actualizar esta configuración. Inténtalo nuevamente.',
      kind: AppFeedbackKind.error,
    );
  }

  static AppFeedbackNotification? _knownBusinessRule(
    CompanySettingsToggle? toggle,
    String normalizedMessage,
  ) {
    if (toggle == CompanySettingsToggle.measurementUnits &&
        normalizedMessage.contains('unidades de medida') &&
        normalizedMessage.contains('unidades distintas de unidad')) {
      return const AppFeedbackNotification(
        title: 'No se pueden desactivar las unidades de medida',
        body:
            'Hay productos configurados con unidades distintas de Unidad. Cambia esos productos a Unidad y vuelve a intentarlo.',
        kind: AppFeedbackKind.warning,
      );
    }

    if (toggle == CompanySettingsToggle.multiWarehouse &&
        normalizedMessage.contains('multiples almacenes') &&
        normalizedMessage.contains('stock distribuido') &&
        normalizedMessage.contains('mas de un almacen activo')) {
      return const AppFeedbackNotification(
        title: 'No se pueden desactivar los múltiples almacenes',
        body:
            'Hay productos con stock distribuido en más de un almacén activo. Deja cada producto con stock en un solo almacén y vuelve a intentarlo.',
        kind: AppFeedbackKind.warning,
      );
    }

    if (toggle == CompanySettingsToggle.taxes &&
        normalizedMessage.contains('impuesto predeterminado invalido')) {
      return const AppFeedbackNotification(
        title: 'No se pudo activar impuestos',
        body:
            'El impuesto predeterminado no está disponible. Revisa la configuración de impuestos y vuelve a intentarlo.',
        kind: AppFeedbackKind.warning,
      );
    }

    return null;
  }

  static String _successTitle(
    CompanySettingsToggle? toggle,
    CompanySettings before,
    CompanySettings after,
  ) {
    switch (toggle) {
      case CompanySettingsToggle.measurementUnits:
        return after.measurementUnitsEnabled
            ? 'Unidades de medida activadas'
            : 'Unidades de medida desactivadas';
      case CompanySettingsToggle.inventory:
        return after.inventoryEnabled
            ? 'Control de inventario activado'
            : 'Control de inventario desactivado';
      case CompanySettingsToggle.multiWarehouse:
        return after.multiWarehouseEnabled
            ? 'Múltiples almacenes activados'
            : 'Múltiples almacenes desactivados';
      case CompanySettingsToggle.taxes:
        return after.taxEnabled
            ? 'Impuestos activados'
            : 'Impuestos desactivados';
      case CompanySettingsToggle.ncf:
        return after.ncfEnabled
            ? 'Comprobantes fiscales activados'
            : 'Comprobantes fiscales desactivados';
      case null:
        return 'Configuración guardada';
    }
  }

  static String _rawMessage(Object error) {
    if (error is ApiException) return error.message;
    return error.toString();
  }

  static String _normalize(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u');
  }
}
