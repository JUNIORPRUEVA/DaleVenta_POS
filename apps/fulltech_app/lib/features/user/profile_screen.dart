import 'dart:typed_data';

import 'package:flutter/material.dart' hide GestureDetector;
import 'package:daleventa_pos/core/widgets/app_gesture_detector.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/auth/auth_repository.dart';
import '../../core/errors/user_safe_error_text.dart';
import '../../core/widgets/custom_app_bar.dart';
import '../../core/widgets/app_drawer.dart';
import '../../core/utils/media_url.dart';
import '../../core/utils/string_utils.dart';
import '../../core/models/user_model.dart';
import '../../core/theme/app_colors.dart';
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
      appBar: CustomAppBar(
        title: 'Mi Perfil',
        showLogo: false,
        // Elemento solo de muestra: sin acción ni navegación. La foto del
        // usuario se muestra únicamente en la tarjeta de cabecera.
        trailing: user == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ExcludeSemantics(
                  child: UserAvatar(
                    radius: 16,
                    backgroundColor: Colors.white24,
                    child: Text(
                      getInitials(user.nombreCompleto),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
      ),
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
                  SnackBar(
                    content: Text(
                      userSafeErrorMessage(
                        e,
                        fallback:
                            'No se pudo actualizar el perfil. Inténtalo nuevamente.',
                      ),
                    ),
                  ),
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
        SnackBar(
          content: Text(
            userSafeErrorMessage(
              e,
              fallback: 'No se pudo eliminar la foto. Inténtalo nuevamente.',
            ),
          ),
        ),
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
        SnackBar(
          content: Text(
            userSafeErrorMessage(
              e,
              fallback:
                  'No se pudo actualizar la foto. Inténtalo nuevamente.',
            ),
          ),
        ),
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
        SnackBar(
          content: Text(
            userSafeErrorMessage(
              e,
              fallback: 'No se pudo subir la foto. Inténtalo nuevamente.',
            ),
          ),
        ),
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
                    content: Text(
                      userSafeErrorMessage(
                        e,
                        fallback:
                            'No se pudo actualizar la contraseña. Inténtalo nuevamente.',
                      ),
                    ),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 26),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeaderCard(user: user, onPhotoTap: onPhotoTap, onEdit: onEdit),
              const SizedBox(height: 18),
              ..._buildDataSection(),
              const SizedBox(height: 18),
              const _SectionLabel(
                icon: Icons.shield_outlined,
                title: 'Seguridad',
              ),
              const SizedBox(height: 8),
              _WhiteCard(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: _PasswordRow(onPressed: onPassword),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDataSection() {
    final rows = <Widget>[];
    if ((user.cedula ?? '').trim().isNotEmpty) {
      rows.add(_InfoRow('Cédula', user.cedula!.trim()));
    }
    if (user.fechaIngreso != null) {
      rows.add(
        _InfoRow(
          'Fecha de ingreso',
          DateFormat('dd/MM/yyyy').format(user.fechaIngreso!),
        ),
      );
    }
    if (user.createdAt != null) {
      rows.add(
        _InfoRow(
          'Miembro desde',
          DateFormat('dd/MM/yyyy').format(user.createdAt!),
        ),
      );
    }
    if (rows.isEmpty) return const <Widget>[];

    return [
      const _SectionLabel(icon: Icons.badge_outlined, title: 'Datos principales'),
      const SizedBox(height: 8),
      _WhiteCard(
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
        child: Column(
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                const Divider(height: 1, thickness: 1, color: AppColors.border),
              rows[i],
            ],
          ],
        ),
      ),
    ];
  }
}

/// Tarjeta blanca base del perfil, alineada con el resto del módulo.
class _WhiteCard extends StatelessWidget {
  const _WhiteCard({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(color: AppColors.shadow, blurRadius: 12, offset: Offset(0, 3)),
        ],
      ),
      child: child,
    );
  }
}

/// Encabezado de sección: icono + rótulo en mayúsculas + línea.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: AppColors.secondary),
        const SizedBox(width: 6),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: AppColors.secondary,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Divider(height: 1, color: AppColors.border)),
      ],
    );
  }
}

/// Fila etiqueta/valor del bloque de información.
class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordRow extends StatelessWidget {
  const _PasswordRow({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.secondarySoft,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFDDEAFF)),
          ),
          child: const Icon(
            Icons.lock_outline_rounded,
            size: 17,
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Contraseña',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Actualiza tu clave de acceso',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
          onPressed: onPressed,
          style: _profileButtonStyle(),
          child: const Text('Cambiar'),
        ),
      ],
    );
  }
}

ButtonStyle _profileButtonStyle({bool tonal = true}) {
  if (!tonal) {
    return OutlinedButton.styleFrom(
      foregroundColor: AppColors.textSecondary,
      side: const BorderSide(color: AppColors.border),
      minimumSize: const Size(0, 38),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0),
    );
  }
  return OutlinedButton.styleFrom(
    foregroundColor: AppColors.secondary,
    backgroundColor: AppColors.secondarySoft,
    side: const BorderSide(color: Color(0xFFDDEAFF)),
    minimumSize: const Size(0, 38),
    padding: const EdgeInsets.symmetric(horizontal: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0),
  );
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
    final name = user.nombreCompleto.trim().isEmpty
        ? 'Usuario'
        : user.nombreCompleto.trim();
    final email = user.email.trim();
    final phone = user.telefono.trim();
    final role = (user.role ?? '').trim();
    final subtitle = [
      if (email.isNotEmpty) email,
      if (phone.isNotEmpty) phone,
    ].join(' · ');

    final avatar = GestureDetector(
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
              radius: 30,
              backgroundColor: AppColors.secondary,
              imageUrl: user.fotoPersonalUrl,
              child: Text(
                getInitials(user.nombreCompleto),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.photo_camera_outlined,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final identity = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        avatar,
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (role.isNotEmpty) _RolePill(role: role),
                  _StatusPill(blocked: user.blocked),
                ],
              ),
            ],
          ),
        ),
      ],
    );

    final editButton = OutlinedButton.icon(
      onPressed: onEdit,
      style: _profileButtonStyle(),
      icon: const Icon(Icons.edit_outlined, size: 16),
      label: const Text('Editar'),
    );

    return _WhiteCard(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: editButton),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: identity),
              const SizedBox(width: 12),
              editButton,
            ],
          );
        },
      ),
    );
  }
}

// ─── Pills ────────────────────────────────────────────────────────────────────

class _RolePill extends StatelessWidget {
  final String role;

  const _RolePill({required this.role});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.secondarySoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFDDEAFF)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        child: Text(
          role.isEmpty ? 'Sin rol' : role,
          style: const TextStyle(
            color: AppColors.secondary,
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 0,
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
    final bg = blocked ? AppColors.errorSoft : AppColors.successSoft;
    final border = blocked ? AppColors.errorBorder : AppColors.successBorder;
    final fg = blocked ? AppColors.error : AppColors.success;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        child: Text(
          blocked ? 'Bloqueado' : 'Activo',
          style: TextStyle(
            color: fg,
            fontWeight: FontWeight.w900,
            fontSize: 11,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}
