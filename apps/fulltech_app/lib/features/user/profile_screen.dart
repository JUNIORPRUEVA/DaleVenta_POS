import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/utils/media_url.dart';
import '../../core/utils/string_utils.dart';
import '../../core/models/user_model.dart';
import '../user/data/users_repository.dart';
import '../user/profile_photo_processor.dart';
import '../../core/widgets/user_avatar.dart';

enum _ProfilePhotoAction { upload, delete }

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authStateProvider);
    final user = state.user;

    return Scaffold(
      appBar: CustomAppBar(title: 'Mi Perfil', showLogo: false),
      drawer: buildAdaptiveDrawer(context, currentUser: user),
      body: user == null
          ? const Center(child: Text('Preparando perfil...'))
          : _ProfileContent(
              user: user,
              onEdit: () => _showEditDialog(context, ref, user),
              onPhotoTap: () => _showProfilePhotoActions(context, ref),
              onPassword: () => _showPasswordDialog(context, ref),
            ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, UserModel user) {
    final nameCtrl = TextEditingController(text: user.nombreCompleto);
    final emailCtrl = TextEditingController(text: user.email);
    final phoneCtrl = TextEditingController(text: user.telefono);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar mis datos'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre completo'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Correo'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Teléfono'),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameCtrl.text.trim();
              if (newName.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('El nombre no puede estar vacío'),
                  ),
                );
                return;
              }

              final originalEmail = user.email.trim();
              final newEmail = emailCtrl.text.trim();
              final originalPhone = user.telefono.trim();
              final newPhone = phoneCtrl.text.trim();

              final changedEmail =
                  newEmail.isNotEmpty && newEmail != originalEmail;
              final changedName = newName != user.nombreCompleto.trim();
              final changedPhone = newPhone != originalPhone;

              if (!changedEmail && !changedName && !changedPhone) {
                Navigator.pop(context);
                return;
              }

              try {
                final repo = ref.read(usersRepositoryProvider);
                UserModel updated;
                try {
                  updated = await repo.updateMe(
                    email: changedEmail ? newEmail : null,
                    nombreCompleto: changedName ? newName : null,
                    telefono: changedPhone ? newPhone : null,
                  );
                } catch (e) {
                  if (changedEmail) {
                    updated = await repo.updateMe(
                      nombreCompleto: changedName ? newName : null,
                      telefono: changedPhone ? newPhone : null,
                    );
                    ref.read(authStateProvider.notifier).setUser(updated);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Perfil actualizado (el correo no se pudo cambiar)',
                        ),
                      ),
                    );
                    return;
                  }
                  rethrow;
                }

                ref.read(authStateProvider.notifier).setUser(updated);
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Perfil actualizado')),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('No se pudo actualizar: $e')),
                );
              }
            },
            child: const Text('Guardar cambios'),
          ),
        ],
      ),
    );
  }

  Future<void> _showProfilePhotoActions(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final currentPhoto =
        (ref.read(authStateProvider).user?.fotoPersonalUrl ?? '').trim();
    final hasPhoto = currentPhoto.isNotEmpty;
    final action = await showDialog<_ProfilePhotoAction>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Foto de perfil'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, _ProfilePhotoAction.upload),
            child: Row(
              children: [
                const Icon(Icons.upload_rounded),
                const SizedBox(width: 12),
                Text(hasPhoto ? 'Cambiar foto' : 'Subir foto'),
              ],
            ),
          ),
          if (hasPhoto)
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.pop(context, _ProfilePhotoAction.delete),
              child: const Row(
                children: [
                  Icon(Icons.delete_outline_rounded),
                  SizedBox(width: 12),
                  Text('Eliminar foto'),
                ],
              ),
            ),
        ],
      ),
    );

    if (!context.mounted || action == null) return;
    switch (action) {
      case _ProfilePhotoAction.upload:
        await _pickAndUploadProfilePhoto(context, ref);
        break;
      case _ProfilePhotoAction.delete:
        await _deleteProfilePhoto(context, ref);
        break;
    }
  }

  Future<void> _deleteProfilePhoto(BuildContext context, WidgetRef ref) async {
    final previousPhotoUrl =
        (ref.read(authStateProvider).user?.fotoPersonalUrl ?? '').trim();
    if (previousPhotoUrl.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar foto'),
        content: const Text('Se quitará la foto actual de tu perfil.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (!context.mounted || confirmed != true) return;

    try {
      final repo = ref.read(usersRepositoryProvider);
      final updated = await repo.updateMe(fotoPersonalUrl: '');
      await _evictProfilePhotoCaches(previousPhotoUrl);
      ref.read(authStateProvider.notifier).setUser(updated);

      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Foto de perfil eliminada')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo eliminar la foto: $e')),
      );
    }
  }

  Future<void> _pickAndUploadProfilePhoto(
    BuildContext context,
    WidgetRef ref,
  ) async {
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
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo leer la imagen seleccionada'),
          ),
        );
        return;
      }

      final previousUser = ref.read(authStateProvider).user;
      if (previousUser == null) return;

      final processedBytes = processProfilePhoto(Uint8List.fromList(bytes));
      final previewUrl = profilePhotoDataUrl(processedBytes);
      ref
          .read(authStateProvider.notifier)
          .setUser(
            _copyUserWithPhoto(previousUser, previewUrl),
            persistSnapshot: false,
          );

      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      await _uploadProcessedProfilePhoto(
        messenger,
        ref,
        processedBytes,
        previewUrl,
        previousUser,
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo actualizar la foto: $e')),
      );
    }
  }

  Future<void> _uploadProcessedProfilePhoto(
    ScaffoldMessengerState messenger,
    WidgetRef ref,
    Uint8List processedBytes,
    String previewUrl,
    UserModel previousUser,
  ) async {
    final repo = ref.read(usersRepositoryProvider);
    final previousPhotoUrl = (previousUser.fotoPersonalUrl ?? '').trim();

    try {
      final uploadedUrl = await repo.uploadUserDocument(
        bytes: processedBytes,
        fileName: profilePhotoUploadName,
        kind: 'profile',
      );
      var currentPhoto =
          (ref.read(authStateProvider).user?.fotoPersonalUrl ?? '').trim();
      if (currentPhoto != previewUrl) return;

      final updated = await repo.updateMe(fotoPersonalUrl: uploadedUrl);

      currentPhoto = (ref.read(authStateProvider).user?.fotoPersonalUrl ?? '')
          .trim();
      if (currentPhoto == previewUrl) {
        await _evictProfilePhotoCaches(previousPhotoUrl);
        await _evictProfilePhotoCaches(uploadedUrl);
        final freshPhotoUrl = (updated.fotoPersonalUrl ?? '').trim();
        await _evictProfilePhotoCaches(freshPhotoUrl);
        ref
            .read(authStateProvider.notifier)
            .setUser(
              _copyUserWithPhoto(updated, previewUrl),
              snapshotUser: updated,
            );
        await ref.read(tokenStorageProvider).saveUserSnapshot(updated);
      }

      if (!messenger.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Foto de perfil actualizada')),
      );
    } catch (e) {
      final currentPhoto =
          (ref.read(authStateProvider).user?.fotoPersonalUrl ?? '').trim();
      if (currentPhoto == previewUrl) {
        ref
            .read(authStateProvider.notifier)
            .setUser(previousUser, persistSnapshot: false);
      }
      if (!messenger.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo subir la foto: $e')),
      );
    }
  }

  Future<void> _evictProfilePhotoCaches(String? rawUrl) async {
    final value = (rawUrl ?? '').trim();
    if (value.isEmpty) return;
    await CachedNetworkImage.evictFromCache(value);
    final resolved = resolvePublicMediaUrl(value);
    if (resolved.isNotEmpty && resolved != value) {
      await CachedNetworkImage.evictFromCache(resolved);
    }
  }

  UserModel _copyUserWithPhoto(UserModel user, String? photoUrl) {
    final json = user.toJson();
    json['fotoPersonalUrl'] = photoUrl;
    return UserModel.fromJson(json);
  }

  Future<void> _showPasswordDialog(BuildContext context, WidgetRef ref) async {
    final passwordCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar contraseña'),
        content: TextField(
          controller: passwordCtrl,
          decoration: const InputDecoration(labelText: 'Nueva contraseña'),
          obscureText: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final password = passwordCtrl.text.trim();
              if (password.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Ingresa una contraseña válida'),
                  ),
                );
                return;
              }

              try {
                final repo = ref.read(usersRepositoryProvider);
                final updated = await repo.updateMe(password: password);
                ref.read(authStateProvider.notifier).setUser(updated);
                if (!context.mounted) return;
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Contraseña actualizada')),
                );
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('No se pudo actualizar la contraseña: $e'),
                  ),
                );
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile content – professional compact horizontal layout
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileContent extends StatelessWidget {
  final UserModel user;
  final VoidCallback onEdit;
  final VoidCallback onPhotoTap;
  final VoidCallback onPassword;

  const _ProfileContent({
    required this.user,
    required this.onEdit,
    required this.onPhotoTap,
    required this.onPassword,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 720 ? 3 : 2;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeaderCard(
                    user: user,
                    onPhotoTap: onPhotoTap,
                    onEdit: onEdit,
                  ),
                  const SizedBox(height: 20),
                  _buildMainSection(cols),
                  const SizedBox(height: 20),
                  _buildActionsRow(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMainSection(int cols) {
    final items = <(String, String)>[];
    if ((user.cedula ?? '').trim().isNotEmpty) {
      items.add(('Cédula', user.cedula!.trim()));
    }
    if (user.fechaIngreso != null) {
      items.add((
        'Fecha de ingreso',
        DateFormat('dd/MM/yyyy').format(user.fechaIngreso!),
      ));
    }
    if (user.createdAt != null) {
      items.add((
        'Miembro desde',
        DateFormat('dd/MM/yyyy').format(user.createdAt!),
      ));
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return _CompactSection(
      icon: Icons.badge_outlined,
      title: 'Datos principales',
      child: _DataGrid(items: items, cols: cols),
    );
  }

  Widget _buildActionsRow() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPassword,
        icon: const Icon(Icons.lock_outline_rounded, size: 18),
        label: const Text('Contraseña'),
      ),
    );
  }
}

// ─── Header card ─────────────────────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  final UserModel user;
  final VoidCallback onPhotoTap;
  final VoidCallback onEdit;

  const _HeaderCard({
    required this.user,
    required this.onPhotoTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = user.nombreCompleto.trim().isEmpty
        ? 'Usuario'
        : user.nombreCompleto.trim();
    final email = user.email.trim();
    final phone = user.telefono.trim();
    final role = (user.role ?? '').trim();

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
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
                child: Stack(
                  key: ValueKey((user.fotoPersonalUrl ?? '').trim()),
                  clipBehavior: Clip.none,
                  children: [
                    UserAvatar(
                      radius: 32,
                      backgroundColor: scheme.primary,
                      imageUrl: user.fotoPersonalUrl,
                      child: Text(
                        getInitials(user.nombreCompleto),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.scaffoldBackgroundColor,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (email.isNotEmpty)
                        Flexible(
                          child: Text(
                            email,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.outline,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (email.isNotEmpty && phone.isNotEmpty)
                        Text(
                          ' · ',
                          style: TextStyle(fontSize: 12, color: scheme.outline),
                        ),
                      if (phone.isNotEmpty)
                        Text(
                          phone,
                          style: TextStyle(fontSize: 12, color: scheme.outline),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (role.isNotEmpty) _RolePill(role: role),
                      _StatusPill(blocked: user.blocked),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Editar perfil',
              style: IconButton.styleFrom(
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Compact section with labelled divider header ─────────────────────────────

class _CompactSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _CompactSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: scheme.primary),
            const SizedBox(width: 6),
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: scheme.primary,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Divider(height: 1, color: scheme.outlineVariant)),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(padding: const EdgeInsets.all(14), child: child),
        ),
      ],
    );
  }
}

// ─── Data grid: label-above-value cells, N columns ───────────────────────────

class _DataGrid extends StatelessWidget {
  final List<(String, String)> items;
  final int cols;

  const _DataGrid({required this.items, required this.cols});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final itemW = (constraints.maxWidth - spacing * (cols - 1)) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: 14,
          children: items
              .map((item) {
                return SizedBox(
                  width: itemW,
                  child: _DataCell(label: item.$1, value: item.$2),
                );
              })
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
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.outline,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ─── Pills ────────────────────────────────────────────────────────────────────

class _RolePill extends StatelessWidget {
  final String role;

  const _RolePill({required this.role});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          role.isEmpty ? 'Sin rol' : role,
          style: TextStyle(
            color: scheme.onPrimaryContainer,
            fontWeight: FontWeight.w800,
            fontSize: 11,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool blocked;

  const _StatusPill({required this.blocked});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = blocked ? scheme.errorContainer : scheme.secondaryContainer;
    final fg = blocked ? scheme.onErrorContainer : scheme.onSecondaryContainer;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          blocked ? 'Bloqueado' : 'Activo',
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w800,
            fontSize: 11,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}
