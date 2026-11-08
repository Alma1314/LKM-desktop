import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:island_ui_foundation/island_ui_foundation.dart';
import 'package:logging/logging.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:solar_network_foundation/solar_network_foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/models.dart';

/// Bottom sheet for a published Solsynth Express release.
///
/// The install operation is a callback so the presentation layer stays
/// reusable across host applications and can provide its own update
/// implementation. [artifact] is the build published for the platform this
/// process runs on; when it is null, or no [onInstall] is supplied, the sheet
/// only offers the release page.
class UpdateSheet extends StatefulWidget {
  const UpdateSheet({
    super.key,
    required this.release,
    this.currentVersion,
    this.artifact,
    this.onInstall,
  });

  final DistributionReleaseInfo release;

  /// Version of the running build, shown next to the release version so the
  /// reader can see what the update replaces. Null when it could not be read.
  final String? currentVersion;

  /// Build published for the host platform, if any.
  final DistributionArtifact? artifact;

  final Future<void> Function()? onInstall;

  @override
  State<UpdateSheet> createState() => _UpdateSheetState();
}

class _UpdateSheetState extends State<UpdateSheet> {
  /// Set while the install callback runs, so a second tap cannot start the
  /// download twice. The callback resolves once the install finishes.
  bool _installing = false;

  DistributionReleaseInfo get release => widget.release;

  bool get _canInstall =>
      !kIsWeb && widget.artifact != null && widget.onInstall != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final artifact = widget.artifact;
    final currentVersion = widget.currentVersion;
    final body = release.body.trim();

    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SheetScaffold(
        titleText: 'updateAvailable'.tr(),
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
                  _ReleaseCard(
                    release: release,
                    currentVersion: currentVersion,
                    size: artifact?.size,
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
                  if (_canInstall)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _installing ? null : _install,
                        icon: _installing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Symbols.system_update, size: 18),
                        label: Text('installUpdate'.tr()),
                      ),
                    )
                  else if (release.htmlUrl?.isNotEmpty == true)
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _openReleasePage(release.htmlUrl!),
                        icon: const Icon(Symbols.open_in_new, size: 18),
                        label: Text('openReleasePage'.tr()),
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

  Future<void> _install() async {
    final install = widget.onInstall;
    if (install == null || _installing) return;
    setState(() => _installing = true);
    try {
      await install();
    } finally {
      if (mounted) setState(() => _installing = false);
    }
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

/// Version, name and the facts a reader needs before installing: which build
/// this is, what it replaces, how big the download is.
class _ReleaseCard extends StatelessWidget {
  const _ReleaseCard({
    required this.release,
    required this.currentVersion,
    required this.size,
  });

  final DistributionReleaseInfo release;
  final String? currentVersion;
  final int? size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final publishedAt = release.publishedAt ?? release.createdAt;
    final currentVersion = this.currentVersion?.trim();
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
                    Symbols.system_update,
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
            if (currentVersion != null && currentVersion.isNotEmpty) ...[
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
                    currentVersion,
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
                if (size != null && size! > 0)
                  _MetaChip(
                    icon: Symbols.download,
                    label: 'updateDownloadSize'.tr(args: [
                      formatFileSize(size!),
                    ]),
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

  /// Day the release was published, written the one way every locale reads
  /// without a date-format dependency: `2026-10-18`.
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
