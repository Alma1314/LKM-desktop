import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:logging/logging.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:solar_network_foundation/solar_network_foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/models.dart';

/// Bottom sheet presenting what's new in the currently installed / updated release.
class WhatsNewSheet extends StatelessWidget {
  const WhatsNewSheet({
    super.key,
    required this.release,
    this.previousVersion,
    this.onDismiss,
  });

  final DistributionReleaseInfo release;

  /// Version of the build this release replaced, if known.
  final String? previousVersion;

  /// Optional callback invoked when the user taps the primary dismissal button.
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = release.body.trim();

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SheetScaffold(
        titleText: 'whatsNew'.tr(),
        heightFactor: 0.75,
        actions: [
          if (release.htmlUrl?.isNotEmpty == true)
            IconButton(
              tooltip: 'openReleasePage'.tr(),
              onPressed: () => _openReleasePage(release.htmlUrl!),
              icon: const Icon(Symbols.open_in_new),
              style: IconButton.styleFrom(minimumSize: const Size(36, 36)),
            ),
        ],
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                children: [
                  _WhatsNewCard(
                    release: release,
                    previousVersion: previousVersion,
                  ),
                  const SizedBox(height: 12),
                  Card(
                    margin: EdgeInsets.zero,
                    color: scheme.surfaceContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SolarMarkdownContent(
                        content: body.isEmpty
                            ? 'noChangelogProvided'.tr()
                            : release.body,
                        textStyle: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.55,
                          color: scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                16 + MediaQuery.of(context).padding.bottom,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        if (onDismiss != null) {
                          onDismiss!();
                        } else {
                          Navigator.of(context).pop();
                        }
                      },
                      child: Text('ok'.tr()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openReleasePage(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      Logger.root.warning('[Solsynth Express] Cannot open release URL: $url');
    }
  }
}

class _WhatsNewCard extends StatelessWidget {
  const _WhatsNewCard({
    required this.release,
    required this.previousVersion,
  });

  final DistributionReleaseInfo release;
  final String? previousVersion;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final publishedAt = release.publishedAt ?? release.createdAt;
    final prevVer = previousVersion?.trim();
    final channel = release.channel.trim();

    return Card(
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Symbols.auto_awesome,
                    size: 22,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        release.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        release.tagName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (prevVer != null && prevVer.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    'updateInstalledVersion'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    prevVer,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Symbols.arrow_forward,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      release.tagName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (channel.isNotEmpty)
                  _MetaChip(
                    icon: Symbols.new_releases,
                    label: 'updateChannelLabel'.tr(args: [channel]),
                  ),
                _MetaChip(
                  icon: Symbols.calendar_today,
                  label: _formatDate(publishedAt),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
