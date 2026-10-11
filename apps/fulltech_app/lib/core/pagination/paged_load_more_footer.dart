import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'paged_list_controller.dart';

class LoadMoreFooter extends StatelessWidget {
  const LoadMoreFooter({
    super.key,
    required this.loading,
    required this.hasMore,
    required this.label,
    required this.onLoadMore,
    this.loadingLabel = 'Cargando...',
    this.doneLabel,
    this.progressLabel,
    this.offline = false,
    this.offlineLabel,
    this.padding = const EdgeInsets.symmetric(vertical: 14),
  });

  final bool loading;
  final bool hasMore;
  final String label;
  final VoidCallback onLoadMore;
  final String loadingLabel;
  final String? doneLabel;
  final String? progressLabel;
  final bool offline;
  final String? offlineLabel;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusText = offline ? offlineLabel : progressLabel;
    return Padding(
      padding: padding,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (statusText != null && statusText.trim().isNotEmpty) ...[
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        statusText,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (hasMore)
                    TextButton.icon(
                      onPressed: loading ? null : onLoadMore,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      icon: loading
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.expand_more_rounded, size: 18),
                      label: Text(loading ? loadingLabel : label),
                    )
                  else if (doneLabel != null)
                    Text(
                      doneLabel!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PagedLoadMoreFooter<T> extends StatelessWidget {
  const PagedLoadMoreFooter({
    super.key,
    required this.state,
    required this.onLoadMore,
    this.label = 'Ver más',
    this.loadingLabel = 'Cargando...',
    this.doneLabel,
    this.offlineLabel,
    this.padding = const EdgeInsets.symmetric(vertical: 14),
  });

  final PagedListState<T> state;
  final VoidCallback onLoadMore;
  final String label;
  final String loadingLabel;
  final String? doneLabel;
  final String? offlineLabel;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (!state.hasItems &&
        !state.hasMore &&
        !state.isInitialLoading &&
        !state.isRefreshing) {
      return const SizedBox.shrink();
    }
    return LoadMoreFooter(
      loading:
          state.isLoadingMore || state.isInitialLoading || state.isRefreshing,
      hasMore: state.hasMore,
      label: label,
      loadingLabel: loadingLabel,
      doneLabel: doneLabel,
      progressLabel: 'Mostrando ${state.progressLabel}',
      offline: state.isOffline,
      offlineLabel: offlineLabel,
      padding: padding,
      onLoadMore: onLoadMore,
    );
  }
}
