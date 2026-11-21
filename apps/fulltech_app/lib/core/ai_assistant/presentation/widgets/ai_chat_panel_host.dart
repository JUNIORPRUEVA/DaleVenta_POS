import 'package:flutter/material.dart';

/// Owns transient chat views so media and forms cannot cover the POS workspace.
class AiChatPanelHost extends StatelessWidget {
  const AiChatPanelHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(6),
    );
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) => MediaQuery(
          data: MediaQuery.of(context).copyWith(size: constraints.biggest),
          child: Theme(
            data: theme.copyWith(
              dialogTheme: theme.dialogTheme.copyWith(shape: shape),
              filledButtonTheme: FilledButtonThemeData(
                style: (theme.filledButtonTheme.style ?? const ButtonStyle())
                    .copyWith(shape: WidgetStatePropertyAll(shape)),
              ),
              textButtonTheme: TextButtonThemeData(
                style: (theme.textButtonTheme.style ?? const ButtonStyle())
                    .copyWith(shape: WidgetStatePropertyAll(shape)),
              ),
              inputDecorationTheme: theme.inputDecorationTheme.copyWith(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide:
                      theme.inputDecorationTheme.enabledBorder?.borderSide ??
                      const BorderSide(),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: theme.colorScheme.primary),
                ),
              ),
            ),
            child: Navigator(
              pages: [
                MaterialPage<void>(
                  key: const ValueKey('ai-chat-root'),
                  child: child,
                ),
              ],
              onDidRemovePage: (_) {},
            ),
          ),
        ),
      ),
    );
  }
}
