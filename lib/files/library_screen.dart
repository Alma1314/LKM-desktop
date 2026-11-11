import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/files_api.dart';
import 'package:island/route.gr.dart';
import 'package:island/shared/widgets/alert.dart';
import 'package:island/shared/widgets/app_scaffold.dart';

typedef LibraryFilter = ({String? status, String sort});

final libraryFilesProvider = FutureProvider.autoDispose
    .family<ApiPage<LkmFile>, LibraryFilter>((ref, filter) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(
        () => ref
            .watch(filesApiProvider)
            .files(status: filter.status, sort: filter.sort),
      );
    });

final libraryFileProvider = FutureProvider.autoDispose.family<LkmFile, String>((
  ref,
  id,
) {
  final session = ref.watch(lkmApiSessionProvider);
  return session.run(() => ref.watch(filesApiProvider).file(id));
});

final libraryVersionsProvider = FutureProvider.autoDispose
    .family<List<LkmFile>, String>((ref, id) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(() => ref.watch(filesApiProvider).versions(id));
    });

/// The website's `/files` list: server-side visibility filtering, status tabs
/// and newest/downloads sorting. Categories are a static tree on the website,
/// so the desktop list leaves them out for now.
@RoutePage()
class LibraryScreen extends HookConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = useState<String?>(null);
    final sort = useState('newest');
    final filter = (status: status.value, sort: sort.value);
    final page = ref.watch(libraryFilesProvider(filter));

    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('library.title'.tr()),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<String?>(
                    segments: [
                      ButtonSegment(
                        value: null,
                        label: Text('library.filterAll'.tr()),
                      ),
                      ButtonSegment(
                        value: 'approved',
                        label: Text('library.filterApproved'.tr()),
                      ),
                      ButtonSegment(
                        value: 'pending',
                        label: Text('library.filterPending'.tr()),
                      ),
                    ],
                    selected: {status.value},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) =>
                        status.value = selection.first,
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: sort.value,
                  onChanged: (value) {
                    if (value != null) sort.value = value;
                  },
                  items: [
                    DropdownMenuItem(
                      value: 'newest',
                      child: Text('library.sortNewest'.tr()),
                    ),
                    DropdownMenuItem(
                      value: 'downloads',
                      child: Text('library.sortDownloads'.tr()),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(libraryFilesProvider(filter));
              },
              child: page.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _Message(text: '$error'),
                data: (result) {
                  if (result.items.isEmpty) {
                    return _Message(text: 'library.empty'.tr());
                  }
                  return ListView.builder(
                    itemCount: result.items.length,
                    itemBuilder: (context, index) {
                      final file = result.items[index];
                      return ListTile(
                        leading: Icon(_iconFor(file.mimeType)),
                        title: Text(file.originalName),
                        subtitle: Text(
                          [
                            if (file.categoryName.isNotEmpty) file.categoryName,
                            _size(file.size),
                            '${'library.downloads'.tr()}: '
                                '${file.downloadCount}',
                          ].join(' · '),
                        ),
                        trailing: _StatusChip(status: file.status),
                        onTap: () =>
                            context.router.push(LibraryFileRoute(id: file.id)),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

@RoutePage()
class LibraryFileScreen extends HookConsumerWidget {
  const LibraryFileScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final file = ref.watch(libraryFileProvider(id));
    final versions = ref.watch(libraryVersionsProvider(id));
    final busy = useState(false);

    Future<void> download(LkmFile value) async {
      busy.value = true;
      try {
        final api = ref.read(filesApiProvider);
        final info = await api.downloadUrl(value.id);
        if (info.isPresigned) {
          await launchUrlString(info.url, mode: LaunchMode.externalApplication);
        } else {
          final bytes = await api.downloadBytes(value.id);
          await FilePicker.saveFile(
            fileName: value.originalName,
            bytes: bytes,
            mimeType: value.mimeType,
          );
        }
        if (context.mounted) showSnackBar('library.downloadStarted'.tr());
      } catch (error) {
        if (context.mounted) showSnackBar('$error');
      } finally {
        busy.value = false;
      }
    }

    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('library.fileTitle'.tr()),
      ),
      body: file.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Message(text: '$error'),
        data: (value) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Icon(_iconFor(value.mimeType), size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    value.originalName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StatusChip(status: value.status),
              ],
            ),
            const SizedBox(height: 12),
            _Info('library.category'.tr(), value.categoryName),
            _Info('library.size'.tr(), _size(value.size)),
            _Info('library.uploader'.tr(), value.uploaderName),
            _Info(
              'library.downloads'.tr(),
              '${value.downloadCount} / ${value.viewCount}',
            ),
            if (value.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(value.description),
            ],
            if (value.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                children: [
                  for (final tag in value.tags) Chip(label: Text(tag)),
                ],
              ),
            ],
            if (value.reviewComment != null &&
                value.reviewComment!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '${'library.reviewComment'.tr()}: ${value.reviewComment}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: busy.value || !value.isApproved
                  ? null
                  : () => download(value),
              icon: const Icon(Icons.download),
              label: Text('library.download'.tr()),
            ),
            const SizedBox(height: 20),
            Text(
              'library.versions'.tr(),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            versions.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => _Message(text: '$error'),
              data: (items) => items.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('library.noVersions'.tr()),
                    )
                  : Column(
                      children: [
                        for (final version in items)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'v${version.version} · ${version.originalName}',
                            ),
                            subtitle: Text(_size(version.size)),
                            trailing: _StatusChip(status: version.status),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'approved' => Theme.of(context).colorScheme.primary,
      'rejected' => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.tertiary,
    };
    return Chip(
      label: Text(status),
      labelStyle: TextStyle(color: color),
      side: BorderSide(color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(child: Text(text, textAlign: TextAlign.center)),
    );
  }
}

IconData _iconFor(String mime) {
  if (mime.startsWith('image/')) return Icons.image_outlined;
  if (mime.startsWith('audio/')) return Icons.audio_file_outlined;
  if (mime.startsWith('video/')) return Icons.video_file_outlined;
  if (mime.contains('pdf')) return Icons.picture_as_pdf_outlined;
  if (mime.contains('zip') || mime.contains('tar')) {
    return Icons.folder_zip_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

String _size(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
