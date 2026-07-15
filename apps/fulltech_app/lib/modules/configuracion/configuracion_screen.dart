import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../../core/auth/auth_provider.dart';
import '../../core/company/company_settings_model.dart';
import '../../core/company/company_settings_repository.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../whatsapp/company_whatsapp_panel.dart';
import 'configuracion_usuarios_screen.dart';

class ConfiguracionScreen extends ConsumerStatefulWidget {
  const ConfiguracionScreen({super.key});

  @override
  ConsumerState<ConfiguracionScreen> createState() =>
      _ConfiguracionScreenState();
}

class _ConfiguracionScreenState extends ConsumerState<ConfiguracionScreen> {
  static const int _maxLogoBytes = 2 * 1024 * 1024;
  static const int _maxLogoDimension = 1200;

  final _nameCtrl = TextEditingController();
  final _rncCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _phonePreferentialCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _businessHoursCtrl = TextEditingController();
  final _instagramUrlCtrl = TextEditingController();
  final _facebookUrlCtrl = TextEditingController();
  final _websiteUrlCtrl = TextEditingController();
  final _gpsLocationUrlCtrl = TextEditingController();
  final List<_BankRowCtrls> _bankRows = [];
  final _legalRepresentativeNameCtrl = TextEditingController();
  final _legalRepresentativeCedulaCtrl = TextEditingController();
  final _legalRepresentativeRoleCtrl = TextEditingController();
  final _legalRepresentativeNationalityCtrl = TextEditingController();
  final _legalRepresentativeCivilStatusCtrl = TextEditingController();
  final _openAiApiKeyCtrl = TextEditingController();
  final _evolutionApiBaseUrlCtrl = TextEditingController();
  final _evolutionApiInstanceNameCtrl = TextEditingController();
  final _evolutionApiApiKeyCtrl = TextEditingController();

