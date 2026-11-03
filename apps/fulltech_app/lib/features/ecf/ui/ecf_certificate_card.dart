import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_feedback.dart';
import '../data/ecf_certificate_repository.dart';
import '../ecf_certificate_models.dart';

/// Archivo elegido por el usuario (nombre + contenido).
typedef EcfPickedCertificate = ({String name, List<int> bytes});

/// Selección de archivo, inyectable para poder probar la tarjeta sin abrir el
/// diálogo del sistema.
typedef EcfCertificatePicker = Future<EcfPickedCertificate?> Function();

/// Estado del certificado para decidir si se puede continuar.
///
/// `ready` es la única señal que habilita el botón «Continuar» del paso; `reason`
/// dice exactamente qué falta cuando no lo está.
class EcfCertificateGate {
  const EcfCertificateGate({required this.ready, this.reason});

  /// Todavía no se ha validado nada.
  static const EcfCertificateGate pending = EcfCertificateGate(
    ready: false,
    reason:
        'Valida el certificado digital del representante legal para continuar.',
  );

  final bool ready;
  final String? reason;
}

/// Tarjeta de certificado digital del proceso de habilitación.
///
/// Qué hace, con precisión: envía el archivo y su contraseña **por HTTPS** a
/// FullPOS Cloud, donde se validan en memoria (formato PKCS#12, contraseña,
/// clave privada, vigencia y titular). El backend no los guarda, no los registra
/// y no los reenvía a la DGII ni a DOSA. La comprobación no afirma que la DGII
/// haya aceptado el certificado.
class EcfCertificateCard extends ConsumerStatefulWidget {
  const EcfCertificateCard({
    super.key,
    this.onValidated,
    this.onGateChanged,
    this.pickFile,
  });

  /// Se avisa cuando el certificado queda utilizable **y** con titular
  /// identificado, es decir, cuando ya no bloquea el avance.
  final VoidCallback? onValidated;

  /// Se avisa en cada cambio de estado: validado, rechazado o invalidado
  /// (archivo o contraseña modificados). El paso usa `reason` para explicar qué
  /// falta sin obligar a avanzar y volver.
  final ValueChanged<EcfCertificateGate>? onGateChanged;

  /// Selector de archivo. Por defecto, el diálogo del sistema.
  final EcfCertificatePicker? pickFile;

  @override
  ConsumerState<EcfCertificateCard> createState() => _EcfCertificateCardState();
}

class _EcfCertificateCardState extends ConsumerState<EcfCertificateCard> {
  String? _fileName;
  List<int>? _bytes;
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  EcfCertificateReport? _report;
  String? _error;

  @override
  void dispose() {
    // La contraseña no se conserva más de lo necesario.
    _password.clear();
    _password.dispose();
    super.dispose();
  }

  bool get _canValidate =>
      !_busy && _bytes != null && _password.text.trim().isNotEmpty;

  /// Estado real del certificado, sin optimismo: sin informe no hay permiso.
  EcfCertificateGate get _gate {
    final report = _report;
    if (report == null) return EcfCertificateGate.pending;
    if (report.canProceed) return const EcfCertificateGate(ready: true);
    return EcfCertificateGate(ready: false, reason: report.blockingReason);
  }

  void _publishGate() => widget.onGateChanged?.call(_gate);

  /// Cambiar el archivo o la contraseña invalida el resultado anterior: se
  /// validó con otros datos y no debe servir para continuar.
  void _invalidateResult() {
    if (_report == null && _error == null) {
      setState(() {});
      return;
    }
    setState(() {
      _report = null;
      _error = null;
    });
    _publishGate();
  }

  Future<void> _pick() async {
    final picker = widget.pickFile;
    final picked = picker != null
        ? await picker()
        : await _pickWithSystemDialog();
    if (picked == null) return;
    setState(() {
      _fileName = picked.name;
      _bytes = picked.bytes;
      _report = null;
      _error = null;
    });
    _publishGate();
  }

