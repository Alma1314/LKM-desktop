import 'dart:async';

import 'package:riverpod/riverpod.dart';
import 'package:solar_network_sdk/solar_network_sdk.dart';
import 'package:test/test.dart';

/// Serves a fixed in-memory list, so tests can change the "server" content
/// between rebuilds (for example when a logout removes entries).
class _ListNotifier extends AsyncNotifier<PaginationState<int>>
    with AsyncPaginationController<int> {
  static const int pageSize = 2;

  static List<int> server = const [];
  static final List<int> requestedOffsets = [];

  @override
  FutureOr<PaginationState<int>> build() async {
    final items = await fetch();
    final total = totalCount;
    return PaginationState(
      items: items,
      isLoading: false,
      isReloading: false,
      totalCount: total,
      hasMore: total == null ? items.isNotEmpty : items.length < total,
      cursor: null,
    );
  }

  @override
  Future<List<int>> fetch() async {
    final offset = fetchedCount;
    requestedOffsets.add(offset);
    totalCount = server.length;
    final start = offset.clamp(0, server.length);
    final end = (offset + pageSize).clamp(0, server.length);
    return server.sublist(start, end);
  }
}

final _listProvider = AsyncNotifierProvider<_ListNotifier, PaginationState<int>>(
  _ListNotifier.new,
);


class _Token extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final _tokenProvider = NotifierProvider<_Token, int>(_Token.new);

/// Rebuilds whenever [_tokenProvider] changes, which makes Riverpod reload the
/// notifier while keeping the previous page as a stale value.
class _ReloadingNotifier extends _ListNotifier {
  @override
  FutureOr<PaginationState<int>> build() async {
    ref.watch(_tokenProvider);
    return super.build();
  }
}

final _reloadingProvider =
    AsyncNotifierProvider<_ReloadingNotifier, PaginationState<int>>(
      _ReloadingNotifier.new,
    );

void main() {
  late ProviderContainer container;

  setUp(() {
    _ListNotifier.server = const [0, 1, 2, 3, 4];
    _ListNotifier.requestedOffsets.clear();
  });

  tearDown(() => container.dispose());

  test('invalidate refetches from the first page after the list shrank',
      () async {
    container = ProviderContainer();
    await container.read(_listProvider.future);
    expect(_ListNotifier.requestedOffsets, [0]);

    // A device/session was revoked elsewhere: the server list got shorter.
    _ListNotifier.server = const [0, 1, 2];
    _ListNotifier.requestedOffsets.clear();

    container.invalidate(_listProvider);
    await container.read(_listProvider.future);

    expect(_ListNotifier.requestedOffsets, [0]);
    final state = container.read(_listProvider).value!;
    expect(state.items, [0, 1]);
    expect(state.totalCount, 3);
    expect(state.hasMore, isTrue);
  });

  test('fetchFurther after invalidate continues from the new first page',
      () async {
    container = ProviderContainer();
    await container.read(_listProvider.future);

    _ListNotifier.server = const [0, 1, 2];
    _ListNotifier.requestedOffsets.clear();

    container.invalidate(_listProvider);
    await container.read(_listProvider.future);
    await container.read(_listProvider.notifier).fetchFurther();

    expect(_ListNotifier.requestedOffsets, [0, 2]);
    final state = container.read(_listProvider).value!;
    expect(state.items, [0, 1, 2]);
    expect(state.hasMore, isFalse);
  });

  test('previously loaded pages do not end pagination after invalidate',
      () async {
    container = ProviderContainer();
    await container.read(_listProvider.future);
    await container.read(_listProvider.notifier).fetchFurther();
    expect(_ListNotifier.requestedOffsets, [0, 2]);

    // Everything was loaded (4 of 5), so without the fix the stale
    // hasMore=false would have been reused by the rebuild.
    _ListNotifier.requestedOffsets.clear();
    container.invalidate(_listProvider);
    await container.read(_listProvider.future);

    expect(_ListNotifier.requestedOffsets, [0]);
    expect(container.read(_listProvider).value!.hasMore, isTrue);
    await container.read(_listProvider.notifier).fetchFurther();
    expect(_ListNotifier.requestedOffsets, [0, 2]);
    expect(container.read(_listProvider).value!.items, [0, 1, 2, 3]);
  });

  test('a watched dependency change refetches from the first page', () async {
    container = ProviderContainer();
    await container.read(_reloadingProvider.future);
    expect(_ListNotifier.requestedOffsets, [0]);

    _ListNotifier.server = const [0, 1, 2];
    _ListNotifier.requestedOffsets.clear();

    container.read(_tokenProvider.notifier).bump();
    await container.read(_reloadingProvider.future);

    expect(_ListNotifier.requestedOffsets, [0]);
    final state = container.read(_reloadingProvider).value!;
    expect(state.items, [0, 1]);
    expect(state.hasMore, isTrue);
  });
}
