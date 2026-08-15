import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_provider.dart';
import '../../core/routing/app_navigator.dart';
import '../../core/widgets/responsive_shell.dart';
import '../settings/data/cloud_backup_service.dart';

/// ShellRoute wrapper.
///
/// Mantiene el UX de cada pantalla (cada módulo maneja su propio Scaffold)
/// y evita romper navegación cuando el shell cambia.
class HomeShell extends ConsumerStatefulWidget {
  final Widget child;

  const HomeShell({super.key, required this.child});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  bool _autoBackupScheduled = false;

  void _scheduleAutomaticBackup() {
    if (_autoBackupScheduled) return;
    _autoBackupScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(
        ref.read(cloudBackupServiceProvider).createAutomaticBackupIfDue(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authStateProvider);
    if (!auth.isAuthenticated) {
      // Router redirect will send the user to /login; avoid rendering
      // role-protected shell widgets during this transition frame.
      return const SizedBox.shrink();
    }

    _scheduleAutomaticBackup();

    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await AppNavigator.handleSystemBack(context);
      },
      child: ResponsiveShell(child: widget.child),
    );
  }
}
