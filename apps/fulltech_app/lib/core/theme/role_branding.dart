import 'package:flutter/material.dart';

import '../auth/app_role.dart';
import 'app_colors.dart';

class RoleBranding {
  const RoleBranding({
    required this.role,
    required this.departmentName,
    required this.departmentAccentLabel,
    required this.primary,
    required this.secondary,
    required this.tertiary,
    required this.appBarStart,
    required this.appBarEnd,
    required this.drawerStart,
    required this.drawerEnd,
    required this.backgroundTop,
    required this.backgroundMiddle,
    required this.backgroundBottom,
    required this.glowA,
    required this.glowB,
    required this.glowC,
    required this.watermarkTitle,
    required this.watermarkSubtitle,
  });

  final AppRole role;
  final String departmentName;
  final String departmentAccentLabel;
  final Color primary;
  final Color secondary;
  final Color tertiary;
  final Color appBarStart;
  final Color appBarEnd;
  final Color drawerStart;
  final Color drawerEnd;
  final Color backgroundTop;
  final Color backgroundMiddle;
  final Color backgroundBottom;
  final Color glowA;
  final Color glowB;
  final Color glowC;
  final String watermarkTitle;
  final String watermarkSubtitle;

  LinearGradient get appBarGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [appBarStart, appBarEnd],
  );

  Color get appBarStartDark =>
      Color.alphaBlend(tertiary.withValues(alpha: 0.34), appBarStart);

  Color get appBarEndDark =>
      Color.alphaBlend(tertiary.withValues(alpha: 0.26), appBarEnd);

  Color get appBarSolidColor =>
      Color.alphaBlend(tertiary.withValues(alpha: 0.30), appBarEnd);

  Color get drawerSolidColor => Color.lerp(drawerStart, drawerEnd, 0.68)!;

  LinearGradient get appBarDarkGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [appBarStartDark, appBarEndDark],
  );

  LinearGradient get drawerGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [drawerStart, drawerEnd],
  );
}

RoleBranding resolveRoleBranding(AppRole role) {
  switch (role) {
    case AppRole.cajero:
    case AppRole.vendedor:
      return const RoleBranding(
        role: AppRole.cajero,
        departmentName: 'Punto de venta',
        departmentAccentLabel: 'Facturacion, caja y atencion al cliente',
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        tertiary: AppColors.primaryDark,
        appBarStart: AppColors.primaryDark,
        appBarEnd: AppColors.primary,
        drawerStart: AppColors.primaryDark,
        drawerEnd: AppColors.primary,
        backgroundTop: AppColors.primarySoft,
        backgroundMiddle: AppColors.surfaceAlt,
        backgroundBottom: AppColors.background,
        glowA: Color(0x331957E6),
        glowB: Color(0x220E5261),
        glowC: Color(0x260B2A3A),
        watermarkTitle: 'POS',
        watermarkSubtitle: 'Operaciones de venta claras y confiables',
      );
    case AppRole.tecnico:
      return const RoleBranding(
        role: AppRole.tecnico,
        departmentName: 'Departamento Tecnico',
        departmentAccentLabel: 'Operacion precisa y seguimiento en campo',
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        tertiary: AppColors.primaryDark,
        appBarStart: AppColors.primaryDark,
        appBarEnd: AppColors.primary,
        drawerStart: AppColors.primaryDark,
        drawerEnd: AppColors.primary,
        backgroundTop: AppColors.primarySoft,
        backgroundMiddle: AppColors.surfaceAlt,
        backgroundBottom: AppColors.background,
        glowA: Color(0x331957E6),
        glowB: Color(0x220E5261),
        glowC: Color(0x260B2A3A),
        watermarkTitle: 'TECNICO',
        watermarkSubtitle: 'Ritmo estable para trabajo de alto enfoque',
      );
    case AppRole.admin:
    case AppRole.asistente:
      return const RoleBranding(
        role: AppRole.admin,
        departmentName: 'Departamento de Administracion',
        departmentAccentLabel: 'Control, coordinacion y vision operativa',
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        tertiary: AppColors.primaryDark,
        appBarStart: AppColors.primaryDark,
        appBarEnd: AppColors.primary,
        drawerStart: AppColors.primaryDark,
        drawerEnd: AppColors.primary,
        backgroundTop: AppColors.primarySoft,
        backgroundMiddle: AppColors.surfaceAlt,
        backgroundBottom: AppColors.background,
        glowA: Color(0x331957E6),
        glowB: Color(0x220E5261),
        glowC: Color(0x260B2A3A),
        watermarkTitle: 'ADMINISTRACION',
        watermarkSubtitle: 'Calma visual para decisiones y supervision',
      );
    case AppRole.marketing:
      return const RoleBranding(
        role: AppRole.marketing,
        departmentName: 'Departamento de Marketing',
        departmentAccentLabel: 'Comunicacion, marca y presencia digital',
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        tertiary: AppColors.primaryDark,
        appBarStart: AppColors.primaryDark,
        appBarEnd: AppColors.primary,
        drawerStart: AppColors.primaryDark,
        drawerEnd: AppColors.primary,
        backgroundTop: AppColors.primarySoft,
        backgroundMiddle: AppColors.surfaceAlt,
        backgroundBottom: AppColors.background,
        glowA: Color(0x331957E6),
        glowB: Color(0x220E5261),
        glowC: Color(0x260B2A3A),
        watermarkTitle: 'MARKETING',
        watermarkSubtitle: 'Un lenguaje visual sereno y contemporaneo',
      );
    case AppRole.unknown:
      return const RoleBranding(
        role: AppRole.unknown,
        departmentName: 'Espacio de trabajo FullTech',
        departmentAccentLabel: 'Experiencia general de trabajo',
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        tertiary: AppColors.primaryDark,
        appBarStart: AppColors.primaryDark,
        appBarEnd: AppColors.primary,
        drawerStart: AppColors.primaryDark,
        drawerEnd: AppColors.primary,
        backgroundTop: AppColors.primarySoft,
        backgroundMiddle: AppColors.surfaceAlt,
        backgroundBottom: AppColors.background,
        glowA: Color(0x331957E6),
        glowB: Color(0x220E5261),
        glowC: Color(0x260B2A3A),
        watermarkTitle: 'FULLTECH',
        watermarkSubtitle: 'Tecnologia confiable, moderna y amable',
      );
  }
}
