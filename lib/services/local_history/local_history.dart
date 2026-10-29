import 'package:PiliPlus/http/user.dart';
import 'package:PiliPlus/services/local_history/local_history_repository.dart';
import 'package:PiliPlus/utils/storage.dart';

/// The repository bound to the app's storage and the history API.
final LocalHistoryRepository localHistory = LocalHistoryRepository(
  box: GStorage.forkLocalHistory,
  cache: GStorage.localCache,
  fetchPage: (cursor) => UserHttp.historyList(
    type: 'all',
    max: cursor?.max,
    viewAt: cursor?.viewAt,
    business: cursor?.business,
  ),
  deleteKids: UserHttp.delHistory,
  clearCloud: UserHttp.clearHistory,
);
