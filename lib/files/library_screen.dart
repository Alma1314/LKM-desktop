import 'package:island/files/categories.dart';
import 'package:island/core/api/search_api.dart';
import 'package:island/shared/widgets/content/markdown_remote_image.dart';
import 'package:mime/mime.dart';
import 'dart:io';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
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

typedef LibraryFilter = ({
  String? status,
  String sort,
  int page,
  String? category,
  String? mime,
});

final libraryFilesProvider = FutureProvider.autoDispose
    .family<ApiPage<LkmFile>, LibraryFilter>((ref, filter) {
      final session = ref.watch(lkmApiSessionProvider);
      return session.run(
        () => ref
            .watch(filesApiProvider)
            .files(
              status: filter.status,
              sort: filter.sort,
              page: filter.page,
              categoryId: filter.category,
              mimePrefix: filter.mime,
            ),
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
/// and newest/downloads sorting, with the website's shared category IDs.
@RoutePage()
class LibraryScreen extends HookConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = useState<String?>(null);
    final sort = useState('newest');
    final number = useState(1);
    final category = useState<String?>(null);
    final mime = useState<String?>(null);
    final grid = useState(false);
    final searchText = useTextEditingController();
    final query = useState('');
    final searchEpoch = useState(0);
    final search = useMemoized(
      () => query.value.isEmpty
          ? Future.value(const ApiPage<SearchHit>.empty())
          : ref
                .read(lkmApiSessionProvider)
                .run(
                  () =>
                      SearchApi(ref.read(lkmApiSessionProvider).client).search(
                        query.value,
                        contentType: 'library_file',
                        page: number.value,
                      ),
                ),
      [query.value, number.value, searchEpoch.value],
    );
    final hits = useFuture(search);
    final busy = useState(false);
    final filter = (
      status: status.value,
      sort: sort.value,
      page: number.value,
      category: category.value,
      mime: mime.value,
    );
    final page = ref.watch(libraryFilesProvider(filter));

    return AppScaffold(
      isNoBackground: false,
      appBar: AppBar(
        leading: const AutoLeadingButton(),
        title: Text('library.title'.tr()),
        actions: [
          IconButton(
            tooltip: 'libraryMore.grid'.tr(),
            onPressed: () => grid.value = !grid.value,
            icon: const Icon(Icons.grid_view),
          ),
          IconButton(
            tooltip: 'libraryMore.upload'.tr(),
            onPressed: busy.value
                ? null
                : () async {
                    busy.value = true;
                    try {
                      await _upload(ref, categoryId: category.value ?? '');
                      ref.invalidate(libraryFilesProvider);
                    } catch (e) {
                      if (context.mounted) showSnackBar('$e');
                    } finally {
                      if (context.mounted) busy.value = false;
                    }
                  },
            icon: const Icon(Icons.upload_file),
          ),
        ],
      ),
      body: Column(
        children: [
          if (busy.value) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: searchText,
              decoration: InputDecoration(
                labelText: 'libraryMore.search'.tr(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    query.value = searchText.text.trim();
                    number.value = 1;
                  },
                ),
              ),
              onSubmitted: (v) {
                query.value = v.trim();
                number.value = 1;
              },
            ),
          ),
          if (query.value.isEmpty)
            Wrap(
              spacing: 8,
              children: [
                if (category.value != null)
                  ActionChip(
                    label: Text('libraryMore.back'.tr()),
                    onPressed: () {
                      category.value = fileCategories
                          .firstWhere((c) => c.id == category.value)
                          .parent;
                      number.value = 1;
                    },
                  ),
                for (final c in fileCategories.where(
                  (c) => c.parent == category.value,
                ))
                  ActionChip(
                    label: Text('libraryMore.categories.${c.key}'.tr()),
                    onPressed: () {
                      category.value = c.id;
                      number.value = 1;
                    },
                  ),
              ],
            ),
          if (query.value.isEmpty)
            DropdownButton<String?>(
              value: mime.value,
              items: [
                for (final (value, label) in <(String?, String)>[
                  (null, 'allTypes'),
                  ('image/', 'images'),
                  ('application/pdf', 'pdf'),
                  ('text/', 'text'),
                  ('audio/', 'audio'),
                  ('video/', 'video'),
                ])
                  DropdownMenuItem(
                    value: value,
                    child: Text('libraryMore.$label'.tr()),
                  ),
              ],
              onChanged: (value) {
                mime.value = value;
                number.value = 1;
              },
            ),
          if (query.value.isEmpty)
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
                      onSelectionChanged: (selection) {
                        status.value = selection.first;
                        number.value = 1;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: sort.value,
                    onChanged: (value) {
                      if (value != null) {
                        sort.value = value;
                        number.value = 1;
                      }
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
                searchEpoch.value++;
              },
              child: query.value.isNotEmpty
                  ? hits.hasError
                        ? _Message(text: '${hits.error}')
                        : !hits.hasData
                        ? const Center(child: CircularProgressIndicator())
                        : ListView(
                            children: [
                              for (final hit in hits.data!.items)
                                ListTile(
                                  title: Text(hit.title),
                                  subtitle: Text(hit.excerpt),
                                  onTap: () => context.router.push(
                                    LibraryFileRoute(id: hit.id),
                                  ),
                                ),
                            ],
                          )
                  : page.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, _) => _Message(text: '$error'),
                      data: (result) {
                        if (result.items.isEmpty) {
                          return _Message(text: 'library.empty'.tr());
                        }
                        Widget tile(LkmFile file) => ListTile(
                          leading: Icon(_iconFor(file.mimeType)),
                          title: Text(file.originalName),
                          subtitle: Text(
                            '${_size(file.size)} · ${file.downloadCount}',
                          ),
                          trailing: _StatusChip(status: file.status),
                          onTap: () => context.router.push(
                            LibraryFileRoute(id: file.id),
                          ),
                        );
                        if (grid.value)
                          return GridView.extent(
                            maxCrossAxisExtent: 400,
                            childAspectRatio: 2.8,
                            children: [
                              for (final file in result.items)
                                Card(child: tile(file)),
                            ],
                          );
                        return ListView(
                          children: [
                            for (final file in result.items) tile(file),
                          ],
                        );
                      },
                    ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'libraryMore.previous'.tr(),
                onPressed: number.value > 1 ? () => number.value-- : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('${'libraryMore.page'.tr()} ${number.value}'),
              IconButton(
                tooltip: 'libraryMore.next'.tr(),
                onPressed:
                    (query.value.isEmpty
                            ? page.value?.hasMore
                            : hits.data?.hasMore) ==
                        true
                    ? () => number.value++
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
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
        final session = ref.read(lkmApiSessionProvider);
        final info = await session.run(() => api.downloadUrl(value.id));
        if (info.isPresigned) {
          await launchUrlString(info.url, mode: LaunchMode.externalApplication);
        } else {
          final bytes = await session.run(() => api.downloadBytes(value.id));
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
        if (context.mounted) busy.value = false;
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
            if (value.isApproved && value.mimeType.startsWith('image/'))
              MarkdownRemoteImage(
                uri: Uri.parse(ref.read(filesApiProvider).previewUrl(value.id)),
              ),
            if (value.isApproved && !value.mimeType.startsWith('image/'))
              OutlinedButton.icon(
                icon: const Icon(Icons.preview),
                label: Text('libraryMore.preview'.tr()),
                onPressed: busy.value
                    ? null
                    : () async {
                        busy.value = true;
                        try {
                          final extension = value.mimeType == 'application/pdf'
                              ? 'pdf'
                              : value.mimeType.startsWith('text/')
                              ? 'txt'
                              : value.mimeType == 'audio/mpeg'
                              ? 'mp3'
                              : value.mimeType == 'video/mp4'
                              ? 'mp4'
                              : null;
                          if (extension == null)
                            throw StateError(
                              'libraryMore.previewUnsupported'.tr(),
                            );
                          final bytes = await ref
                              .read(lkmApiSessionProvider)
                              .run(
                                () => ref
                                    .read(filesApiProvider)
                                    .downloadBytes(value.id),
                              );
                          final directory = await getTemporaryDirectory();
                          final output = File(
                            '${directory.path}/library-${DateTime.now().microsecondsSinceEpoch}.$extension',
                          );
                          await output.writeAsBytes(bytes);
                          final result = await OpenFile.open(output.path);
                          if (result.type != ResultType.done)
                            throw StateError(result.message);
                        } catch (e) {
                          if (context.mounted) showSnackBar('$e');
                        } finally {
                          if (context.mounted) busy.value = false;
                        }
                      },
              ),
            OutlinedButton.icon(
              onPressed: busy.value
                  ? null
                  : () async {
                      busy.value = true;
                      try {
                        await _upload(ref, versionOf: value.id);
                        ref.invalidate(libraryVersionsProvider(id));
                        ref.invalidate(libraryFilesProvider);
                      } catch (e) {
                        if (context.mounted) showSnackBar('$e');
                      } finally {
                        if (context.mounted) busy.value = false;
                      }
                    },
              icon: const Icon(Icons.upload_file),
              label: Text('libraryMore.uploadVersion'.tr()),
            ),
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
                            onTap: () => context.router.push(
                              LibraryFileRoute(id: version.id),
                            ),
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

Future<void> _upload(
  WidgetRef ref, {
  String categoryId = '',
  String? versionOf,
}) async {
  final picked = await FilePicker.pickFile();
  if (picked == null) return;
  final bytes = await picked.xFile.readAsBytes();
  final mime =
      lookupMimeType(picked.name, headerBytes: bytes) ??
      'application/octet-stream';
  final api = ref.read(filesApiProvider);
  await ref
      .read(lkmApiSessionProvider)
      .run(
        () => versionOf == null
            ? api.upload(
                bytes: bytes,
                originalName: picked.name,
                mimeType: mime,
                categoryId: categoryId,
              )
            : api.uploadVersion(
                versionOf,
                bytes: bytes,
                originalName: picked.name,
                mimeType: mime,
              ),
      );
}
