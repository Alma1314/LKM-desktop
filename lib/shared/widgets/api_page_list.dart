import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:island/core/api/api_client.dart';
import 'package:island/core/api/api_providers.dart';

/// Page-number APIs share one native list, retry and page controls.
class ApiPageList<T> extends HookConsumerWidget {
  const ApiPageList({
    super.key,
    required this.provider,
    required this.itemBuilder,
  });
  final FutureProvider<ApiPage<T>> Function(int page) provider;
  final Widget Function(BuildContext, T) itemBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = useState(1);
    final session = ref.watch(lkmApiSessionProvider);
    useEffect(() {
      page.value = 1;
      return null;
    }, [session.serverUrl, session.identityRevision]);
    final source = provider(page.value);
    final value = ref.watch(source);
    final pages = value.value?.pages ?? page.value;
    return Column(
      children: [
        Expanded(
          child: value.when(
            skipLoadingOnRefresh: false,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$error'),
                  TextButton(
                    onPressed: () => ref.invalidate(source),
                    child: Text('retry'.tr()),
                  ),
                ],
              ),
            ),
            data: (data) => RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(source);
                await ref.read(source.future);
              },
              child: ListView.separated(
                key: ValueKey(page.value),
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                itemCount: data.items.isEmpty ? 1 : data.items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) => data.items.isEmpty
                    ? Center(child: Text('authFlow.empty'.tr()))
                    : itemBuilder(context, data.items[index]),
              ),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'adminPanel.previous'.tr(),
              onPressed: page.value > 1 && !value.isLoading
                  ? () => page.value--
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            Text('${page.value} / ${pages < 1 ? 1 : pages}'),
            IconButton(
              tooltip: 'adminPanel.next'.tr(),
              onPressed: page.value < pages && !value.isLoading
                  ? () => page.value++
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}
