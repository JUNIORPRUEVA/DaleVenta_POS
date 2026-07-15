import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/models/user_model.dart';
import '../../core/routing/routes.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/user_avatar.dart';
import '../user/data/users_repository.dart';

String _getInitials(String name) {
  final initials = name
      .split(' ')
      .map((e) => e.isNotEmpty ? e[0].toUpperCase() : '')
      .join('')
      .replaceAll(' ', '');

  if (initials.isEmpty) return 'U';
  if (initials.length >= 2) return initials.substring(0, 2);
  return initials.padRight(2, initials[0]);
}

class UserScreen extends ConsumerStatefulWidget {
  const UserScreen({super.key});

  @override
  ConsumerState<UserScreen> createState() => _UserScreenState();
}

class _UserScreenState extends ConsumerState<UserScreen> {
  Future<void> _pickAndUploadProfilePhoto() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.first;
      final bytes = picked.bytes;
      if (bytes == null || bytes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo leer la imagen seleccionada'),
          ),
        );
        return;
      }

      final repo = ref.read(usersRepositoryProvider);
      final previousPhotoUrl =
          (ref.read(authStateProvider).user?.fotoPersonalUrl ?? '').trim();
      final uploadedUrl = await repo.uploadUserDocument(
        bytes: bytes,
        fileName: picked.name,
        kind: 'profile',
      );
      final updated = await repo.updateMe(fotoPersonalUrl: uploadedUrl);

      if (previousPhotoUrl.isNotEmpty) {
        await CachedNetworkImage.evictFromCache(previousPhotoUrl);
      }
      final freshPhotoUrl = (updated.fotoPersonalUrl ?? '').trim();
      if (freshPhotoUrl.isNotEmpty && freshPhotoUrl != previousPhotoUrl) {
        await CachedNetworkImage.evictFromCache(freshPhotoUrl);
      }

      ref.read(authStateProvider.notifier).setUser(updated);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Foto de perfil actualizada')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar la foto: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authStateProvider);
    final user = state.user;

    return Scaffold(
      appBar: CustomAppBar(title: 'FullTech', showLogo: true),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : _UserDetailContent(
              user: user,
              onPhotoTap: _pickAndUploadProfilePhoto,
              onEdit: () => context.push(Routes.profile),
              onLogout: () async {
                await ref.read(authStateProvider.notifier).logout();
              },
            ),
    );
  }
}

class _UserDetailContent extends StatelessWidget {
  final UserModel user;
  final VoidCallback onPhotoTap;
  final VoidCallback onEdit;
  final Future<void> Function() onLogout;

