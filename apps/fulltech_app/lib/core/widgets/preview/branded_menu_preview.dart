import 'package:flutter/material.dart';

import '../../ai_assistant/presentation/widgets/ai_assistant_dock_button.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../branded_menu_button.dart';

/// Vista aislada de presentación: no inicia sesión ni consulta datos de empresa.
void main() => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    home: const BrandedMenuPreview(),
  ),
);

class BrandedMenuPreview extends StatelessWidget {
  const BrandedMenuPreview({super.key});

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 900;
    return Scaffold(
      drawer: const Drawer(
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('Menú principal'),
          ),
        ),
      ),
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 8,
        backgroundColor: compact ? AppColors.primary : AppColors.surface,
        title: Builder(
          builder: (context) => BrandedMenuButton(
            onDark: compact,
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Información de la vista previa',
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Vista previa de diseño · sin datos de empresa'),
              ),
            ),
            color: compact ? AppColors.surface : AppColors.primary,
            icon: const Icon(Icons.info_outline_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const TextField(
                  decoration: InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    hintText: 'Buscar producto por nombre o código…',
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Vista previa de la cabecera',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Abre el menú desde la marca FullPOS.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Positioned(
            left: 24,
            bottom: 24,
            child: AiAssistantDockButton(
              compact: true,
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Botón de IA · vista previa de tamaño'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
