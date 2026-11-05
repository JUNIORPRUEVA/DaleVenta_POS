import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_permissions.dart';
import '../../../core/auth/auth_provider.dart';
import '../../../core/company/company_settings_repository.dart';
import '../data/ecf_repository.dart';
import 'dosa_assistant_config.dart';
import 'dosa_assistant_events.dart';
import 'dosa_assistant_launcher.dart';
import 'dosa_assistant_panel.dart';
import 'dosa_assistant_session.dart';
import 'dosa_certification_intent_api.dart';
import 'dosa_certification_session_api.dart';
import 'dosa_portal_launcher.dart';

/// Inserta el panel del asistente DOSA dentro del expediente existente.
///
/// Es el único punto que lee la identidad fiscal de la empresa: el RNC sale de
/// la configuración confirmada por el backend, nunca de un campo del asistente.
///
/// En Seguimiento, la bandera del embed apagada devuelve `SizedBox.shrink()`.
/// En Preparación, `portalOnly` usa el portal seguro y la elegibilidad del
/// backend sin montar el embed de Flutter.
///
/// **Abrir el expediente no registra nada.** Al montarse solo se consulta el
/// estado (lectura). La intención se registra únicamente cuando un administrador
/// autorizado pulsa «Iniciar postulación electrónica»; con ese mismo clic se
/// abre el portal oficial, sin pedir un segundo toque. El clic autoriza abrir
/// el asistente, no crear una postulación externa ni pulsar «Conectar» por el
/// usuario.
class DosaAssistantSection extends ConsumerStatefulWidget {
  const DosaAssistantSection({
    super.key,
    this.postulationExternalId,
    this.phase,
    this.onResume,
    this.onRefresh,
    this.config,
    this.portalOnly = false,
    this.onSessionOpened,
  });

  /// Referencia externa del expediente, si ya existe.
  final String? postulationExternalId;

  /// Fase observada. Por defecto se deduce de si hay expediente externo.
  final DosaAssistantPhase? phase;

  final VoidCallback? onResume;

  /// Recarga la pantalla que contiene la sección tras un evento del componente.
  final VoidCallback? onRefresh;

  /// Solo para pruebas; en la app se lee del build.
  final DosaAssistantConfig? config;

  /// En Preparación usa el portal existente sin depender del embed de Flutter.
  final bool portalOnly;

  /// Se invoca solo cuando el portal oficial se abrió correctamente.
  final VoidCallback? onSessionOpened;

  @override
  ConsumerState<DosaAssistantSection> createState() =>
      _DosaAssistantSectionState();
}

class _DosaAssistantSectionState extends ConsumerState<DosaAssistantSection> {
  /// Solo pasa a `true` por acción explícita del administrador.
  bool _requested = false;

  /// Evita dobles peticiones de ticket mientras se abre el portal.
  bool _openingPortal = false;

  /// El portal se abre una única vez por registro, nunca en bucle ni al
  /// volver a construir la sección.
  bool _autoOpened = false;

