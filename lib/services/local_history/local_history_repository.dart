import 'dart:math';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/history/cursor.dart';
import 'package:PiliPlus/models_new/history/data.dart';
import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/models_new/local_history/local_history_item.dart';
import 'package:get/get.dart';
import 'package:hive_ce/hive.dart';

enum LocalHistorySource { cloud, local, unknown }

enum HistorySortOrder { viewAtDesc, viewAtAsc }

enum HistoryClearMode { cloudOnly, both }

typedef HistoryPageFetcher = Future<LoadingState<HistoryData>> Function(
  HistoryCursor? cursor,
);

class HistorySessionState {
  /// `business:kid` of every record seen on the cloud in this session.
  final Set<String> fetchedCloudKeys = <String>{};
  final RxBool isSyncing = false.obs;

  /// Flips to true once the first cloud page is processed; reset per sync.
  final RxBool hasFirstPage = false.obs;

  /// Flips to true when a sync fails (not when it is cancelled); reset per sync.
  final RxBool syncFailed = false.obs;

  /// Set when the sync stopped at an unchanged frontier page: the cursor of the
  /// next unconfirmed cloud page, consumed by [LocalHistoryRepository.confirmNextPage].
  HistoryCursor? cursor;

  final RxInt syncedPages = 0.obs;
}

class LocalHistoryRepository {
  LocalHistoryRepository({
    required this.box,
    required this.cache,
    required this.fetchPage,
    required this.deleteKids,
    required this.clearCloud,
    this.fastDelay = const Duration(milliseconds: 200),
    this.slowDelay = const Duration(milliseconds: 800),
  });

  static const int _fastPages = 3;

  final Box<LocalHistoryItem> box;
  final Box<dynamic> cache;
  final HistoryPageFetcher fetchPage;
  final Future<LoadingState<void>> Function(String kids) deleteKids;
  final Future<LoadingState<void>> Function() clearCloud;
  final Duration fastDelay;
  final Duration slowDelay;

  final HistorySessionState sessionState = HistorySessionState();

  /// Bumped to invalidate the task holding an older value.
  int _generation = 0;

  List<String>? _sortedKeys;
  int? _sortedKeysMid;

  static String fullySyncedKey(int accountMid) =>
      'fork_historyFullySynced:$accountMid';

  static String _uniqueKeyOf(HistoryItemModel item) =>
      '${item.history.business}:${item.kid}';

  /// Business values shown under each cloud tab; null means all.
  static Set<String>? businessesOfType(String? type) => switch (type) {
    'archive' => const {'archive', 'pgc'},
    'live' => const {'live'},
    'article' => const {'article', 'article-list'},
    _ => null,
  };

  void _cancel() {
    _generation++;
    sessionState.isSyncing.value = false;
  }

  bool _isActive(int generation) => generation == _generation;

  /// Cancels a running sync. Rows already written stay; `fullySynced` was
  /// cleared when the sync started, so the next sync rescans everything.
  void cancelActiveSync() => _cancel();

  void resetRuntimeState() {
    _cancel();
    sessionState
      ..fetchedCloudKeys.clear()
      ..hasFirstPage.value = false
      ..syncFailed.value = false
      ..cursor = null
      ..syncedPages.value = 0;
    _sortedKeys = null;
    _sortedKeysMid = null;
  }

  LocalHistorySource resolveSource(HistoryItemModel item) {
    if (sessionState.fetchedCloudKeys.contains(_uniqueKeyOf(item))) {
      return LocalHistorySource.cloud;
    }
    if (sessionState.isSyncing.value || sessionState.cursor != null) {
      return LocalHistorySource.unknown;
    }
    return LocalHistorySource.local;
  }

  List<HistoryItemModel> loadPage({
    required int accountMid,
    required int offset,
    required int limit,
    String? type,
    HistorySortOrder sortOrder = HistorySortOrder.viewAtDesc,
    int? filterFrom,
    int? filterTo,
  }) {
    if (limit <= 0) return const [];
    final businesses = businessesOfType(type);
    final items = <LocalHistoryItem>[];
    for (final key in _sortedKeysFor(accountMid)) {
      final item = box.get(key);
      if (item == null) continue;
      if (businesses != null && !businesses.contains(item.business)) continue;
      final view = item.viewAt ?? 0;
      if (filterFrom != null && view < filterFrom) continue;
      if (filterTo != null && view > filterTo) continue;
      items.add(item);
    }
    if (sortOrder == HistorySortOrder.viewAtAsc) {
      items.sort((a, b) => _compare(b, a));
    }
    if (offset >= items.length) return const [];
    return items
        .sublist(max(0, offset), min(items.length, max(0, offset) + limit))
        .map((e) => e.toModel())
        .toList();
  }

  /// viewAt descending; ties by newer sync, then by key for a stable order.
  static int _compare(LocalHistoryItem a, LocalHistoryItem b) {
    final byView = (b.viewAt ?? 0).compareTo(a.viewAt ?? 0);
    if (byView != 0) return byView;
    final bySynced = b.syncedAt.compareTo(a.syncedAt);
    if (bySynced != 0) return bySynced;
    return a.uniqueKey.compareTo(b.uniqueKey);
  }

  List<String> _sortedKeysFor(int accountMid) {
    if (_sortedKeys case final keys? when _sortedKeysMid == accountMid) {
      return keys;
    }
    final items = box.values.where((e) => e.accountMid == accountMid).toList()
      ..sort(_compare);
    _sortedKeysMid = accountMid;
    return _sortedKeys = items.map((e) => e.rowKey).toList(growable: false);
  }

