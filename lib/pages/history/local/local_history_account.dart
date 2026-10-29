import 'dart:async';

import 'package:PiliPlus/pages/history/local/local_history_state.dart';
import 'package:PiliPlus/services/local_history/local_history.dart';
import 'package:PiliPlus/utils/accounts.dart';
import 'package:get/get.dart';

int? _currentMid;

/// Keeps the local history on the account [Accounts.history] points to.
///
/// Call it at startup and after anything that can change that account (login,
/// logout, account switch, import). When the account differs from the one the
/// runtime state belongs to, the state is dropped and a sync starts for the new
/// account; an open history page reloads.
void refreshLocalHistoryAccount() {
  final mid = Accounts.history.mid;
  if (mid == _currentMid) return;
  _currentMid = mid;
  localHistory.resetRuntimeState();
  if (mid != 0) {
    unawaited(localHistory.startSync(accountMid: mid));
  }
  if (Get.isRegistered<LocalHistoryState>()) {
    Get.find<LocalHistoryState>().listRevision.value++;
  }
}
