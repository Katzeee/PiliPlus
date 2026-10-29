class HistoryCursor {
  int? max;
  int? viewAt;
  String? business;

  HistoryCursor({this.max, this.viewAt, this.business});

  factory HistoryCursor.fromJson(Map<String, dynamic> json) => HistoryCursor(
    max: json['max'] as int?,
    viewAt: json['view_at'] as int?,
    business: json['business'] as String?,
  );
}
