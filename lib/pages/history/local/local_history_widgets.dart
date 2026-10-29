import 'package:PiliPlus/models_new/history/list.dart';
import 'package:PiliPlus/pages/history/local/local_history_state.dart';
import 'package:PiliPlus/services/local_history/local_history.dart';
import 'package:PiliPlus/services/local_history/local_history_repository.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

/// Cloud/local icon in the top-left corner of a cover; hidden while the scan
/// that decides it is still running.
class LocalHistorySourceBadge extends StatelessWidget {
  const LocalHistorySourceBadge({
    super.key,
    required this.state,
    required this.item,
  });

  final LocalHistoryState state;
  final HistoryItemModel item;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      state.badgeRevision.value;
      final source = localHistory.resolveSource(item);
      if (source == LocalHistorySource.unknown) {
        return const SizedBox.shrink();
      }
      return Positioned(
        top: 6,
        left: 6,
        child: Icon(
          source == LocalHistorySource.cloud
              ? Icons.cloud_outlined
              : Icons.storage_outlined,
          size: 14,
          color: Colors.white.withValues(alpha: 0.85),
          shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
        ),
      );
    });
  }
}

class LocalHistorySyncBar extends StatelessWidget {
  const LocalHistorySyncBar({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    final state = localHistory.sessionState;
    return Obx(() {
      final syncing = state.isSyncing.value;
      final failed = state.syncFailed.value;
      final pages = state.syncedPages.value;

      final String? text;
      final Color fg;
      final Color bg;
      if (syncing) {
        text = pages > 0 ? '正在同步云端记录… 已同步 $pages 页' : '正在同步云端记录…';
        fg = colorScheme.primary;
        bg = colorScheme.primaryContainer.withValues(alpha: 0.3);
      } else if (failed) {
        text = '同步失败，下拉刷新可重试';
        fg = colorScheme.error;
        bg = colorScheme.errorContainer.withValues(alpha: 0.3);
      } else {
        text = null;
        fg = colorScheme.primary;
        bg = colorScheme.primaryContainer;
      }

      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, animation) => SizeTransition(
          sizeFactor: animation,
          alignment: Alignment.topCenter,
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: text == null
            ? const SizedBox(key: ValueKey('none'), width: double.infinity)
            : Container(
                key: ValueKey(syncing),
                width: double.infinity,
                color: bg,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  spacing: 10,
                  children: [
                    if (syncing)
                      SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(fg),
                        ),
                      )
                    else
                      Icon(Icons.error_outline, size: 16, color: fg),
                    Expanded(
                      child: Text(
                        text,
                        style: TextTheme.of(
                          context,
                        ).bodySmall?.copyWith(color: fg),
                      ),
                    ),
                  ],
                ),
              ),
      );
    });
  }
}

class LocalHistoryFilterButton extends StatelessWidget {
  const LocalHistoryFilterButton({super.key, required this.state});

  final LocalHistoryState state;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: '排序与筛选',
      onPressed: () => showModalBottomSheet(
        context: context,
        builder: (_) => _FilterSheet(state: state),
      ),
      icon: Obx(
        () => Badge(
          isLabelVisible: !state.isDefaultQuery,
          smallSize: 8,
          child: const Icon(Icons.filter_list_outlined),
        ),
      ),
    );
  }
}

class _FilterSheet extends StatelessWidget {
  const _FilterSheet({required this.state});

  final LocalHistoryState state;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _fmt(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final titleStyle = TextTheme.of(context).titleSmall;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 8,
          children: [
            Text('排序方式', style: titleStyle),
            Obx(() {
              final current = state.sortOrder.value;
              return Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('最新优先'),
                    selected: current == HistorySortOrder.viewAtDesc,
                    onSelected: (_) => state.apply(
                      context,
                      sort: HistorySortOrder.viewAtDesc,
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('最早优先'),
                    selected: current == HistorySortOrder.viewAtAsc,
                    onSelected: (_) => state.apply(
                      context,
                      sort: HistorySortOrder.viewAtAsc,
                    ),
                  ),
                ],
              );
            }),
            const SizedBox(height: 12),
            Text('日期范围', style: titleStyle),
            Obx(() {
              final current = state.dateFilter.value;
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);

              DateTimeRange lastDays(int days) => DateTimeRange(
                start: today.subtract(Duration(days: days - 1)),
                end: today,
              );
              bool matches(DateTimeRange preset) =>
                  current != null &&
                  _sameDay(current.start, preset.start) &&
                  _sameDay(current.end, preset.end);

              final presets = {
                '今天': lastDays(1),
                '最近7天': lastDays(7),
                '最近30天': lastDays(30),
              };
              final isCustom = current != null && !presets.values.any(matches);

              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('全部'),
                    selected: current == null,
                    onSelected: (_) => state.apply(context, clearDate: true),
                  ),
                  for (final MapEntry(:key, :value) in presets.entries)
                    ChoiceChip(
                      label: Text(key),
                      selected: matches(value),
                      onSelected: (_) => state.apply(context, date: value),
                    ),
                  ChoiceChip(
                    label: Text(
                      isCustom
                          ? '${_fmt(current.start)} ~ ${_fmt(current.end)}'
                          : '自定义…',
                    ),
                    selected: isCustom,
                    onSelected: (_) => _pickCustomRange(context),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCustomRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2016),
      lastDate: now,
      initialDateRange:
          state.dateFilter.value ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 6)),
            end: now,
          ),
    );
    if (picked != null && context.mounted) {
      await state.apply(context, date: picked);
    }
  }
}
