import 'dart:io';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/history/cursor.dart';
import 'package:PiliPlus/models_new/history/data.dart';
import 'package:PiliPlus/models_new/history/history.dart';
import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/models_new/local_history/local_history_item.dart';
import 'package:PiliPlus/models_new/local_history/local_history_item_adapter.dart';
import 'package:PiliPlus/services/local_history/local_history_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

const _mid = 1;

HistoryItemModel _cloud(
  String business,
  int kid,
  int viewAt, {
  String? title,
}) => HistoryItemModel(
  title: title ?? '$business$kid',
  history: History(business: business, oid: kid),
  kid: kid,
  viewAt: viewAt,
);

LocalHistoryItem _row(
  String business,
  int kid,
  int viewAt, {
  int mid = _mid,
  int syncedAt = 0,
}) => LocalHistoryItem.fromModel(
  accountMid: mid,
  item: _cloud(business, kid, viewAt),
  syncedAt: syncedAt,
)!;

/// Serves [items] (newest first) in pages; the cursor's `max` is the index of
/// the next page, and 0 marks the end like the real API does.
class _FakeCloud {
  _FakeCloud(this.items);

  List<HistoryItemModel> items;
  final int pageSize = 2;
  final List<HistoryCursor?> requests = [];
  bool failing = false;

  Future<LoadingState<HistoryData>> fetch(HistoryCursor? cursor) async {
    requests.add(cursor);
    if (failing) return const Error('boom');
    final start = cursor?.max ?? 0;
    final end = start + pageSize;
    final page = items.skip(start).take(pageSize).toList();
    return Success(
      HistoryData(
        list: page,
        cursor: HistoryCursor(max: end >= items.length ? 0 : end),
      ),
    );
  }
}

