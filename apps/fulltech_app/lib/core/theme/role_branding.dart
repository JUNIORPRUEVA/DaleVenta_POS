import 'package:flutter/material.dart';

import '../auth/app_role.dart';

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
        primary: Color(0xFF0D6F86),
        secondary: Color(0xFF24A69A),
        tertiary: Color(0xFF0B2A3A),
        appBarStart: Color(0xFF0B2A3A),
        appBarEnd: Color(0xFF0D6F86),
        drawerStart: Color(0xFF092638),
        drawerEnd: Color(0xFF0D4F61),
        backgroundTop: Color(0xFFEAF5F8),
        backgroundMiddle: Color(0xFFF7FBFC),
        backgroundBottom: Color(0xFFEFF6F8),
        glowA: Color(0x3324A69A),
        glowB: Color(0x220D6F86),
        glowC: Color(0x260B2A3A),
        watermarkTitle: 'POS',
        watermarkSubtitle: 'Operaciones de venta claras y confiables',
      );
    case AppRole.tecnico:
      return const RoleBranding(
        role: AppRole.tecnico,
        departmentName: 'Departamento Tecnico',
        departmentAccentLabel: 'Operacion precisa y seguimiento en campo',
        primary: Color(0xFF1D5D86),
        secondary: Color(0xFF338EB7),
        tertiary: Color(0xFF0B2A3A),
        appBarStart: Color(0xFF0B2A3A),
        appBarEnd: Color(0xFF1D5D86),
        drawerStart: Color(0xFF092638),
        drawerEnd: Color(0xFF17465E),
        backgroundTop: Color(0xFFEAF2F8),
        backgroundMiddle: Color(0xFFF7FAFC),
        backgroundBottom: Color(0xFFEFF5F8),
        glowA: Color(0x33338EB7),
        glowB: Color(0x221D5D86),
        glowC: Color(0x240B2A3A),
        watermarkTitle: 'TECNICO',
        watermarkSubtitle: 'Ritmo estable para trabajo de alto enfoque',
      );
    case AppRole.admin:
    case AppRole.asistente:
      return const RoleBranding(
        role: AppRole.admin,
        departmentName: 'Departamento de Administracion',
        departmentAccentLabel: 'Control, coordinacion y vision operativa',
        primary: Color(0xFF0D6F86),
        secondary: Color(0xFF1D9AAA),
        tertiary: Color(0xFF0B2A3A),
        appBarStart: Color(0xFF0B2A3A),
        appBarEnd: Color(0xFF0D6F86),
        drawerStart: Color(0xFF092638),
        drawerEnd: Color(0xFF0D4F61),
        backgroundTop: Color(0xFFEAF5F8),
        backgroundMiddle: Color(0xFFF7FBFC),
        backgroundBottom: Color(0xFFEFF6F8),
        glowA: Color(0x331D9AAA),
        glowB: Color(0x220D6F86),
        glowC: Color(0x260B2A3A),
        watermarkTitle: 'ADMINISTRACION',
        watermarkSubtitle: 'Calma visual para decisiones y supervision',
      );
    case AppRole.marketing:
      return const RoleBranding(
        role: AppRole.marketing,
        departmentName: 'Departamento de Marketing',
        departmentAccentLabel: 'Comunicacion, marca y presencia digital',
        primary: Color(0xFF16746E),
        secondary: Color(0xFF2FA697),
        tertiary: Color(0xFF0B2A3A),
        appBarStart: Color(0xFF0B2A3A),
        appBarEnd: Color(0xFF16746E),
        drawerStart: Color(0xFF092638),
        drawerEnd: Color(0xFF165A55),
        backgroundTop: Color(0xFFEAF7F5),
        backgroundMiddle: Color(0xFFF8FCFB),
        backgroundBottom: Color(0xFFEFF7F6),
        glowA: Color(0x332FA697),
        glowB: Color(0x2216746E),
        glowC: Color(0x240B2A3A),
        watermarkTitle: 'MARKETING',
        watermarkSubtitle: 'Un lenguaje visual sereno y contemporaneo',
      );
    case AppRole.unknown:
      return const RoleBranding(
        role: AppRole.unknown,
        departmentName: 'Espacio de trabajo FullTech',
        departmentAccentLabel: 'Experiencia general de trabajo',
        primary: Color(0xFF0D6A82),
        secondary: Color(0xFF2B8EA8),
        tertiary: Color(0xFF0B2A3A),
        appBarStart: Color(0xFF0B2A3A),
        appBarEnd: Color(0xFF0D6A82),
        drawerStart: Color(0xFF092638),
        drawerEnd: Color(0xFF0D4B60),
        backgroundTop: Color(0xFFEAF4F8),
        backgroundMiddle: Color(0xFFF7FBFC),
        backgroundBottom: Color(0xFFEFF5F8),
        glowA: Color(0x332B8EA8),
        glowB: Color(0x220D6A82),
        glowC: Color(0x240B2A3A),
        watermarkTitle: 'FULLTECH',
        watermarkSubtitle: 'Tecnologia confiable, moderna y amable',
      );
  }
}
