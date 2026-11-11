import 'dart:async';
import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mime/mime.dart';
import 'package:island/community/user_pod.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/blog_api.dart';
import 'package:island/core/config.dart';
import 'package:island/editor/document_store.dart';
import 'package:island/posts/widgets/compose/compose_shared.dart';
import 'package:island/posts/widgets/compose/quill_content_editor.dart';
import 'package:island/shared/widgets/content/markdown.dart';

@RoutePage()
class SeriesEditorScreen extends ConsumerWidget {
  const SeriesEditorScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(lkmMeProvider);
    return me.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('$e')),
      data: (user) => user == null
          ? Scaffold(
              appBar: AppBar(),
              body: Center(child: Text('seriesEditor.signIn'.tr())),
            )
          : _Editor(
              key: ValueKey('${ref.watch(lkmServerUrlProvider)}:${user.id}'),
              userId: user.id,
            ),
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({super.key, required this.userId});
  final String userId;
  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  late final ComposeState compose;
  late final DocumentStore store;
  final series = TextEditingController();
  final path = TextEditingController();
  Timer? timer;
  String id = '';
  String? savedContent;
  bool busy = false;
  bool loading = false;
  int mode = 0;
  String? error;
  List<String> paths = [];

  BlogApi get api => BlogApi(ref.read(lkmApiSessionProvider).client);
  Map<String, dynamic> get document => {
    'id': id,
    'series': series.text,
    'path': path.text,
    'title': compose.titleController.text,
    'content': compose.contentController.text,
  };

  @override
  void initState() {
    super.initState();
    store = DocumentStore(
      ref.read(sharedPreferencesProvider),
      ref.read(lkmServerUrlProvider),
      widget.userId,
    );
    compose = ComposeLogic.createState();
    newDocument();
    for (final c in [
      compose.contentController,
      compose.titleController,
      series,
      path,
    ]) {
      c.addListener(changed);
    }
  }

  void changed() {
    if (loading) return;
    timer?.cancel();
    timer = Timer(const Duration(seconds: 2), () async {
      try {
        await store.save(document);
        if (!mounted) return;
        if (series.text.isNotEmpty &&
            path.text.isNotEmpty &&
            !busy &&
            compose.contentController.text != savedContent)
          await run(save);
      } catch (e) {
        if (mounted) setState(() => error = '$e');
      }
    });
  }

  void newDocument() {
    loading = true;
    id = DateTime.now().microsecondsSinceEpoch.toString();
    path.clear();
    compose.titleController.clear();
    compose.contentController.clear();
    savedContent = null;
    loading = false;
  }

  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    timer?.cancel();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      loading = false;
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    final current = document;
    BlogApi.validatePath(path.text);
    if (series.text.trim().isEmpty)
      throw StateError('seriesEditor.seriesRequired'.tr());
    // Do not overwrite an existing remote file when creating a new local draft.
    if (savedContent == null) {
      final detail = await ref
          .read(lkmApiSessionProvider)
          .run(() => api.detail(series.text));
      if (detail.paths.contains(path.text))
        throw StateError('seriesEditor.openExisting'.tr());
    }
    if (savedContent != null) {
      final remote = await ref
          .read(lkmApiSessionProvider)
          .run(() => api.content(series.text, path.text));
      if (remote != savedContent)
        throw StateError('seriesEditor.conflict'.tr());
    }
    await ref
        .read(lkmApiSessionProvider)
        .run(
          () => api.save(
            current['series'] as String,
            current['path'] as String,
            current['content'] as String,
          ),
        );
    savedContent = current['content'] as String;
    await store.save(current, snapshot: true);
    if (mounted) setState(() {});
  }

  Future<void> openRemote(String name) async {
    final content = await ref
        .read(lkmApiSessionProvider)
        .run(() => api.content(series.text, name));
    await store.save(document);
    loading = true;
    id = '${series.text}/$name';
    path.text = name;
    compose.titleController.text =
        RegExp(r'^# +(.+)$', multiLine: true).firstMatch(content)?.group(1) ??
        '';
    compose.contentController.text = content;
    savedContent = content;
    loading = false;
    await store.save(document, snapshot: true);
  }

  Future<void> image() async {
    final picked = await FilePicker.pickFiles(type: FileType.image);
    if (picked.isEmpty) return;
    final file = picked.first;
    final bytes = await file.xFile.readAsBytes();
    if (bytes.isEmpty) return;
    final mime = lookupMimeType(file.name, headerBytes: bytes) ?? '';
    if (!mime.startsWith('image/'))
      throw const FormatException('Expected image');
    final files = ref.read(filesApiProvider);
    final uploaded = await ref
        .read(lkmApiSessionProvider)
        .run(
          () => files.upload(
            bytes: bytes,
            originalName: file.name,
            mimeType: mime,
          ),
        );
    if (!mounted) return;
    final markdown =
        '\n![${file.name.replaceAll(RegExp(r'[\[\]]'), '')}](${files.previewUrl(uploaded.id)})\n';
    final controller = compose.contentController;
    if (mode == 1) {
      final selection = controller.selection;
      final start = selection.isValid
          ? selection.start
          : controller.text.length;
      final end = selection.isValid ? selection.end : start;
      controller.value = TextEditingValue(
        text: controller.text.replaceRange(start, end, markdown),
        selection: TextSelection.collapsed(offset: start + markdown.length),
      );
    } else {
      compose.insertContent(markdown);
    }
    setState(() => error = 'seriesEditor.imagePending'.tr());
  }

  Future<void> history() async {
    final entries =
        store.documents().where((d) => d['id'] == id).firstOrNull?['history']
            as List? ??
        [];
    final chosen = await showDialog<Map>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('seriesEditor.localHistory'.tr()),
        children: [
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('seriesEditor.empty'.tr()),
            ),
          for (final entry in entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, entry),
              child: Text('${entry['time']} · ${entry['title']}'),
            ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    final restore = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('seriesEditor.restore'.tr()),
        content: SingleChildScrollView(
          child: MarkdownTextContent(content: chosen['content'] as String),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('seriesEditor.restore'.tr()),
          ),
        ],
      ),
    );
    if (restore == true && mounted) {
      await store.save(document, snapshot: true);
      compose.contentController.text = chosen['content'] as String;
      compose.titleController.text = chosen['title'] as String;
      await store.save(document);
      setState(() {});
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    // Every keystroke is also persisted on leaving, including before debounce.
    unawaited(store.save(document));
    series.dispose();
    path.dispose();
    ComposeLogic.dispose(compose);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(
        title: Text('seriesEditor.title'.tr()),
        actions: [
          IconButton(
            tooltip: 'seriesEditor.history'.tr(),
            onPressed: busy ? null : () => run(history),
            icon: const Icon(Icons.history),
          ),
          IconButton(
            tooltip: 'save'.tr(),
            onPressed: busy ? null : () => run(save),
            icon: const Icon(Icons.save),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    await save();
                    await ref
                        .read(lkmApiSessionProvider)
                        .run(
                          () => api.publish(
                            series.text,
                            path.text,
                            compose.titleController.text,
                          ),
                        );
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('seriesEditor.published'.tr())),
                      );
                  }),
            child: Text('seriesEditor.publish'.tr()),
          ),
        ],
      ),
      body: Column(
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 240,
                  child: TextField(
                    controller: series,
                    enabled: !busy && savedContent == null,
                    decoration: InputDecoration(
                      labelText: 'seriesEditor.series'.tr(),
                    ),
                  ),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          final detail = await ref
                              .read(lkmApiSessionProvider)
                              .run(() => api.detail(series.text));
                          if (detail.ownerId != widget.userId)
                            throw StateError('seriesEditor.ownerOnly'.tr());
                          setState(() => paths = detail.paths);
                        }),
                  child: Text('seriesEditor.load'.tr()),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          final title = compose.titleController.text.trim();
                          if (title.isEmpty)
                            throw StateError('seriesEditor.titleRequired'.tr());
                          series.text = await ref
                              .read(lkmApiSessionProvider)
                              .run(
                                () => api.createSeries(
                                  title,
                                  'desktop-${DateTime.now().microsecondsSinceEpoch}',
                                ),
                              );
                          paths = [];
                          await store.save(document);
                        }),
                  child: Text('seriesEditor.createSeries'.tr()),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          await store.save(document);
                          setState(newDocument);
                        }),
                  child: Text('seriesEditor.new'.tr()),
                ),
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          final selected =
                              await showDialog<Map<String, dynamic>>(
                                context: context,
                                builder: (context) => SimpleDialog(
                                  title: Text('seriesEditor.documents'.tr()),
                                  children: [
                                    for (final doc in store.documents())
                                      SimpleDialogOption(
                                        onPressed: () =>
                                            Navigator.pop(context, doc),
                                        child: Text(
                                          '${doc['title']} · ${doc['path']}',
                                        ),
                                      ),
                                  ],
                                ),
                              );
                          if (selected == null || !mounted) return;
                          await store.save(document);
                          loading = true;
                          id = selected['id'] as String;
                          series.text = selected['series'] as String;
                          path.text = selected['path'] as String;
                          compose.titleController.text =
                              selected['title'] as String;
                          compose.contentController.text =
                              selected['content'] as String;
                          savedContent = null;
                          if (series.text.isNotEmpty && path.text.isNotEmpty) {
                            // A restored local draft must be opened explicitly against current remote content.
                            final remote = await ref
                                .read(lkmApiSessionProvider)
                                .run(() => api.detail(series.text));
                            if (remote.paths.contains(path.text))
                              savedContent = await ref
                                  .read(lkmApiSessionProvider)
                                  .run(
                                    () => api.content(series.text, path.text),
                                  );
                          }
                          loading = false;
                          setState(() {});
                        }),
                  child: Text('seriesEditor.documents'.tr()),
                ),
                if (paths.isNotEmpty)
                  DropdownButton<String>(
                    hint: Text('seriesEditor.open'.tr()),
                    items: paths
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: busy
                        ? null
                        : (p) {
                            if (p != null) run(() => openRemote(p));
                          },
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: compose.titleController,
                    enabled: !busy,
                    decoration: InputDecoration(
                      labelText: 'seriesEditor.documentTitle'.tr(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: path,
                    enabled: !busy && savedContent == null,
                    decoration: InputDecoration(
                      labelText: 'seriesEditor.path'.tr(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SegmentedButton<int>(
                segments: [
                  for (final (value, key) in [
                    (0, 'edit'),
                    (1, 'source'),
                    (2, 'preview'),
                  ])
                    ButtonSegment(
                      value: value,
                      label: Text('seriesEditor.$key'.tr()),
                    ),
                ],
                selected: {mode},
                onSelectionChanged: (v) => setState(() => mode = v.first),
              ),
              IconButton(
                tooltip: 'seriesEditor.image'.tr(),
                onPressed: busy ? null : () => run(image),
                icon: const Icon(Icons.add_photo_alternate),
              ),
            ],
          ),
          Expanded(
            child: mode == 0
                ? QuillContentEditor(
                    state: compose,
                    enabled: !busy,
                    expands: true,
                  )
                : mode == 1
                ? TextField(
                    controller: compose.contentController,
                    enabled: !busy,
                    expands: true,
                    minLines: null,
                    maxLines: null,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.all(16),
                    ),
                  )
                : ValueListenableBuilder(
                    valueListenable: compose.contentController,
                    builder: (context, value, _) => SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: MarkdownTextContent(content: value.text),
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}