  Future<EcfPickedCertificate?> _pickWithSystemDialog() async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['pfx', 'p12'],
    );
    final file = (result == null || result.files.isEmpty)
        ? null
        : result.files.first;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return null;
    return (name: file.name, bytes: bytes);
  }

  Future<void> _validate() async {
    final bytes = _bytes;
    final fileName = _fileName;
    if (bytes == null || fileName == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final report = await ref
          .read(ecfCertificateRepositoryProvider)
          .validate(bytes: bytes, fileName: fileName, password: _password.text);
      if (!mounted) return;
      setState(() {
        _report = report;
        _busy = false;
      });
      _publishGate();
      if (report.canProceed) {
        AppFeedback.showToast(
          context,
          title: 'Certificado válido',
          body: 'El archivo y la clave privada son correctos, está vigente y el '
              'titular coincide con el expediente.',
          kind: AppFeedbackKind.success,
          dedupeKey: 'ecf_certificate_valid',
        );
        widget.onValidated?.call();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.toString().replaceFirst('Exception: ', '');
        _report = null;
      });
      _publishGate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _fileName ?? 'Ningún archivo seleccionado',
                key: const ValueKey('ecf_certificate_file_name'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: _fileName == null
                      ? FontWeight.w400
                      : FontWeight.w600,
                  color: _fileName == null
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF1F2A37),
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _busy ? null : _pick,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 34)),
              child: Text(_fileName == null ? 'Seleccionar' : 'Cambiar'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('ecf_certificate_password'),
          controller: _password,
          obscureText: _obscure,
          enabled: !_busy,
          // Cambiar la contraseña invalida el informe anterior: se validó con
          // otra y no debe seguir habilitando el avance.
          onChanged: (_) => _invalidateResult(),
          decoration: InputDecoration(
            labelText: 'Contraseña del certificado',
            isDense: true,
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Mostrar' : 'Ocultar',
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 18,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _canValidate ? _validate : null,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
            icon: _busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.verified_user_outlined, size: 18),
            label: Text(_busy ? 'Validando…' : 'Validar certificado'),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          _Message(
            kind: _MessageKind.error,
            title: 'No se pudo validar',
            body: _error!,
          ),
        ],
        if (_report != null) ...[
          const SizedBox(height: 12),
          _ReportView(report: _report!),
        ],
      ],
    );
  }
}

enum _MessageKind { success, error, neutral }

class _Message extends StatelessWidget {
  const _Message({required this.kind, required this.title, required this.body});

