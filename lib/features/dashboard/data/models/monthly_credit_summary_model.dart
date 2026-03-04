class MonthlyCreditSummaryModel {
  final int totalIn;
  final int totalOut;
  final int netTotal;
  final int usageOut;
  final int txCount;

  const MonthlyCreditSummaryModel({
    required this.totalIn,
    required this.totalOut,
    required this.netTotal,
    required this.usageOut,
    required this.txCount,
  });

  factory MonthlyCreditSummaryModel.fromJson(Map<String, dynamic> json) {
    int toInt(dynamic value) => (value as num?)?.toInt() ?? 0;

    return MonthlyCreditSummaryModel(
      totalIn: toInt(json['total_in']),
      totalOut: toInt(json['total_out']),
      netTotal: toInt(json['net_total']),
      usageOut: toInt(json['usage_out']),
      txCount: toInt(json['tx_count']),
    );
  }

  static const MonthlyCreditSummaryModel empty = MonthlyCreditSummaryModel(
    totalIn: 0,
    totalOut: 0,
    netTotal: 0,
    usageOut: 0,
    txCount: 0,
  );
}
