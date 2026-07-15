import 'package:flutter/material.dart';

import '../marketing_campaign_models.dart';

/// Campaign preview types
enum PreviewType { facebookFeed, instagramFeed, instagramStory, instagramReels }

/// Premium campaign preview panel - shows ads as they appear in Meta platforms
class CampaignPreviewPanel extends StatefulWidget {
  final MarketingCampaign campaign;
  final PreviewType previewType;
  final VoidCallback? onTypeChange;

  const CampaignPreviewPanel({
    required this.campaign,
    this.previewType = PreviewType.facebookFeed,
    this.onTypeChange,
    super.key,
  });

  @override
  State<CampaignPreviewPanel> createState() => _CampaignPreviewPanelState();
}

class _CampaignPreviewPanelState extends State<CampaignPreviewPanel> {
  late PreviewType _currentType;

  @override
  void initState() {
    super.initState();
    _currentType = widget.previewType;
  }

  @override
  void didUpdateWidget(CampaignPreviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.campaign.id != widget.campaign.id) {
      _currentType = widget.previewType;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          // Preview type selector
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _PreviewTypeButton(
                  type: PreviewType.facebookFeed,
                  icon: Icons.feed_rounded,
                  label: 'Feed FB',
                  isSelected: _currentType == PreviewType.facebookFeed,
                  onTap: () =>
                      setState(() => _currentType = PreviewType.facebookFeed),
                ),
                _PreviewTypeButton(
                  type: PreviewType.instagramFeed,
                  icon: Icons.grid_3x3_rounded,
                  label: 'Feed IG',
                  isSelected: _currentType == PreviewType.instagramFeed,
                  onTap: () =>
                      setState(() => _currentType = PreviewType.instagramFeed),
                ),
                _PreviewTypeButton(
                  type: PreviewType.instagramStory,
                  icon: Icons.rectangle_rounded,
                  label: 'Story',
                  isSelected: _currentType == PreviewType.instagramStory,
                  onTap: () =>
                      setState(() => _currentType = PreviewType.instagramStory),
                ),
                _PreviewTypeButton(
                  type: PreviewType.instagramReels,
                  icon: Icons.play_arrow_rounded,
                  label: 'Reels',
                  isSelected: _currentType == PreviewType.instagramReels,
                  onTap: () =>
                      setState(() => _currentType = PreviewType.instagramReels),
                ),
              ],
            ),
          ),
          // Divider
          Divider(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: 0.15),
          ),
          // Preview content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Center(child: _buildPreview(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(BuildContext context) {
    switch (_currentType) {
      case PreviewType.facebookFeed:
        return _FacebookFeedPreview(campaign: widget.campaign);
      case PreviewType.instagramFeed:
        return _InstagramFeedPreview(campaign: widget.campaign);
      case PreviewType.instagramStory:
        return _InstagramStoryPreview(campaign: widget.campaign);
      case PreviewType.instagramReels:
        return _InstagramReelsPreview(campaign: widget.campaign);
    }
  }
}

/// Preview type selector button
class _PreviewTypeButton extends StatefulWidget {
  final PreviewType type;
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _PreviewTypeButton({
    required this.type,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_PreviewTypeButton> createState() => _PreviewTypeButtonState();
}

class _PreviewTypeButtonState extends State<_PreviewTypeButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    if (widget.isSelected) _controller.forward();
  }

  @override
  void didUpdateWidget(_PreviewTypeButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSelected != widget.isSelected) {
      if (widget.isSelected) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ScaleTransition(
      scale: Tween<double>(begin: 1, end: 1.08).animate(_controller),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 20,
                  color: widget.isSelected
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
                ),
                const SizedBox(height: 2),
                Text(
                  widget.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: widget.isSelected
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                    fontWeight: widget.isSelected
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Facebook feed preview mock
class _FacebookFeedPreview extends StatelessWidget {
  final MarketingCampaign campaign;

  const _FacebookFeedPreview({required this.campaign});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Facebook header
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: scheme.primary.withValues(alpha: 0.3),
                  child: Icon(Icons.business, size: 16, color: scheme.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tu Negocio',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Anuncio patrocinado',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.more_vert, size: 16, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
          // Image
          if ((campaign.finalDesignUrl ?? '').isNotEmpty)
            Container(
              width: 320,
              height: 240,
              color: scheme.surface,
              child: Image.network(
                campaign.finalDesignUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    'Imagen no disponible',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            ),
          // Ad copy
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((campaign.headline ?? '').isNotEmpty)
                  Text(
                    campaign.headline!,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if ((campaign.primaryText ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      campaign.primaryText!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                if ((campaign.description ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      campaign.description!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        'Enviar WhatsApp',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Instagram feed preview mock
class _InstagramFeedPreview extends StatelessWidget {
  final MarketingCampaign campaign;

  const _InstagramFeedPreview({required this.campaign});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Instagram header
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: scheme.primary.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'tu_negocio',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Patrocinado',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Image
          if ((campaign.finalDesignUrl ?? '').isNotEmpty)
            Container(
              width: 280,
              height: 280,
              color: scheme.surface,
              child: Image.network(
                campaign.finalDesignUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    'Imagen no disponible',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            ),
          // Actions
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.favorite_border,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.mode_comment_outlined,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      Icons.share_outlined,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ],
                ),
                Icon(
                  Icons.bookmark_border,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
          // Caption
          if ((campaign.headline ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Text(
                campaign.headline!,
                style: Theme.of(context).textTheme.labelSmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

/// Instagram story preview mock
class _InstagramStoryPreview extends StatelessWidget {
  final MarketingCampaign campaign;

  const _InstagramStoryPreview({required this.campaign});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 200,
      height: 350,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          // Story image
          if ((campaign.finalDesignUrl ?? '').isNotEmpty)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Image.network(
                campaign.finalDesignUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    'Imagen no disponible',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            ),
          // Text overlay
          Positioned(
            bottom: 40,
            left: 10,
            right: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((campaign.headline ?? '').isNotEmpty)
                  Text(
                    campaign.headline!,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if ((campaign.primaryText ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      campaign.primaryText!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          // CTA button
          Positioned(
            bottom: 10,
            left: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Center(
                child: Text(
                  'Enviar WhatsApp',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w600,
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

/// Instagram reels preview mock
class _InstagramReelsPreview extends StatelessWidget {
  final MarketingCampaign campaign;

  const _InstagramReelsPreview({required this.campaign});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: 200,
      height: 350,
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          // Video thumbnail
          if ((campaign.finalDesignUrl ?? '').isNotEmpty)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Image.network(
                campaign.finalDesignUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Center(
                  child: Text(
                    'Imagen no disponible',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
              ),
            ),
          // Play button overlay
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                size: 28,
                color: scheme.primary,
              ),
            ),
          ),
          // Text overlay
          Positioned(
            bottom: 40,
            left: 10,
            right: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if ((campaign.headline ?? '').isNotEmpty)
                  Text(
                    campaign.headline!,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          // Reels badge
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_arrow_rounded, size: 12, color: Colors.white),
                  const SizedBox(width: 2),
                  Text(
                    'Reel',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