  ///
  /// Pide un ticket de un solo uso y abre el portal alojado en el dominio
  /// autorizado. El componente oficial NO se monta aquí: en Web el iframe
  /// sería bloqueado por la CSP del proveedor y en movil/Windows no hay origen
  /// autorizado. Por eso la acción siempre es "abrir el portal".
  Future<void> _openPortal() async {
    if (_openingPortal) return;
    final user = ref.read(authStateProvider).user;
    final companyId = user?.companyId?.trim() ?? '';
    if (companyId.isEmpty ||
        !hasUserPermission(user, AppPermission.manageEcfOnboarding)) {
      return;
    }
    setState(() => _openingPortal = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      // 1) Apertura AUTOMÁTICA: el backend toma el RNC del expediente y el
      // correo ya guardado, y devuelve el enlace de sesión de DOSA. El cliente
      // no vuelve a escribir esos datos.
      try {
        final session = await ref
            .read(dosaCertificationSessionApiProvider)
            .open();
        if (!mounted) return;
        final currentUser = ref.read(authStateProvider).user;
        // El enlace debe pertenecer a la empresa autenticada: se comprueba el
        // `companyId` devuelto contra el del usuario actual.
        if (currentUser?.companyId?.trim() != companyId ||
            session.companyId.trim() != companyId ||
            !hasUserPermission(
              currentUser,
              AppPermission.manageEcfOnboarding,
            )) {
          return;
        }
        if (session.sessionUrl.trim().isEmpty) {
          messenger?.showSnackBar(
            const SnackBar(
              content: Text(
                'El servidor no devolvió un enlace de sesión válido.',
              ),
            ),
          );
          return;
        }
        final opened = await openDosaPortal(session.sessionUrl);
        if (opened) {
          widget.onSessionOpened?.call();
        } else {
          messenger?.showSnackBar(
            const SnackBar(
              content: Text(
                'No se pudo abrir el navegador. Copia el enlace desde el portal.',
              ),
            ),
          );
        }
        return;
      } on DosaCertificationSessionException catch (error) {
        // Un error definitivo (correo, RNC, incierto) se explica y NO se
        // reintenta. Solo si la API aún no está habilitada se usa el asistente
        // actual como alternativa segura.
        if (!error.canFallBackToAssistant) {
          messenger?.showSnackBar(SnackBar(content: Text(error.message)));
          return;
        }
      }

      // 2) Alternativa segura: portal existente mientras la API de sesiones
      // todavía no está habilitada.
      final api = ref.read(dosaPortalApiProvider);
      final ticket = await api.requestTicket();
      if (!mounted) return;
      final currentUser = ref.read(authStateProvider).user;
      if (currentUser?.companyId?.trim() != companyId ||
          !hasUserPermission(currentUser, AppPermission.manageEcfOnboarding)) {
        return;
      }
      final opened = await openDosaPortal(ticket.url);
      if (opened) {
        widget.onSessionOpened?.call();
      } else {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo abrir el navegador. Copia el enlace desde el portal.',
            ),
          ),
        );
      }
    } on DosaPortalException catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _openingPortal = false);
    }
  }

  /// Un solo clic: registrada la intención, se abre el portal sin pedir otro
  /// toque. Solo en Preparación (`portalOnly`); en Seguimiento la apertura
  /// sigue siendo manual.
  ///
  /// Abrir el portal no pulsa «Conectar» por el usuario. Si la API oficial de
  /// sesiones está habilitada, el backend puede crear o reutilizar la sesión
  /// del expediente; si no, se usa el ticket de un solo uso como fallback.
  void _scheduleAutoOpen() {
    if (!widget.portalOnly || _autoOpened) return;
    _autoOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openPortal();
    });
  }

  @override
  Widget build(BuildContext context) {
    final resolved = widget.config ?? DosaAssistantConfig.fromEnvironment();
    if (!widget.portalOnly && !resolved.enabled) return const SizedBox.shrink();

    final user = ref.watch(authStateProvider).user;
    final companyId = user?.companyId?.trim() ?? '';
    final taxId =
        ref.watch(companySettingsProvider).valueOrNull?.rnc.trim() ?? '';
    // Preparar exige el permiso administrativo, igual que en el backend.
    final canManage = hasUserPermission(
      user,
      AppPermission.manageEcfOnboarding,
    );
    if (widget.portalOnly) {
      if (companyId.isEmpty || !canManage) return const SizedBox.shrink();
      final eligibility = ref.watch(dosaPortalEligibilityProvider);
      if (eligibility.isLoading ||
          eligibility.hasError ||
          eligibility.valueOrNull != true) {
        return const SizedBox.shrink();
      }
    }

    final binding = DosaAssistantBinding(
      companyId: companyId,
      taxId: taxId,
      postulationExternalId: widget.postulationExternalId,
    );

    // Lectura del estado interno. Consultar no crea ni activa nada.
    return ref
        .watch(dosaIntentStateProvider)
        .when(
          loading: () => const _DosaIntentGate(
            icon: Icons.hourglass_top,
            message: 'Consultando la preparación de facturación electrónica...',
          ),
          error: (error, _) => _DosaIntentGate(
            icon: Icons.cloud_off,
            message: 'No se pudo consultar el estado de la preparación.',
            onRetry: () => ref.invalidate(dosaIntentStateProvider),
          ),
          data: (value) {
            // Solo una intención atribuida a DOSA ofrece el portal sin registrar otra.
            if (value.sessionId != null) {
              if (value.provider != 'DOSA') {
                return const _DosaIntentGate(
                  icon: Icons.info_outline,
                  message:
                      'Revisa el intento de certificación existente con un '
                      'administrador antes de continuar.',
                );
              }
              return _panel(
                resolved,
                binding,
                attemptNo: value.sessionAttemptNo ?? 0,
                created: false,
                canManage: canManage,
                intentId: value.sessionId,
                // Una sesión ya emitida y vigente se puede reanudar: no se exige
                // una nueva autorización solo para volver a abrirla.
                historicalReviewRequired:
                    value.historicalReviewRequired && !value.sessionReusable,
              );
            }

            // El backend explica qué falta (identidad fiscal), no el interruptor
            // de emisión: preparar no depende de tener e-CF ya activado.
            if (!value.canRegister) {
              final reason = value.blockingReasons.isEmpty
                  ? null
                  : value.blockingReasons.first;
              return _DosaIntentGate(
                icon: Icons.block,
                message: reason == null
                    ? 'La preparación no puede iniciarse todavía.'
                    : dosaIntentReasonMessage(reason),
                detail: reason,
              );
            }

            if (!canManage) {
              return const _DosaIntentGate(
                icon: Icons.lock_outline,
                message:
                    'Solo un administrador autorizado puede preparar la '
                    'certificación de esta empresa.',
              );
            }

            if (!_requested) {
              return _DosaPrepareCard(
                portalOnly: widget.portalOnly,
                onPrepare: () => setState(() => _requested = true),
              );
            }

            // Acción voluntaria confirmada: ahora sí se registra la intención.
            return ref
                .watch(dosaIntentRegistrationProvider(taxId))
                .when(
                  loading: () => const _DosaIntentGate(
                    icon: Icons.hourglass_top,
                    message:
                        'Registrando la preparación de facturación electrónica...',
                  ),
                  error: (error, _) => _DosaIntentGate(
                    icon: Icons.block,
                    message: error is DosaIntentException
                        ? error.message
                        : 'No se pudo registrar la intención de certificación.',
                    // Solo se muestra como detalle un código propio del dominio:
                    // los errores de transporte no aportan nada al administrador.
                    detail:
                        error is DosaIntentException &&
                            (error.code.startsWith('ECF_') ||
                                error.code == 'AMBIGUOUS_RNC' ||
                                error.code == 'COMPANY_RNC_NOT_VERIFIED' ||
                                error.code ==
                                    'RNC_DOES_NOT_MATCH_COMPANY_IDENTITY' ||
                                error.code == 'SESSION_CLAIM_FAILED')
                        ? error.code
                        : null,
                    onRetry: () =>
                        ref.invalidate(dosaIntentRegistrationProvider(taxId)),
                  ),
                  data: (registered) {
                    _scheduleAutoOpen();
                    return _panel(
                      resolved,
                      binding,
                      attemptNo: registered.attemptNo,
                      created: registered.created,
                      canManage: true,
                      intentId: registered.sessionId,
                      historicalReviewRequired: false,
                    );
                  },
                );
          },
        );
  }

  Widget _panel(
    DosaAssistantConfig resolved,
    DosaAssistantBinding binding, {
    required int attemptNo,
    required bool created,
    required bool canManage,
    required String? intentId,
    required bool historicalReviewRequired,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // La autorización histórica es el PASO OBLIGATORIO para continuar, no
        // un control opcional: se muestra abierta y en primer plano. Antes vivía
        // dentro de un desplegable «Avanzado», indistinguible del otro panel
        // administrativo de la pantalla, y el administrador no encontraba cómo
        // avanzar.
        if (historicalReviewRequired && canManage && intentId != null)
          _DosaHistoricalReviewCard(
            intentId: intentId,
            onAuthorized: () {
              ref.invalidate(dosaIntentStateProvider);
              ref.invalidate(ecfOnboardingProvider);
            },
          )
        else if (historicalReviewRequired)
          const _DosaIntentGate(
            icon: Icons.lock_outline,
            message:
                'Este expediente tiene una revisión histórica. Solo un '
                'administrador autorizado puede aprobar la transición.',
          ),
        // La acción del portal exige el permiso administrativo: un usuario sin
        // él puede ver el estado, pero no pedir un ticket ni abrir el portal.
        // Mientras la transición histórica no esté autorizada, el portal no se
        // ofrece: abrirlo solo devolvería el mismo bloqueo del backend.
        if (canManage && !historicalReviewRequired)
          _DosaPortalCard(
            onOpen: _openPortal,
            busy: _openingPortal,
            portalOnly: widget.portalOnly,
          ),
        if (!widget.portalOnly)
          _DosaIntentBanner(
            attemptNo: attemptNo,
            created: created,
            onRefreshState: () => ref.invalidate(dosaIntentStateProvider),
          ),
        if (!widget.portalOnly)
          DosaAssistantPanel(
            config: resolved,
            session: DosaAssistantSession(
              binding: binding,
              phase:
                  widget.phase ?? _defaultPhase(widget.postulationExternalId),
            ),
            onResume: widget.onResume,
            // Un evento del navegador NO escribe nada: solo pide recargar.
            onWizardEvent: _onWizardEvent,
            onOpenExternally: resolved.hasSessionUrl
                ? () => openDosaAssistantExternally(
                    sessionUrl: resolved.sessionUrl!,
                  )
                : null,
          ),
      ],
    );
  }

  void _onWizardEvent(DosaAssistantEvent event) {
    // Doble cinturón: aunque el evento llegue con forma válida, aquí no se
    // crea ninguna postulación ni se marca aceptación fiscal.
    if (mayMutateFiscalState(event)) return;
    if (!event.impliesRefresh) return;
    ref.invalidate(ecfOnboardingProvider);
    widget.onRefresh?.call();
  }

  /// Sin señal del proveedor no se inventa un estado: como mucho "en curso".
  static DosaAssistantPhase _defaultPhase(String? externalId) =>
      externalId == null || externalId.trim().isEmpty
      ? DosaAssistantPhase.idle
      : DosaAssistantPhase.running;
}

