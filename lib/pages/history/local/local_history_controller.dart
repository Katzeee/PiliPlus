import 'dart:async';

import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models_new/history/data.dart';
import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/models_new/history/tab.dart';
import 'package:PiliPlus/pages/history/controller.dart';
import 'package:PiliPlus/pages/history/local/local_history_state.dart';
import 'package:PiliPlus/services/local_history/local_history.dart';
import 'package:PiliPlus/services/local_history/local_history_repository.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// History page backed by the local rows; the cloud is mirrored into them by
/// [localHistory] and deletes still go to the cloud first.
class LocalHistoryController extends HistoryController {
  LocalHistoryController(super.type);

  static const _pageSize = 20;
  static final _tabs = [
    HistoryTab(type: 'archive', name: '视频'),
    HistoryTab(type: 'live', name: '直播'),
    HistoryTab(type: 'article', name: '专栏'),
  ];

  late final viewState = Get.put(LocalHistoryState());

  final _workers = <Worker>[];
  bool _syncOnRefresh = true;

  int get _mid => Accounts.history.mid;

  @override
  void onInit() {
    _workers.add(
      ever(viewState.listRevision, (_) {
        if (enableMultiSelect.value) handleSelect();
        onReload();
      }),
    );
    super.onInit();
  }

  @override
  void onClose() {
    for (final worker in _workers) {
      worker.dispose();
    }
    if (type == null) {
      Get.delete<LocalHistoryState>();
    }
    super.onClose();
  }

  /// Pull-to-refresh asks the cloud again; reloads only re-read local rows.
  @override
  Future<void> onRefresh() {
    if (_syncOnRefresh) {
      if (!viewState.isDefaultQuery) {
        // Filters hide what the sync writes newest-first.
        viewState.resetQuery();
      }
      unawaited(localHistory.startSync(accountMid: _mid));
    }
    _syncOnRefresh = true;
    return super.onRefresh();
  }

  @override
  Future<void> onReload() {
    _syncOnRefresh = false;
    return super.onReload();
  }

  @override
  Future<LoadingState<HistoryData>> customGetData() async {
    final mid = _mid;
    if (mid == 0) return const Error('请先登录');

    final isRefresh = page == 1;
    if (isRefresh) await _awaitFirstPage(mid);

    final items = localHistory.loadPage(
      accountMid: mid,
      offset: isRefresh ? 0 : (loadingState.value.dataOrNull?.length ?? 0),
      limit: _pageSize,
      type: type,
      sortOrder: viewState.sortOrder.value,
      filterFrom: viewState.filterFrom,
      filterTo: viewState.filterTo,
    );
    if (isRefresh &&
        items.isEmpty &&
        localHistory.sessionState.syncFailed.value) {
      return const Error('同步失败，请重试');
    }
    if (viewState.isDefaultQuery) _confirmSources(items);
    return Success(
      HistoryData(tab: type == null ? _tabs : null, list: items),
    );
  }

  @override
  bool customHandleResponse(bool isRefresh, Success<HistoryData> response) {
    final handled = super.customHandleResponse(isRefresh, response);
    if ((response.response.list?.length ?? 0) < _pageSize) {
      isEnd = true;
    }
    return handled;
  }

  /// Waits until a sync has written its first page, starting one if none ran
  /// in this session. Failed or cancelled syncs release the wait too.
  Future<void> _awaitFirstPage(int mid) async {
    final state = localHistory.sessionState;
    if (state.hasFirstPage.value) return;

    final done = Completer<void>();
    void release() {
      if (!done.isCompleted) done.complete();
    }

    final workers = [
      ever(state.hasFirstPage, (ready) => ready ? release() : null),
      ever(state.isSyncing, (syncing) => syncing ? null : release()),
    ];
    if (!state.isSyncing.value) {
      unawaited(localHistory.startSync(accountMid: mid));
    }
    try {
      await done.future;
    } finally {
      for (final worker in workers) {
        worker.dispose();
      }
    }
  }

  /// Walks cloud pages until the visible range is covered, then refreshes the
  /// badges. Only meaningful for the default newest-first query.
  void _confirmSources(List<HistoryItemModel> items) {
    final until = items.lastOrNull?.viewAt;
    if (until == null ||
        localHistory.sessionState.cursor == null ||
        viewState.confirming) {
      return;
    }
    viewState.confirming = true;
    unawaited(() async {
      try {
        while (await localHistory.confirmNextPage(until: until)) {}
      } finally {
        viewState.confirming = false;
        viewState.badgeRevision.value++;
      }
    }());
  }

  Future<void> _deleteLocal(Set<HistoryItemModel> removeList) async {
    SmartDialog.showLoading(msg: '请求中');
    final res = await localHistory.deleteItems(
      accountMid: _mid,
      items: removeList,
    );
    SmartDialog.dismiss();
    if (res.isSuccess) {
      afterDelete(removeList);
      SmartDialog.showToast('已删除');
    } else {
      res.toast();
    }
  }

  @override
  void delHistory(HistoryItemModel item) => _deleteLocal({item});

  @override
  void onDelViewedHistory() {
    final viewedList = loadingState.value.dataOrNull
        ?.where((e) => e.progress == -1)
        .toSet();
    if (viewedList != null && viewedList.isNotEmpty) {
      _deleteLocal(viewedList);
    } else {
      SmartDialog.showToast('无已看记录');
    }
  }

  @override
  void onRemove() {
    showDialog(
      context: Get.context!,
      builder: (context) => AlertDialog(
        title: const Text('提示'),
        content: const Text('确认删除所选历史记录吗？'),
        actions: [
          TextButton(
            onPressed: Get.back,
            child: Text(
              '取消',
              style: TextStyle(color: ColorScheme.of(context).outline),
            ),
          ),
          TextButton(
            onPressed: () {
              Get.back();
              _deleteLocal(allChecked.toSet());
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  void onClearHistory(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空观看历史'),
        content: const Text('选择清空范围'),
        actions: [
          TextButton(
            onPressed: Get.back,
            child: Text(
              '取消',
              style: TextStyle(color: ColorScheme.of(context).outline),
            ),
          ),
          TextButton(
            onPressed: () => _clear(HistoryClearMode.cloudOnly),
            child: const Text('仅云端'),
          ),
          TextButton(
            onPressed: () => _clear(HistoryClearMode.both),
            child: Text(
              '云端和本地',
              style: TextStyle(color: ColorScheme.of(context).error),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clear(HistoryClearMode mode) async {
    Get.back();
    SmartDialog.showLoading(msg: '请求中');
    final res = await localHistory.clearHistory(accountMid: _mid, mode: mode);
    SmartDialog.dismiss();
    if (res.isSuccess) {
      if (mode == HistoryClearMode.both) {
        SmartDialog.showToast('已清空全部记录');
        viewState.listRevision.value++;
      } else {
        SmartDialog.showToast('已清空云端记录');
        viewState.badgeRevision.value++;
      }
    } else {
      res.toast();
    }
  }
}
