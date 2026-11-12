import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher_string.dart';

import 'package:island/community/feed_links.dart';
import 'package:island/core/api/api_providers.dart';
import 'package:island/core/api/search_api.dart';
import 'package:island/route.gr.dart';
import 'package:island/shared/widgets/layouts/sheet_scaffold.dart';

final searchApiProvider = Provider<SearchApi>((ref) {
  return SearchApi(ref.watch(lkmApiSessionProvider).client);
});

const _debounce = Duration(milliseconds: 400);

/// Scope tabs of the website's `/search`: the question bank is a mock there,
/// so only the three real backends are offered.
const _searchTypes = ['all', 'posts', 'columns', 'files'];
const _contentTypeFor = {
  'posts': 'discussion',
  'columns': 'column_post',
  'files': 'library_file',
};
const _detailTypes = {
  'discussion',
  'article',
  'column_post',
  'blog_post',
};

String _typeLabel(String type) => switch (type) {
  'posts' => 'searchMore.posts'.tr(),
  'columns' => 'searchMore.columns'.tr(),
  'files' => 'searchMore.files'.tr(),
  _ => 'searchMore.all'.tr(),
};

String _hitLabel(String contentType) => contentType == 'library_file'
    ? 'searchMore.files'.tr()
    : contentType == 'column_post'
    ? 'searchMore.columns'.tr()
    : 'searchMore.posts'.tr();

/// Full-text search across the site, opened from the community header.
class LkmSearchSheet extends HookConsumerWidget {
  const LkmSearchSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController();
    final session = ref.read(lkmApiSessionProvider);
    final serverHost = ref.read(lkmServerUrlProvider);
    final results = useState<List<SearchHit>>(const []);
    final loading = useState(false);
    final loadingMore = useState(false);
    final error = useState<String?>(null);
    final page = useState(1);
    final pages = useState(1);
    final type = useState('all');
    final requestId = useRef(0);
    final timer = useRef<Timer?>(null);
    final theme = Theme.of(context);

    useEffect(() {
      return () => timer.value?.cancel();
    }, const []);

    Future<void> run(String raw, {int toPage = 1}) async {
      final query = raw.trim();
      final id = ++requestId.value;
      if (query.isEmpty) {
        results.value = const [];
        page.value = 1;
        pages.value = 1;
        error.value = null;
        return;
      }
      if (toPage == 1) {
        loading.value = true;
      } else {
        loadingMore.value = true;
      }
      error.value = null;
      try {
        final result = await session.run(
          () => ref.read(searchApiProvider).search(
            query,
            contentType: _contentTypeFor[type.value],
            page: toPage,
          ),
        );
        if (!context.mounted || id != requestId.value) return;
        results.value = toPage == 1
            ? result.items
            : [...results.value, ...result.items];
        page.value = result.page;
        pages.value = result.pages;
      } catch (failure) {
        if (!context.mounted || id != requestId.value) return;
        error.value = '$failure';
      } finally {
        if (id == requestId.value && context.mounted) {
          loading.value = false;
          loadingMore.value = false;
        }
      }
    }

    void onChanged(String value) {
      timer.value?.cancel();
      timer.value = Timer(_debounce, () => run(value));
    }

    void openHit(SearchHit hit) {
      final router = context.router;
      if (hit.contentType == 'library_file') {
        Navigator.of(context).pop();
        router.push(LibraryFileRoute(id: hit.id));
        return;
      }
      if (_detailTypes.contains(hit.contentType)) {
        Navigator.of(context).pop();
        router.push(ContentDetailRoute(id: hit.id));
        return;
      }
      final path = '/forum/post/${hit.id}';
      final target = resolveFeedUrl(path, serverHost);
      if (target != null) {
        launchUrlString(target, mode: LaunchMode.externalApplication);
      }
    }

    final items = results.value;
    final hasMore = page.value < pages.value;

    return SheetScaffold(
      titleText: 'search'.tr(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: onChanged,
              onSubmitted: (value) {
                timer.value?.cancel();
                run(value);
              },
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'feedSearchHint'.tr(),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Wrap(
                spacing: 8,
                children: [
                  for (final value in _searchTypes)
                    ChoiceChip(
                      label: Text(_typeLabel(value)),
                      selected: type.value == value,
                      onSelected: (_) {
                        if (type.value == value) return;
                        type.value = value;
                        timer.value?.cancel();
                        run(controller.text);
                      },
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: loading.value
                ? const Center(child: CircularProgressIndicator())
                : error.value != null && items.isEmpty
                ? Center(
                    child: Text(
                      error.value!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  )
                : items.isEmpty
                ? Center(
                    child: Text(
                      'feedSearchEmpty'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: items.length + (hasMore ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      if (index == items.length) {
                        return Center(
                          child: TextButton(
                            onPressed: loadingMore.value
                                ? null
                                : () => run(
                                    controller.text,
                                    toPage: page.value + 1,
                                  ),
                            child: Text('feedLoadMore'.tr()),
                          ),
                        );
                      }
                      final hit = items[index];
                      return ListTile(
                        onTap: () => openHit(hit),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        tileColor: theme.colorScheme.surfaceContainerLow,
                        title: Text(
                          hit.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          [
                            _hitLabel(hit.contentType),
                            if (hit.authorName.isNotEmpty) hit.authorName,
                            if (hit.excerpt.isNotEmpty) hit.excerpt,
                          ].join(' · '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
