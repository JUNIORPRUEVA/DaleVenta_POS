import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Phone-only navigation; callbacks keep the existing permission and auth flow.
class MobileDrawerAccountFooter extends StatelessWidget {
  const MobileDrawerAccountFooter({
    super.key,
    required this.canManageUsers,
    required this.onProfile,
    required this.onUsers,
    required this.onSettings,
    required this.onLogout,
  });

  final bool canManageUsers;
  final VoidCallback onProfile;
  final VoidCallback onUsers;
  final VoidCallback onSettings;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    Widget glyph(String name) => ImageIcon(
      AssetImage('assets/image/mobile_navigation/$name.png'),
      color: AppColors.primary,
      size: 20,
    );
    Widget row(
      String label,
      String image,
      VoidCallback onTap,
      Widget trailing,
    ) => Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              height: 48,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    glyph(image),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        trailing,
      ],
    );
    return Material(
      key: const ValueKey('phone-drawer-account-footer'),
      color: AppColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Divider(height: 1, color: AppColors.border),
          row(
            'Perfil',
            'profile',
            onProfile,
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Configuración',
                  onPressed: onSettings,
                  icon: glyph('settings'),
                ),
                IconButton(
                  tooltip: 'Cerrar sesión',
                  onPressed: onLogout,
                  icon: const ImageIcon(
                    AssetImage('assets/image/mobile_navigation/logout_outline.png'),
                    size: 20,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          if (canManageUsers) ...[
            const Divider(height: 1, color: AppColors.border),
            row(
              'Usuario',
              'users',
              onUsers,
              const SizedBox(width: 12),
            ),
          ],
        ],
      ),
    );
  }
}