  const _UserDetailContent({
    required this.user,
    required this.onPhotoTap,
    required this.onEdit,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    final infoItems = <(String, String)>[
      if (user.telefono.trim().isNotEmpty) ('Teléfono', user.telefono.trim()),
      if ((user.cedula ?? '').trim().isNotEmpty)
        ('Cédula', user.cedula!.trim()),
      if ((user.telefonoFamiliar ?? '').trim().isNotEmpty)
        ('Tel. familiar', user.telefonoFamiliar!.trim()),
      if (user.fechaNacimiento != null)
        ('Nacimiento', DateFormat('dd/MM/yyyy').format(user.fechaNacimiento!)),
      if (user.edad != null) ('Edad', '${user.edad} años'),
      ('Estado civil', user.estaCasado ? 'Casado' : 'Soltero'),
      ('Hijos', user.tieneHijos ? 'Sí' : 'No'),
      if ((user.experienciaLaboral ?? '').trim().isNotEmpty)
        ('Experiencia', user.experienciaLaboral!.trim()),
      if (user.fechaIngreso != null)
        ('Ingreso', DateFormat('dd/MM/yyyy').format(user.fechaIngreso!)),
      if (user.fechaIngreso != null)
        ('Días empresa', '${user.diasEnEmpresa ?? 0}'),
      ('Licencia', user.licenciaConducir ? 'Sí' : 'No'),
      ('Vehículo', user.vehiculo ? 'Sí' : 'No'),
      ('Casa propia', user.casaPropia ? 'Sí' : 'No'),
      if ((user.cuentaNominaPreferencial ?? '').trim().isNotEmpty)
        ('Nómina', user.cuentaNominaPreferencial!.trim()),
      ('Rol', ((user.role ?? '').trim().isEmpty) ? '—' : user.role!.trim()),
      ('Estado', user.blocked ? 'Bloqueado' : 'Activo'),
      if (user.createdAt != null)
        ('Miembro desde', DateFormat('dd/MM/yyyy').format(user.createdAt!)),
    ];

    final docs = <(String, String)>[
      if ((user.fotoPersonalUrl ?? '').trim().isNotEmpty)
        ('Perfil', user.fotoPersonalUrl!.trim()),
      if ((user.fotoCedulaUrl ?? '').trim().isNotEmpty)
        ('Cédula', user.fotoCedulaUrl!.trim()),
      if ((user.fotoLicenciaUrl ?? '').trim().isNotEmpty)
        ('Licencia', user.fotoLicenciaUrl!.trim()),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 4
            : constraints.maxWidth >= 760
            ? 3
            : 2;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeaderStrip(user: user, onPhotoTap: onPhotoTap),
                  const SizedBox(height: 16),
                  const _SectionTitle('Datos'),
                  const SizedBox(height: 10),
                  _Panel(
                    child: _DataGrid(items: infoItems, columns: columns),
                  ),
                  if (user.habilidades.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const _SectionTitle('Habilidades'),
                    const SizedBox(height: 10),
                    _Panel(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: user.habilidades
                            .map(
                              (h) => Chip(
                                label: Text(
                                  h,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                  ],
                  if (docs.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const _SectionTitle('Imágenes'),
                    const SizedBox(height: 10),
                    _Panel(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: docs
                            .map(
                              (doc) =>
                                  _SmallPreview(label: doc.$1, url: doc.$2),
                            )
                            .toList(growable: false),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.edit),
                          label: const Text('Editar Perfil'),
                          onPressed: onEdit,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.logout),
                          label: const Text('Cerrar Sesión'),
                          onPressed: () async => onLogout(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeaderStrip extends StatelessWidget {
  final UserModel user;
  final VoidCallback onPhotoTap;

  const _HeaderStrip({required this.user, required this.onPhotoTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = user.nombreCompleto.trim().isEmpty
        ? 'Usuario'
        : user.nombreCompleto.trim();
    final email = user.email.trim();

    return _Panel(
      child: Row(
        children: [
          GestureDetector(
            onTap: onPhotoTap,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.95, end: 1).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutBack,
                      ),
                    ),
                    child: child,
                  ),
                );
              },
              child: UserAvatar(
                key: ValueKey((user.fotoPersonalUrl ?? '').trim()),
                radius: 34,
                backgroundColor: scheme.primary,
                imageUrl: user.fotoPersonalUrl,
                child: Text(
                  _getInitials(user.nombreCompleto),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.outline,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          _StatusPill(active: !user.blocked),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: scheme.primary,
            letterSpacing: 0.9,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: scheme.outlineVariant, height: 1)),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  final Widget child;

  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _DataGrid extends StatelessWidget {
  final List<(String, String)> items;
  final int columns;

  const _DataGrid({required this.items, required this.columns});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: 12,
          children: items
              .map(
                (item) => SizedBox(
                  width: width,
                  child: _DataCell(label: item.$1, value: item.$2),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _DataCell extends StatelessWidget {
  final String label;
  final String value;

  const _DataCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: theme.colorScheme.outline,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _SmallPreview extends StatelessWidget {
  final String label;
  final String url;

  const _SmallPreview({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(20),
          child: InteractiveViewer(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => SizedBox(
                width: 280,
                height: 220,
                child: Icon(Icons.broken_image_outlined, color: scheme.outline),
              ),
            ),
          ),
        ),
      ),
      child: SizedBox(
        width: 100,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                url,
                width: 100,
                height: 72,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 100,
                  height: 72,
                  color: scheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: scheme.outline,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: scheme.outline,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool active;

  const _StatusPill({required this.active});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? Colors.green : scheme.error;
    final bg = active ? Colors.green.withAlpha(28) : scheme.errorContainer;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              active ? 'Activo' : 'Bloqueado',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