void main() {
  late Directory dir;
  late Box<LocalHistoryItem> box;
  late Box<dynamic> cache;
  late _FakeCloud cloud;
  late List<String> deleted;
  late LoadingState<void> deleteResult;
  late LoadingState<void> clearResult;
  late LocalHistoryRepository repo;

  setUpAll(() {
    dir = Directory.systemTemp.createTempSync('local_history_test');
    Hive
      ..init(dir.path)
      ..registerAdapter(LocalHistoryItemAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  setUp(() async {
    box = await Hive.openBox<LocalHistoryItem>('rows');
    cache = await Hive.openBox('cache');
    await box.clear();
    await cache.clear();
    cloud = _FakeCloud([]);
    deleted = [];
    deleteResult = const Success(null);
    clearResult = const Success(null);
    repo = LocalHistoryRepository(
      box: box,
      cache: cache,
      fetchPage: (c) => cloud.fetch(c),
      deleteKids: (kids) async {
        deleted.add(kids);
        return deleteResult;
      },
      clearCloud: () async => clearResult,
      fastDelay: Duration.zero,
      slowDelay: Duration.zero,
    );
  });

  List<String> titles(List<HistoryItemModel> l) =>
      l.map((e) => e.title!).toList();

  group('loadPage', () {
    setUp(() async {
      await box.putAll({
        for (final r in [
          _row('archive', 1, 100),
          _row('live', 2, 300),
          _row('article', 3, 200),
          _row('pgc', 4, 50),
          _row('archive', 5, 999, mid: 2),
        ])
          r.rowKey: r,
      });
    });

    test('sorts newest first and keeps accounts apart', () {
      final page = repo.loadPage(accountMid: _mid, offset: 0, limit: 10);
      expect(titles(page), ['live2', 'article3', 'archive1', 'pgc4']);
    });

    test('ascending order reverses the same set', () {
      final page = repo.loadPage(
        accountMid: _mid,
        offset: 0,
        limit: 10,
        sortOrder: HistorySortOrder.viewAtAsc,
      );
      expect(titles(page), ['pgc4', 'archive1', 'article3', 'live2']);
    });

    test('equal viewAt falls back to newer syncedAt', () async {
      final a = _row('archive', 10, 500, syncedAt: 1);
      final b = _row('archive', 11, 500, syncedAt: 2);
      await box.putAll({a.rowKey: a, b.rowKey: b});
      repo.resetRuntimeState();
      final page = repo.loadPage(accountMid: _mid, offset: 0, limit: 2);
      expect(titles(page), ['archive11', 'archive10']);
    });

    test('date range is inclusive on both ends', () {
      final page = repo.loadPage(
        accountMid: _mid,
        offset: 0,
        limit: 10,
        filterFrom: 100,
        filterTo: 200,
      );
      expect(titles(page), ['article3', 'archive1']);
    });

    test('tabs filter on business', () {
      List<String> of(String type) => titles(
        repo.loadPage(accountMid: _mid, offset: 0, limit: 10, type: type),
      );
      expect(of('archive'), ['archive1', 'pgc4']);
      expect(of('live'), ['live2']);
      expect(of('article'), ['article3']);
    });

    test('pages after filtering', () {
      final first = repo.loadPage(
        accountMid: _mid,
        offset: 0,
        limit: 1,
        type: 'archive',
      );
      final second = repo.loadPage(
        accountMid: _mid,
        offset: 1,
        limit: 1,
        type: 'archive',
      );
      final third = repo.loadPage(
        accountMid: _mid,
        offset: 2,
        limit: 1,
        type: 'archive',
      );
      expect([...titles(first), ...titles(second)], ['archive1', 'pgc4']);
      expect(third, isEmpty);
    });

    test(
      'rows survive a box reopen and convert back to the page model',
      () async {
        await box.close();
        box = await Hive.openBox<LocalHistoryItem>('rows');
        final item = box.get('1:archive:1')!.toModel();
        expect(item.kid, 1);
        expect(item.history.business, 'archive');
        expect(item.history.oid, 1);
        expect(item.viewAt, 100);
      },
    );
  });

  group('sync', () {
    List<HistoryItemModel> cloudItems() => [
      _cloud('archive', 6, 600),
      _cloud('archive', 5, 500),
      _cloud('archive', 4, 400),
      _cloud('archive', 3, 300),
      _cloud('archive', 2, 200),
    ];

    test(
      'first sync walks the whole cloud and marks it fully synced',
      () async {
        cloud.items = cloudItems();
        await repo.startSync(accountMid: _mid);

        expect(cloud.requests.length, 3);
        expect(box.length, 5);
        expect(cache.get(LocalHistoryRepository.fullySyncedKey(_mid)), true);
        expect(repo.sessionState.fetchedCloudKeys.length, 5);
        expect(repo.sessionState.hasFirstPage.value, true);
        expect(repo.sessionState.syncFailed.value, false);
      },
    );

    test('a failing fetch leaves the flag unset and reports failure', () async {
      cloud
        ..items = cloudItems()
        ..failing = true;
      await repo.startSync(accountMid: _mid);

      expect(cache.get(LocalHistoryRepository.fullySyncedKey(_mid)), isNull);
      expect(repo.sessionState.syncFailed.value, true);
    });

    test(
      'stops at the unchanged frontier and leaves a cursor to confirm',
      () async {
        cloud.items = cloudItems();
        await repo.startSync(accountMid: _mid);
        cloud.requests.clear();

        cloud.items = [_cloud('archive', 7, 700), ...cloudItems()];
        await repo.startSync(accountMid: _mid);

        // Page 1 holds the new record, page 2 matches local rows exactly.
        expect(cloud.requests.length, 2);
        expect(box.containsKey('1:archive:7'), true);
        expect(repo.sessionState.cursor, isNotNull);
        expect(cache.get(LocalHistoryRepository.fullySyncedKey(_mid)), true);
      },
    );

    test('a re-watched record is not mistaken for the frontier', () async {
      cloud.items = cloudItems();
      await repo.startSync(accountMid: _mid);
      cloud.requests.clear();

      // archive3 moved to the top: page 2 now differs from local viewAt.
      cloud.items = [
        _cloud('archive', 3, 900),
        _cloud('archive', 6, 600),
        _cloud('archive', 5, 500),
        _cloud('archive', 4, 400),
        _cloud('archive', 2, 200),
      ];
      await repo.startSync(accountMid: _mid);

      expect(box.get('1:archive:3')!.viewAt, 900);
      expect(cloud.requests.length, greaterThan(1));
    });

    test('cancelling forces a full rescan next time', () async {
      cloud.items = cloudItems();
      await repo.startSync(accountMid: _mid);
      cloud.requests.clear();

      final running = repo.startSync(accountMid: _mid);
      repo.cancelActiveSync();
      await running;
      expect(cache.get(LocalHistoryRepository.fullySyncedKey(_mid)), isNull);
      expect(repo.sessionState.syncFailed.value, false);

      cloud.requests.clear();
      await repo.startSync(accountMid: _mid);
      expect(cloud.requests.length, 3);
    });

    test('source is unknown until the scan is done, then local', () async {
      cloud.items = cloudItems();
      await repo.startSync(accountMid: _mid);
      await box.put('1:archive:99', _row('archive', 99, 1));

      expect(
        repo.resolveSource(_cloud('archive', 6, 600)),
        LocalHistorySource.cloud,
      );
      expect(
        repo.resolveSource(_cloud('archive', 99, 1)),
        LocalHistorySource.local,
      );
    });

    test(
      'confirmNextPage extends cloud keys until the visible range is covered',
      () async {
        cloud.items = cloudItems();
        await repo.startSync(accountMid: _mid);
        cloud.requests.clear();
        cloud.items = [_cloud('archive', 7, 700), ...cloudItems()];
        await repo.startSync(accountMid: _mid);

        // Frontier page covers 600/500; the unconfirmed rest is below.
        expect(
          repo.resolveSource(_cloud('archive', 2, 200)),
          LocalHistorySource.unknown,
        );
        var more = true;
        while (more) {
          more = await repo.confirmNextPage(until: 0);
        }
        expect(repo.sessionState.cursor, isNull);
        expect(
          repo.resolveSource(_cloud('archive', 2, 200)),
          LocalHistorySource.cloud,
        );
      },
    );
  });

  group('delete and clear', () {
    setUp(() async {
      await box.putAll({
        for (final r in [
          _row('archive', 1, 100),
          _row('live', 2, 200),
          _row('archive', 1, 100, mid: 2),
        ])
          r.rowKey: r,
      });
    });

    test('removes local rows only after the cloud delete succeeds', () async {
      deleteResult = const Error('no');
      await repo.deleteItems(
        accountMid: _mid,
        items: [_cloud('archive', 1, 100)],
      );
      expect(box.containsKey('1:archive:1'), true);

      deleteResult = const Success(null);
      await repo.deleteItems(
        accountMid: _mid,
        items: [_cloud('archive', 1, 100), _cloud('live', 2, 200)],
      );
      expect(deleted.last, 'archive_1,live_2');
      expect(box.keys, ['2:archive:1']);
    });

    test('clearing both wipes only this account and resets the flag', () async {
      await cache.put(LocalHistoryRepository.fullySyncedKey(_mid), true);
      await repo.clearHistory(accountMid: _mid, mode: HistoryClearMode.both);

      expect(box.keys, ['2:archive:1']);
      expect(cache.get(LocalHistoryRepository.fullySyncedKey(_mid)), isNull);
    });

    test('cloud-only clear keeps local rows and the flag', () async {
      await cache.put(LocalHistoryRepository.fullySyncedKey(_mid), true);
      await repo.clearHistory(
        accountMid: _mid,
        mode: HistoryClearMode.cloudOnly,
      );

      expect(box.length, 3);
      expect(cache.get(LocalHistoryRepository.fullySyncedKey(_mid)), true);
    });

    test('a failed cloud clear changes nothing', () async {
      clearResult = const Error('no');
      await repo.clearHistory(accountMid: _mid, mode: HistoryClearMode.both);
      expect(box.length, 3);
    });
  });
}
