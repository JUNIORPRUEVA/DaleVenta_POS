import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/app_role.dart';
import '../../core/auth/auth_provider.dart';
import '../../core/widgets/fulltech_global_background.dart';

class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const FulltechGlobalBackground(
            role: AppRole.unknown,
            enableBlurEffects: true,
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.68),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x140F172A),
                          blurRadius: 22,
                          offset: Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              auth.restoringSession
                                  ? Icons.lock_clock_outlined
                                  : Icons.rocket_launch_outlined,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  auth.restoringSession
                                      ? 'Restaurando sesión...'
                                      : 'Abriendo DaleVenta POS...',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  auth.user == null
                                      ? 'Verificando acceso inicial.'
                                      : 'Entrando con tu sesión guardada.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2.6,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
