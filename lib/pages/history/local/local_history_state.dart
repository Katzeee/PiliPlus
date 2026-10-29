import 'package:PiliPlus/common/widgets/dialog/dialog.dart';
import 'package:PiliPlus/services/local_history/local_history.dart';
import 'package:PiliPlus/services/local_history/local_history_repository.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// Query state shared by the history tabs: sort, date range and the signals
/// that make every tab reload or re-derive its source badges.
class LocalHistoryState extends GetxController {
  final sortOrder = HistorySortOrder.viewAtDesc.obs;
  final dateFilter = Rx<DateTimeRange?>(null);

  /// Bumped when every tab has to reload from the local rows.
  final listRevision = 0.obs;

  /// Bumped when cloud/local source badges may have changed.
  final badgeRevision = 0.obs;

  /// True while a controller walks cloud pages to confirm source badges.
  bool confirming = false;

  bool get isDefaultQuery =>
      sortOrder.value == HistorySortOrder.viewAtDesc &&
      dateFilter.value == null;

  int? get filterFrom {
    final range = dateFilter.value;
    if (range == null) return null;
    final start = range.start;
    return DateTime(
          start.year,
          start.month,
          start.day,
        ).millisecondsSinceEpoch ~/
        Duration.millisecondsPerSecond;
  }

  int? get filterTo {
    final range = dateFilter.value;
    if (range == null) return null;
    final end = range.end;
    return DateTime(
          end.year,
          end.month,
          end.day,
          23,
          59,
          59,
        ).millisecondsSinceEpoch ~/
        Duration.millisecondsPerSecond;
  }

  void resetQuery() {
    sortOrder.value = HistorySortOrder.viewAtDesc;
    dateFilter.value = null;
    listRevision.value++;
  }

  /// Returns false when the user declined to interrupt the running sync.
  Future<bool> apply(
    BuildContext context, {
    HistorySortOrder? sort,
    DateTimeRange? date,
    bool clearDate = false,
  }) async {
    final targetSort = sort ?? sortOrder.value;
    final targetDate = clearDate ? null : (date ?? dateFilter.value);
    if (targetSort == sortOrder.value && targetDate == dateFilter.value) {
      return true;
    }

    // A filtered view of a half-synced box would be incomplete.
    final targetIsDefault =
        targetSort == HistorySortOrder.viewAtDesc && targetDate == null;
    if (!targetIsDefault && localHistory.sessionState.isSyncing.value) {
      final confirmed = await showConfirmDialog(
        context: context,
        title: const Text('终止云端同步？'),
        content: const Text(
          '云端历史记录正在同步中，使用排序或日期筛选会终止同步。\n已同步到本地的记录会保留，下次进入页面将重新同步。',
        ),
      );
      if (!confirmed) return false;
      localHistory.cancelActiveSync();
    }

    sortOrder.value = targetSort;
    dateFilter.value = targetDate;
    listRevision.value++;
    return true;
  }
}