  bool _loading = true;
  bool _refreshing = false;
  bool _saving = false;
  bool _showApiKey = false;
  bool _showEvolutionApiKey = false;
  bool _syncingWebhooks = false;
  bool _whatsappWebhookEnabled = false;
  String? _logoBase64;
  String? _openSection;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _rncCtrl.dispose();
    _phoneCtrl.dispose();
    _phonePreferentialCtrl.dispose();
    _addressCtrl.dispose();
    _descriptionCtrl.dispose();
    _businessHoursCtrl.dispose();
    _instagramUrlCtrl.dispose();
    _facebookUrlCtrl.dispose();
    _websiteUrlCtrl.dispose();
    _gpsLocationUrlCtrl.dispose();
    for (final row in _bankRows) {
      row.dispose();
    }
    _legalRepresentativeNameCtrl.dispose();
    _legalRepresentativeCedulaCtrl.dispose();
    _legalRepresentativeRoleCtrl.dispose();
    _legalRepresentativeNationalityCtrl.dispose();
    _legalRepresentativeCivilStatusCtrl.dispose();
    _openAiApiKeyCtrl.dispose();
    _evolutionApiBaseUrlCtrl.dispose();
    _evolutionApiInstanceNameCtrl.dispose();
    _evolutionApiApiKeyCtrl.dispose();
    super.dispose();
  }

  void _applySettings(CompanySettings s) {
    _nameCtrl.text = s.companyName;
    _rncCtrl.text = s.rnc;
    _phoneCtrl.text = s.phone;
    _phonePreferentialCtrl.text = s.phonePreferential;
    _addressCtrl.text = s.address;
    _descriptionCtrl.text = s.description;
    _businessHoursCtrl.text = s.businessHours;
    _instagramUrlCtrl.text = s.instagramUrl;
    _facebookUrlCtrl.text = s.facebookUrl;
    _websiteUrlCtrl.text = s.websiteUrl;
    _gpsLocationUrlCtrl.text = s.gpsLocationUrl;
    for (final row in _bankRows) {
      row.dispose();
    }
    _bankRows
      ..clear()
      ..addAll(s.bankAccounts.map(_BankRowCtrls.fromEntry));
    _legalRepresentativeNameCtrl.text = s.legalRepresentativeName;
    _legalRepresentativeCedulaCtrl.text = s.legalRepresentativeCedula;
    _legalRepresentativeRoleCtrl.text = s.legalRepresentativeRole;
    _legalRepresentativeNationalityCtrl.text = s.legalRepresentativeNationality;
    _legalRepresentativeCivilStatusCtrl.text = s.legalRepresentativeCivilStatus;
    _logoBase64 = s.logoBase64;
    _openAiApiKeyCtrl.text = s.openAiApiKey;
    _evolutionApiBaseUrlCtrl.text = s.evolutionApiBaseUrl;
    _evolutionApiInstanceNameCtrl.text = s.evolutionApiInstanceName;
    _evolutionApiApiKeyCtrl.text = s.evolutionApiApiKey;
    _whatsappWebhookEnabled = s.whatsappWebhookEnabled;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _refreshing = false;
    });
    final repo = ref.read(companySettingsRepositoryProvider);
    try {
      final cached = await repo.getCachedSettings();
      if (cached != null) {
        if (!mounted) return;
        _applySettings(cached);
        setState(() {
          _loading = false;
          _refreshing = true;
        });
      }
      final settings = await repo.getSettingsRemoteAndCache();
      if (!mounted) return;
      _applySettings(settings);
      ref.invalidate(companySettingsProvider);
    } catch (e) {
      _showMessage('$e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _refreshing = false;
        });
      }
    }
  }

  Future<bool> _save() async {
    if (_saving) return false;
    setState(() => _saving = true);
    final settings = CompanySettings(
      companyName: _nameCtrl.text.trim(),
      rnc: _rncCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      phonePreferential: _phonePreferentialCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      description: _descriptionCtrl.text.trim(),
      businessHours: _businessHoursCtrl.text.trim(),
      instagramUrl: _instagramUrlCtrl.text.trim(),
      facebookUrl: _facebookUrlCtrl.text.trim(),
      websiteUrl: _websiteUrlCtrl.text.trim(),
      gpsLocationUrl: _gpsLocationUrlCtrl.text.trim(),
      bankAccounts: _bankRows.map((r) => r.toEntry()).toList(),
      legalRepresentativeName: _legalRepresentativeNameCtrl.text.trim(),
      legalRepresentativeCedula: _legalRepresentativeCedulaCtrl.text.trim(),
      legalRepresentativeRole: _legalRepresentativeRoleCtrl.text.trim(),
      legalRepresentativeNationality: _legalRepresentativeNationalityCtrl.text
          .trim(),
      legalRepresentativeCivilStatus: _legalRepresentativeCivilStatusCtrl.text
          .trim(),
      logoBase64: _logoBase64,
      openAiApiKey: _openAiApiKeyCtrl.text.trim(),
      openAiModel: '',
      hasOpenAiApiKey: _openAiApiKeyCtrl.text.trim().isNotEmpty,
      evolutionApiBaseUrl: _evolutionApiBaseUrlCtrl.text.trim(),
      evolutionApiInstanceName: _evolutionApiInstanceNameCtrl.text.trim(),
      evolutionApiApiKey: _evolutionApiApiKeyCtrl.text.trim(),
      hasEvolutionApiApiKey: _evolutionApiApiKeyCtrl.text.trim().isNotEmpty,
      whatsappWebhookEnabled: _whatsappWebhookEnabled,
    );
    try {
      final queued = await ref
          .read(companySettingsRepositoryProvider)
          .saveSettingsOrQueue(settings);
      ref.invalidate(companySettingsProvider);
      _showMessage(
        queued
            ? 'Configuracion guardada localmente. Se sincronizara en segundo plano.'
            : 'Configuracion guardada.',
      );
      return true;
    } catch (e) {
      _showMessage('$e');
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    if (!mounted) return;
    final file = result?.files.firstOrNull;
    if (file == null || file.bytes == null) return;
    try {
      final prepared = _prepareLogoBytes(file.bytes!);
      setState(() => _logoBase64 = base64Encode(prepared));
      _showMessage('Logo cargado correctamente.');
    } catch (e) {
      _showMessage('$e');
    }
  }

  Uint8List? _logoBytes() {
    final raw = _logoBase64;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  Uint8List _prepareLogoBytes(Uint8List rawBytes) {
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null)
      throw Exception('La imagen seleccionada no es valida.');
    var current = img.bakeOrientation(decoded);
    current = _resizeToFit(current, _maxLogoDimension);
    for (var attempt = 0; attempt < 5; attempt++) {
      final quality = (88 - (attempt * 10)).clamp(50, 88).toInt();
      final pngBytes = Uint8List.fromList(img.encodePng(current, level: 6));
      final jpgBytes = Uint8List.fromList(
        img.encodeJpg(current, quality: quality),
      );
      if (current.hasAlpha && pngBytes.length <= _maxLogoBytes) return pngBytes;
      if (jpgBytes.length <= _maxLogoBytes) return jpgBytes;
      if (!current.hasAlpha && pngBytes.length <= _maxLogoBytes)
        return pngBytes;
      if (current.width <= 320 && current.height <= 320) break;
      current = img.copyResize(
        current,
        width: (current.width * 0.82).round(),
        height: (current.height * 0.82).round(),
        interpolation: img.Interpolation.average,
      );
    }
    throw Exception(
      'El logo sigue siendo demasiado pesado. Usa una imagen menor a 2 MB.',
    );
  }

  img.Image _resizeToFit(img.Image image, int maxDimension) {
    if (image.width <= maxDimension && image.height <= maxDimension) {
      return image;
    }
    final ar = image.width / image.height;
    final w = image.width >= image.height
        ? maxDimension
        : (maxDimension * ar).round();
    final h = image.height > image.width
        ? maxDimension
        : (maxDimension / ar).round();
    return img.copyResize(
      image,
      width: w,
      height: h,
      interpolation: img.Interpolation.average,
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _toggleSection(String key) {
    setState(() => _openSection = _openSection == key ? null : key);
  }

  InputDecoration _dec(String label, {String? hint, Widget? suffix}) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixIcon: suffix,
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outlineVariant, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    String? hint,
    TextInputType? keyboard,
    bool obscure = false,
    Widget? suffix,
    int maxLines = 1,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 480),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        keyboardType: keyboard,
        maxLines: maxLines,
        autocorrect: false,
        enableSuggestions: !obscure,
        decoration: _dec(label, hint: hint, suffix: suffix),
      ),
    );
  }

  Widget _accordion({
    required String key,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isOpen = _openSection == key;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isOpen
              ? scheme.primary.withValues(alpha: 0.35)
              : scheme.outlineVariant.withValues(alpha: 0.5),
          width: isOpen ? 1.5 : 1,
        ),
        color: scheme.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => _toggleSection(key),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: isOpen ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isOpen ? scheme.primary : scheme.onSurface,
                          ),
                        ),
                        if (!isOpen) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: isOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: isOpen
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
                    child: child,
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpresaSection() {
    final logoBytes = _logoBytes();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (logoBytes != null)
              Container(
                width: 72,
                height: 72,
                margin: const EdgeInsets.only(right: 12),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Image.memory(logoBytes, fit: BoxFit.cover),
              )
            else
              Container(
                width: 72,
                height: 72,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                ),
                child: Icon(
                  Icons.image_outlined,
                  size: 28,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            OutlinedButton.icon(
              onPressed: _pickLogo,
              icon: const Icon(Icons.upload_file_outlined, size: 18),
              label: const Text('Subir logo'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
            ),
            if (_logoBase64 != null) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Quitar logo',
                onPressed: () {
                  setState(() => _logoBase64 = null);
                  _showMessage('Logo eliminado.');
                },
                icon: const Icon(Icons.delete_outline),
                color: Theme.of(context).colorScheme.error,
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _field(_nameCtrl, 'Nombre de la empresa'),
        const SizedBox(height: 12),
        _field(_rncCtrl, 'RNC'),
        const SizedBox(height: 12),
        _field(_descriptionCtrl, 'Descripcion corta', maxLines: 2),
        const SizedBox(height: 12),
        _field(_phoneCtrl, 'Telefono principal', keyboard: TextInputType.phone),
        const SizedBox(height: 12),
        _field(
          _phonePreferentialCtrl,
          'Telefono preferencial',
          hint: 'Ej. +1 809 000 0000',
          keyboard: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        _field(_addressCtrl, 'Direccion', maxLines: 2),
        const SizedBox(height: 12),
        _field(
          _businessHoursCtrl,
          'Horario comercial',
          hint: 'Ej. Lun-Vie 8am-5pm | Sab 8am-12pm',
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        Text(
          'Redes y presencia digital',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 10),
        _field(
          _instagramUrlCtrl,
          'Instagram',
          hint: 'https://instagram.com/...',
          keyboard: TextInputType.url,
        ),
        const SizedBox(height: 12),
        _field(
          _facebookUrlCtrl,
          'Facebook',
          hint: 'https://facebook.com/...',
          keyboard: TextInputType.url,
        ),
        const SizedBox(height: 12),
        _field(
          _websiteUrlCtrl,
          'Sitio web',
          hint: 'https://...',
          keyboard: TextInputType.url,
        ),
        const SizedBox(height: 12),
        _field(
          _gpsLocationUrlCtrl,
          'Enlace GPS',
          hint: 'https://maps.google.com/...',
          keyboard: TextInputType.url,
        ),
      ],
    );
  }

  Widget _buildCuentasSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_bankRows.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Sin cuentas bancarias configuradas.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        else
          for (var i = 0; i < _bankRows.length; i++) ...[
            _BankRowWidget(
              row: _bankRows[i],
              index: i + 1,
              dec: _dec,
              onRemove: () => setState(() {
                _bankRows[i].dispose();
                _bankRows.removeAt(i);
              }),
            ),
            const SizedBox(height: 12),
          ],
        TextButton.icon(
          onPressed: () => setState(() => _bankRows.add(_BankRowCtrls())),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Agregar cuenta'),
        ),
      ],
    );
  }

  Widget _buildLegalSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _field(_legalRepresentativeNameCtrl, 'Nombre del representante legal'),
        const SizedBox(height: 12),
        _field(_legalRepresentativeCedulaCtrl, 'Cedula'),
        const SizedBox(height: 12),
        _field(_legalRepresentativeRoleCtrl, 'Cargo'),
        const SizedBox(height: 12),
        _field(_legalRepresentativeNationalityCtrl, 'Nacionalidad'),
        const SizedBox(height: 12),
        _field(_legalRepresentativeCivilStatusCtrl, 'Estado civil'),
      ],
    );
  }

  Widget _buildOpenAiSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Solo coloca tu API key. El sistema selecciona el modelo segun la necesidad.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        _field(
          _openAiApiKeyCtrl,
          'OpenAI API Key',
          hint: 'sk-...',
          obscure: !_showApiKey,
          suffix: IconButton(
            tooltip: _showApiKey ? 'Ocultar clave' : 'Mostrar clave',
            onPressed: () => setState(() => _showApiKey = !_showApiKey),
            icon: Icon(
              _showApiKey
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (_openAiApiKeyCtrl.text.trim().isNotEmpty)
          TextButton.icon(
            onPressed: () => setState(() => _openAiApiKeyCtrl.clear()),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Limpiar API key'),
          ),
      ],
    );
  }

  Future<void> _syncWebhooks() async {
    if (_syncingWebhooks) return;
    setState(() => _syncingWebhooks = true);
    try {
      final repo = ref.read(companySettingsRepositoryProvider);
      await repo.syncWhatsappWebhooks(enabled: _whatsappWebhookEnabled);
      _showMessage('Webhooks sincronizados correctamente.');
    } catch (e) {
      _showMessage('Error al sincronizar webhooks: $e');
    } finally {
      if (mounted) setState(() => _syncingWebhooks = false);
    }
  }

  Widget _buildWhatsappSection() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Infrastructure fields (always shown — needed before creating instance)
        _field(
          _evolutionApiBaseUrlCtrl,
          'URL base de Evolution API',
          hint: 'https://evolution.tudominio.com',
          keyboard: TextInputType.url,
        ),
        const SizedBox(height: 12),
        _field(
          _evolutionApiApiKeyCtrl,
          'API Key de Evolution API',
          hint: 'tu-api-key',
          obscure: !_showEvolutionApiKey,
          suffix: IconButton(
            tooltip: _showEvolutionApiKey ? 'Ocultar clave' : 'Mostrar clave',
            onPressed: () =>
                setState(() => _showEvolutionApiKey = !_showEvolutionApiKey),
            icon: Icon(
              _showEvolutionApiKey
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Guarda primero la configuración antes de crear la instancia.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        Divider(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        const SizedBox(height: 16),
        // Instance management panel
        Text(
          'INSTANCIA DE LA EMPRESA',
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Esta instancia es exclusiva para notificaciones automáticas del sistema. '
          'Es completamente SEPARADA de la instancia personal de cada usuario.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        const CompanyWhatsappPanel(),
        const SizedBox(height: 16),
        Divider(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        const SizedBox(height: 12),
        Row(
          children: [
            Switch(
              value: _whatsappWebhookEnabled,
              onChanged: (v) => setState(() => _whatsappWebhookEnabled = v),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Webhooks activos',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Activa para recibir mensajes entrantes en el CRM.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _syncingWebhooks ? null : _syncWebhooks,
          icon: _syncingWebhooks
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync_rounded, size: 18),
          label: Text(
            _syncingWebhooks
                ? 'Sincronizando...'
                : 'Sincronizar webhooks de usuarios',
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_saving) ...[_SavingBanner(), const SizedBox(height: 12)],
                if (_refreshing)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: _RefreshingSettingsBanner(),
                  ),
                _accordion(
                  key: 'empresa',
                  icon: Icons.business_outlined,
                  title: 'Datos de la empresa',
                  subtitle: 'Nombre, logo, contacto y redes sociales.',
                  child: _buildEmpresaSection(),
                ),
                _accordion(
                  key: 'cuentas',
                  icon: Icons.account_balance_outlined,
                  title: 'Cuentas bancarias',
                  subtitle: 'Cuentas disponibles para pagos y transferencias.',
                  child: _buildCuentasSection(),
                ),
                _accordion(
                  key: 'legal',
                  icon: Icons.gavel_outlined,
                  title: 'Datos legales',
                  subtitle:
                      'Representante legal — usado en contratos laborales.',
                  child: _buildLegalSection(),
                ),
                _accordion(
                  key: 'openai',
                  icon: Icons.hub_outlined,
                  title: 'OpenAI',
                  subtitle: 'Credenciales para el asistente de IA.',
                  child: _buildOpenAiSection(),
                ),
                _accordion(
                  key: 'whatsapp',
                  icon: Icons.chat_rounded,
                  title: 'WhatsApp de la empresa',
                  subtitle:
                      'Instancia de notificaciones automáticas — separada de la instancia personal de cada usuario.',
                  child: _buildWhatsappSection(),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(
                      _saving ? 'Guardando...' : 'Guardar configuracion',
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).user;
    final isAdmin = user?.role == 'ADMIN';

    if (!isAdmin) {
      return Scaffold(
        appBar: const CustomAppBar(
          title: 'Configuracion',
          showLogo: false,
          showDepartmentLabel: false,
        ),
        drawer: buildAdaptiveDrawer(context, currentUser: user),
        body: const Center(
          child: Text('Solo administradores pueden acceder a configuracion.'),
        ),
      );
    }

    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Configuracion',
        showLogo: false,
        showDepartmentLabel: false,
      ),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const ConfiguracionUsuariosScreen(),
          ),
        ),
        icon: const Icon(Icons.manage_accounts_outlined),
        label: const Text('Config. por usuario'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

class _BankRowCtrls {
  final TextEditingController name;
  final TextEditingController type;
  final TextEditingController accountNumber;
  final TextEditingController bankName;

  _BankRowCtrls({
    String initialName = '',
    String initialType = '',
    String initialAccountNumber = '',
    String initialBankName = '',
  }) : name = TextEditingController(text: initialName),
       type = TextEditingController(text: initialType),
       accountNumber = TextEditingController(text: initialAccountNumber),
       bankName = TextEditingController(text: initialBankName);

  factory _BankRowCtrls.fromEntry(BankAccountEntry e) => _BankRowCtrls(
    initialName: e.name,
    initialType: e.type,
    initialAccountNumber: e.accountNumber,
    initialBankName: e.bankName,
  );

  BankAccountEntry toEntry() => BankAccountEntry(
    name: name.text.trim(),
    type: type.text.trim(),
    accountNumber: accountNumber.text.trim(),
    bankName: bankName.text.trim(),
  );

  void dispose() {
    name.dispose();
    type.dispose();
    accountNumber.dispose();
    bankName.dispose();
  }
}

class _BankRowWidget extends StatelessWidget {
  const _BankRowWidget({
    required this.row,
    required this.index,
    required this.dec,
    required this.onRemove,
  });

  final _BankRowCtrls row;
  final int index;
  final InputDecoration Function(String, {String? hint, Widget? suffix}) dec;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        color: scheme.surfaceContainerLowest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Cuenta $index',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Eliminar cuenta',
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 18),
                color: scheme.error,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 200,
                child: TextField(
                  controller: row.name,
                  decoration: dec('Nombre de cuenta'),
                ),
              ),
              SizedBox(
                width: 140,
                child: TextField(
                  controller: row.type,
                  decoration: dec('Tipo', hint: 'Ej. Ahorros'),
                ),
              ),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: row.accountNumber,
                  decoration: dec('Numero de cuenta'),
                  keyboardType: TextInputType.number,
                ),
              ),
              SizedBox(
                width: 180,
                child: TextField(
                  controller: row.bankName,
                  decoration: dec('Banco'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SavingBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.primaryContainer,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Guardando configuracion...',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
      ),
    );
  }
}

class _RefreshingSettingsBanner extends StatelessWidget {
  const _RefreshingSettingsBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Actualizando configuracion en segundo plano...',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