  final _MessageKind kind;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (background, border, icon, iconColor) = switch (kind) {
      _MessageKind.success => (
        const Color(0xFFECFDF3),
        const Color(0xFFB7E4C7),
        Icons.check_circle_outline,
        const Color(0xFF15803D),
      ),
      _MessageKind.error => (
        const Color(0xFFFEF2F2),
        const Color(0xFFFCA5A5),
        Icons.error_outline,
        const Color(0xFFB91C1C),
      ),
      _MessageKind.neutral => (
        const Color(0xFFF4F7F9),
        const Color(0xFFDDE7EE),
        Icons.info_outline,
        const Color(0xFF64748B),
      ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1F2A37),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.35,
                    color: const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportView extends StatelessWidget {
  const _ReportView({required this.report});

  final EcfCertificateReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final certificate = report.certificate;
    final rows = <(String, String)>[
      if (certificate?.commonName != null)
        ('Titular', certificate!.commonName!),
      if (certificate?.organization != null)
        ('Empresa', certificate!.organization!),
      if (certificate?.serialNumber != null)
        ('Identificación', certificate!.serialNumber!),
      if (certificate?.notAfterLabel != null)
        ('Vence', certificate!.notAfterLabel!),
      if (certificate?.daysRemaining != null)
        ('Días restantes', '${certificate!.daysRemaining}'),
      if (certificate?.fingerprintShort != null)
        ('Huella', certificate!.fingerprintShort!),
    ];
    final facts = rows.isEmpty ? null : _FactsCard(rows: rows);

    if (!report.valid) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Message(
            kind: _MessageKind.error,
            title: 'El certificado no es utilizable',
            body: report.message,
          ),
          if (facts != null) ...[const SizedBox(height: 10), facts],
          const SizedBox(height: 10),
          _DiagnosticsView(
            diagnostics: report.diagnostics,
            notes: report.notes,
          ),
        ],
      );
    }

    // Archivo correcto pero titular sin identificar: no es un error del usuario
    // ni un certificado ajeno. Se explica qué falta y no se habilita el avance.
    if (!report.canProceed) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Message(
            kind: _MessageKind.neutral,
            title: 'Falta comprobar el titular',
            body: report.blockingReason ?? report.message,
          ),
          if (facts != null) ...[const SizedBox(height: 10), facts],
          const SizedBox(height: 10),
          _DiagnosticsView(
            diagnostics: report.diagnostics,
            notes: report.notes,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Message(
          kind: _MessageKind.success,
          title: 'Certificado válido y vigente',
          body:
              'El archivo se abrió con esa contraseña y la clave privada '
              'corresponde al certificado.',
        ),
        if (facts != null) ...[const SizedBox(height: 10), facts],
        const SizedBox(height: 10),
        Text(
          'Lo que todavía no se comprobó',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 2),
        for (final pending in report.pendingChecks)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.remove_circle_outline,
                  size: 13,
                  color: Color(0xFF94A3B8),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    pending,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11.5,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Text(
          'Esta comprobación no es una validación de la DGII: no significa que '
          'haya aceptado el certificado ni que ya puedas emitir.',
          style: theme.textTheme.bodySmall?.copyWith(
            fontSize: 11,
            height: 1.3,
            color: const Color(0xFF94A3B8),
          ),
        ),
      ],
    );
  }
}

class _FactsCard extends StatelessWidget {
  const _FactsCard({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(
                      label,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1F2A37),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Diagnóstico SEGURO del resultado.
///
/// Dice qué condición falló con booleanos y etiquetas: nunca el RNC, la cédula,
/// el nombre del titular, la contraseña ni material del certificado.
class _DiagnosticsView extends StatelessWidget {
  const _DiagnosticsView({required this.diagnostics, required this.notes});

  final EcfCertificateDiagnostics diagnostics;
  final List<String> notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <(String, String)>[
      if (diagnostics.matchedAs != null)
        (
          'Titular reconocido',
          diagnostics.matchedAs == 'COMPANY'
              ? 'RNC de la empresa'
              : 'Cédula del representante',
        ),
      ('RNC en el expediente', diagnostics.hasCompanyTaxId ? 'Sí' : 'No'),
      (
        'Cédula del representante',
        diagnostics.hasRepresentativeId ? 'Sí' : 'No',
      ),
      (
        'Tipo de titular',
        switch (diagnostics.holderKind) {
          'PERSON' => 'Persona física',
          'ORGANIZATION' => 'Empresa',
          _ => 'No determinado',
        },
      ),
      if (diagnostics.daysRemaining != null)
        ('Días de vigencia', '${diagnostics.daysRemaining}'),
      if (diagnostics.keyMatchesCertificate != null)
        (
          'Clave privada',
          diagnostics.keyMatchesCertificate!
              ? 'Corresponde al certificado'
              : 'No corresponde',
        ),
    ];
    if (rows.isEmpty && notes.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rows.isNotEmpty) ...[
            Text(
              'Por qué',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF475569),
              ),
            ),
            const SizedBox(height: 2),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 132,
                      child: Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        value,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF1F2A37),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (notes.isNotEmpty) ...[
            if (rows.isNotEmpty) const SizedBox(height: 6),
            for (final note in notes)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  note,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11.5,
                    height: 1.35,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