/// Paso previo explícito: explica qué va a pasar y espera la confirmación del
/// administrador. Es la única puerta que registra la intención y, en
/// Preparación, la que abre el portal con el mismo clic.
class _DosaPrepareCard extends StatelessWidget {
  const _DosaPrepareCard({required this.onPrepare, this.portalOnly = false});

  final VoidCallback onPrepare;
  final bool portalOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    portalOnly ? 'Postulación electrónica' : 'Estado de certificación',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              portalOnly
                  ? 'Abriremos el asistente oficial de DOSA con los datos de '
                        'tu empresa. Allí completarás el certificado y las '
                        'credenciales. No se emite ningún comprobante.'
                  : 'Vincula esta empresa con su RNC verificado para abrir el '
                        'asistente del proveedor. No activa la facturación '
                        'electrónica, no emite comprobantes y no envía nada a '
                        'la DGII.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onPrepare,
                icon: const Icon(Icons.play_arrow, size: 18),
                label: Text(
                  portalOnly ? 'Iniciar postulación' : 'Preparar certificación',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Estado previo al asistente: mientras la intención no esté registrada, DOSA
/// no se monta. Si falla, se explica el motivo y no se abre nada.
class _DosaIntentGate extends StatelessWidget {
  const _DosaIntentGate({
    required this.icon,
    required this.message,
    this.detail,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final String? detail;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(message, style: theme.textTheme.bodyMedium),
                  if (detail != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      detail!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

/// Autorización administrativa de una transición histórica ya reconciliada.
///
/// Se muestra únicamente cuando el backend indica que queda una reconciliación
/// sin autorización vigente. No se ejecuta sola, no abre el portal y no emite:
/// solo deja la auditoría humana que el backend exige para continuar.
class _DosaHistoricalReviewCard extends ConsumerStatefulWidget {
  const _DosaHistoricalReviewCard({
    required this.intentId,
    required this.onAuthorized,
  });

  final String intentId;
  final VoidCallback onAuthorized;

  @override
  ConsumerState<_DosaHistoricalReviewCard> createState() =>
      _DosaHistoricalReviewCardState();
}

class _DosaHistoricalReviewCardState
    extends ConsumerState<_DosaHistoricalReviewCard> {
  final _formKey = GlobalKey<FormState>();
  final _approvalController = TextEditingController();
  final _reasonController = TextEditingController();
  bool _confirmed = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _approvalController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false) || !_confirmed) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Autorizar transición histórica'),
        content: const Text(
          'Esta acción deja auditoría y permite continuar la preparación del '
          'expediente. No emite comprobantes, no activa la facturación '
          'electrónica y no llama al proveedor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Autorizar'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(dosaCertificationIntentApiProvider)
          .authorizeHistoricalTransition(
            intentId: widget.intentId,
            ownerApprovalReference: _approvalController.text,
            reason: _reasonController.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Transición histórica autorizada.')),
      );
      widget.onAuthorized();
    } on DosaIntentException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'No se pudo autorizar la transición. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.admin_panel_settings_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Autorización administrativa requerida',
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Este expediente conserva una intención histórica de un '
                'proveedor anterior que ya fue conciliada con FullPOS. Para evitar cambiar '
                'estados, fechas o referencias sin control, la transición '
                'requiere aprobación del propietario y queda auditada.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _approvalController,
                maxLength: 128,
                decoration: const InputDecoration(
                  labelText: 'Referencia de aprobación del propietario',
                  helperText: 'Mínimo 8 caracteres',
                ),
                validator: (value) => (value ?? '').trim().length < 8
                    ? 'Indica una referencia de aprobación válida.'
                    : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _reasonController,
                maxLength: 500,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Motivo de la autorización',
                  helperText: 'Mínimo 20 caracteres',
                ),
                validator: (value) => (value ?? '').trim().length < 20
                    ? 'Explica el motivo con al menos 20 caracteres.'
                    : null,
              ),
              CheckboxListTile(
                value: _confirmed,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _confirmed = value == true),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text(
                  'Confirmo que revisé el expediente y autorizo esta '
                  'transición histórica.',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _busy || !_confirmed ? null : _submit,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check, size: 18),
                  label: const Text('Autorizar transición'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Acción única para todos los dispositivos: abrir el portal de certificación.
///
/// Un solo portal en el dominio autorizado, no un asistente por plataforma. El
/// componente oficial solo se monta allí porque es el único origen que el
/// proveedor permite enmarcar.
class _DosaPortalCard extends StatelessWidget {
  const _DosaPortalCard({
    required this.onOpen,
    required this.busy,
    this.portalOnly = false,
  });

  final VoidCallback onOpen;
  final bool busy;
  final bool portalOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.open_in_new, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    portalOnly
                        ? 'Asistente de certificación electrónica'
                        : 'Estado de certificación',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              portalOnly
                  ? 'Continúa en el asistente oficial de DOSA con los datos de '
                        'tu empresa. Allí se solicitan el certificado y las '
                        'credenciales.'
                  : 'Se abre el asistente oficial de DOSA. Puedes empezar aquí y '
                        'seguir desde otro dispositivo: el proceso pertenece a '
                        'la empresa, no al equipo.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: busy ? null : onOpen,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow, size: 18),
                label: Text(
                  portalOnly
                      ? 'Continuar con el asistente'
                      : 'Continuar certificación',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Barra informativa con el estado interno de la preparación.
///
/// Solo muestra identificadores y estados: ni claves, ni credenciales, ni nada
/// que el administrador no deba ver.
class _DosaIntentBanner extends ConsumerWidget {
  const _DosaIntentBanner({
    required this.attemptNo,
    required this.created,
    required this.onRefreshState,
  });

  final int attemptNo;
  final bool created;
  final VoidCallback onRefreshState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(dosaIntentStateProvider);

    final parts = <String>[
      'Intento $attemptNo',
      created ? 'registrado ahora' : 'ya estaba registrado',
    ];

    state.whenData((value) {
      if (value.sessionStatus != null) {
        parts.add(_statusLabel(value.sessionStatus!));
      }
    });

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.link, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              parts.join(' \u00b7 '),
              style: theme.textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: onRefreshState,
            child: const Text('Actualizar estado'),
          ),
        ],
      ),
    );
  }

  static String _statusLabel(String status) => switch (status) {
    'NOT_STARTED' => 'Preparación registrada',
    'RUNNING' => 'En curso',
    'ATTENTION' => 'Requiere atención',
    'COMPLETED' => 'Paso del asistente completado',
    'FAILED' => 'No completada',
    'CANCELLED' => 'Cancelada',
    'EXPIRED' => 'Vencida',
    _ => 'Estado pendiente de confirmar',
  };
}
