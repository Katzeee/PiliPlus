import 'package:PiliPlus/models_new/history/history.dart';
import 'package:PiliPlus/models_new/history/list.dart';

/// A persisted row of the local history, scoped to one account.
class LocalHistoryItem {
  LocalHistoryItem({
    required this.accountMid,
    required this.business,
    required this.kid,
    required this.syncedAt,
    this.title,
    this.cover,
    this.covers,
    this.uri,
    this.videos,
    this.authorName,
    this.authorMid,
    this.viewAt,
    this.progress,
    this.badge,
    this.showTitle,
    this.duration,
    this.isFav,
    this.tagName,
    this.liveStatus,
    this.oid,
    this.epid,
    this.bvid,
    this.page,
    this.cid,
  });

  final int accountMid;
  final String business;

  /// Cloud history record id, unique within [business].
  final int kid;

  /// Epoch seconds of the last upsert from the cloud.
  final int syncedAt;

  final String? title;
  final String? cover;
  final List<String>? covers;
  final String? uri;
  final int? videos;
  final String? authorName;
  final int? authorMid;
  final int? viewAt;
  final int? progress;
  final String? badge;
  final String? showTitle;
  final int? duration;
  final int? isFav;
  final String? tagName;
  final int? liveStatus;
  final int? oid;
  final int? epid;
  final String? bvid;
  final int? page;
  final int? cid;

  /// Identity of the cloud record, shared by every account.
  String get uniqueKey => '$business:$kid';

  /// Box key, unique across accounts.
  String get rowKey => '$accountMid:$uniqueKey';

  /// Returns null when the cloud item lacks a business or kid.
  static LocalHistoryItem? fromModel({
    required int accountMid,
    required HistoryItemModel item,
    required int syncedAt,
  }) {
    final history = item.history;
    final business = history.business?.trim();
    final kid = item.kid;
    if (business == null || business.isEmpty || kid == null || kid <= 0) {
      return null;
    }
    return LocalHistoryItem(
      accountMid: accountMid,
      business: business,
      kid: kid,
      syncedAt: syncedAt,
      title: item.title,
      cover: item.cover,
      covers: item.covers,
      uri: item.uri,
      videos: item.videos,
      authorName: item.authorName,
      authorMid: item.authorMid,
      viewAt: item.viewAt,
      progress: item.progress,
      badge: item.badge,
      showTitle: item.showTitle,
      duration: item.duration,
      isFav: item.isFav,
      tagName: item.tagName,
      liveStatus: item.liveStatus,
      oid: history.oid,
      epid: history.epid,
      bvid: history.bvid,
      page: history.page,
      cid: history.cid,
    );
  }

  HistoryItemModel toModel() => HistoryItemModel(
    title: title,
    cover: cover,
    covers: covers,
    uri: uri,
    history: History(
      oid: oid,
      epid: epid,
      bvid: bvid,
      page: page,
      cid: cid,
      business: business,
    ),
    videos: videos,
    authorName: authorName,
    authorMid: authorMid,
    viewAt: viewAt,
    progress: progress,
    badge: badge,
    showTitle: showTitle,
    duration: duration,
    isFav: isFav,
    kid: kid,
    tagName: tagName,
    liveStatus: liveStatus,
  );
}