  /// Walks the cloud history newest-first and mirrors it into the box.
  ///
  /// Without a previous complete sync (`fullySynced` unset) it runs until the
  /// cloud is exhausted. Otherwise it stops at the first page whose records all
  /// exist locally with the same `viewAt`: new records always appear on top, so
  /// nothing below that page can be new. The flag is cleared up front, so any
  /// interruption forces a full rescan next time.
  Future<void> startSync({required int accountMid}) async {
    _cancel();
    final generation = ++_generation;
    final state = sessionState
      ..isSyncing.value = true
      ..fetchedCloudKeys.clear()
      ..hasFirstPage.value = false
      ..syncFailed.value = false
      ..cursor = null
      ..syncedPages.value = 0;
    try {
      await _sync(accountMid, state, generation);
    } finally {
      if (_isActive(generation)) {
        state.isSyncing.value = false;
      }
    }
  }

  Future<void> _sync(
    int accountMid,
    HistorySessionState state,
    int generation,
  ) async {
    final flagKey = fullySyncedKey(accountMid);
    final fullySynced = cache.get(flagKey) as bool? ?? false;
    if (fullySynced) await cache.delete(flagKey);

    HistoryCursor? nextCursor;
    var pageIndex = 0;
    var complete = false;

    while (_isActive(generation)) {
      final LoadingState<HistoryData> res;
      try {
        res = await fetchPage(nextCursor);
      } catch (_) {
        break;
      }
      if (!_isActive(generation) || res is! Success<HistoryData>) break;

      final data = res.response;
      final list = data.list ?? const <HistoryItemModel>[];
      final cursor = data.cursor;
      final isLastPage = list.isEmpty || cursor == null || cursor.max == 0;
      state.syncedPages.value++;

      if (fullySynced && !isLastPage && _isUnchanged(accountMid, list)) {
        state.fetchedCloudKeys.addAll(list.map(_uniqueKeyOf));
        state.hasFirstPage.value = true;
        state.cursor = cursor;
        complete = true;
        break;
      }

      final syncedAt = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final rows = <LocalHistoryItem>[
        for (final item in list)
          ?LocalHistoryItem.fromModel(
            accountMid: accountMid,
            item: item,
            syncedAt: syncedAt,
          ),
      ];
      if (rows.isNotEmpty) {
        await box.putAll({for (final row in rows) row.rowKey: row});
        if (!_isActive(generation)) break;
        _sortedKeys = null;
        state.fetchedCloudKeys.addAll(rows.map((e) => e.uniqueKey));
        state.hasFirstPage.value = true;
      }

      nextCursor = cursor;
      if (isLastPage) {
        complete = true;
        break;
      }
      await Future<void>.delayed(
        pageIndex < _fastPages ? fastDelay : slowDelay,
      );
      pageIndex++;
    }

    // A clean sync that wrote nothing still lets the page render from the box.
    if (complete) {
      state.hasFirstPage.value = true;
      await cache.put(flagKey, true);
    } else if (_isActive(generation)) {
      state.syncFailed.value = true;
    }
  }

  /// A viewAt mismatch means the record was watched again and moved up.
  bool _isUnchanged(int accountMid, List<HistoryItemModel> list) {
    for (final item in list) {
      final local = box.get('$accountMid:${_uniqueKeyOf(item)}');
      if (local == null || local.viewAt != item.viewAt) return false;
    }
    return true;
  }

  /// Adds cloud keys page by page from the frontier cursor, so records below
  /// the unchanged page also get a cloud source. Stops once the scan reaches
  /// [until] (`viewAt` of the last visible record). Returns true while more
  /// pages are needed to cover [until].
  Future<bool> confirmNextPage({required int? until}) async {
    final state = sessionState;
    final cursor = state.cursor;
    if (cursor == null || state.isSyncing.value) return false;

    final generation = _generation;
    try {
      final res = await fetchPage(cursor);
      if (!_isActive(generation) || res is! Success<HistoryData>) return false;

      final data = res.response;
      final list = data.list ?? const <HistoryItemModel>[];
      final next = data.cursor;
      state.fetchedCloudKeys.addAll(list.map(_uniqueKeyOf));

      if (list.isEmpty || next == null || next.max == 0) {
        state.cursor = null;
        return false;
      }
      state.cursor = next;

      final oldest = list
          .map((e) => e.viewAt)
          .nonNulls
          .fold<int?>(null, (a, b) => a == null ? b : min(a, b));
      return !(until != null && oldest != null && oldest <= until);
    } catch (_) {
      return false;
    }
  }

  /// Deletes on the cloud first; local rows go only when that succeeds.
  Future<LoadingState<void>> deleteItems({
    required int accountMid,
    required Iterable<HistoryItemModel> items,
  }) async {
    if (items.isEmpty) return const Success(null);
    _cancel();
    final res = await deleteKids(
      items.map((e) => '${e.history.business}_${e.kid}').join(','),
    );
    if (res is Success) {
      await box.deleteAll(items.map((e) => '$accountMid:${_uniqueKeyOf(e)}'));
      _sortedKeys = null;
      sessionState.fetchedCloudKeys.removeAll(items.map(_uniqueKeyOf));
    }
    return res;
  }

  Future<LoadingState<void>> clearHistory({
    required int accountMid,
    required HistoryClearMode mode,
  }) async {
    _cancel();
    final res = await clearCloud();
    if (res is! Success) return res;
    sessionState
      ..fetchedCloudKeys.clear()
      ..cursor = null;
    if (mode == HistoryClearMode.both) {
      await box.deleteAll(_sortedKeysFor(accountMid).toList());
      _sortedKeys = null;
      // The next sync must download everything again.
      await cache.delete(fullySyncedKey(accountMid));
    }
    return res;
  }
}
