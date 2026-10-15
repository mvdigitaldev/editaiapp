import '../../../core/constants/operation_type.dart';

class AdminToolUsage {
  const AdminToolUsage({
    required this.operationType,
    required this.total,
    required this.completed,
    required this.failed,
    required this.credits,
    required this.creditCostLabel,
  });

  final String operationType;
  final int total;
  final int completed;
  final int failed;
  final int credits;
  final String creditCostLabel;

  String get label => OperationType.labelFrom(operationType);
}

class AdminPlanCount {
  const AdminPlanCount({required this.name, required this.users});

  final String name;
  final int users;
}

class AdminBannerClicks {
  const AdminBannerClicks({
    required this.kind,
    required this.clicks,
    required this.people,
  });

  final String kind;
  final int clicks;
  final int people;

  String get label => switch (kind) {
        'principal' => 'Leve suas fotos',
        'compact' => 'Desbloqueie o Pro',
        'opportunity' => 'Mais possibilidades',
        'offer' => 'Oferta especial',
        _ => kind,
      };

  double get clicksPerPerson => people == 0 ? 0 : clicks / people;
}

class AdminUsageOverview {
  const AdminUsageOverview({
    required this.generatedAt,
    required this.onlineWindowMinutes,
    required this.onlineUsers,
    required this.activeToday,
    required this.editsToday,
    required this.edits7d,
    required this.edits30d,
    required this.completed30d,
    required this.failed30d,
    required this.credits30d,
    required this.editors30d,
    required this.tools,
    required this.plans,
    required this.bannerClicks,
  });

  final DateTime? generatedAt;
  final int onlineWindowMinutes;
  final int onlineUsers;
  final int activeToday;
  final int editsToday;
  final int edits7d;
  final int edits30d;
  final int completed30d;
  final int failed30d;
  final int credits30d;
  final int editors30d;
  final List<AdminToolUsage> tools;
  final List<AdminPlanCount> plans;
  final List<AdminBannerClicks> bannerClicks;

  factory AdminUsageOverview.fromJson(Map<String, dynamic> json) {
    final costs = _asMap(json['credit_costs']);
    final used = <String, AdminToolUsage>{};

    for (final raw in _asList(json['tools'])) {
      final row = _asMap(raw);
      final type = row['operation_type'] as String? ?? 'unknown';
      if (type.isEmpty) continue;
      used[type] = AdminToolUsage(
        operationType: type,
        total: _asInt(row['total']),
        completed: _asInt(row['completed']),
        failed: _asInt(row['failed']),
        credits: _asInt(row['credits']),
        creditCostLabel: creditCostLabelFor(costs, type),
      );
    }

    for (final type in _knownOperationTypes) {
      used.putIfAbsent(
        type,
        () => AdminToolUsage(
          operationType: type,
          total: 0,
          completed: 0,
          failed: 0,
          credits: 0,
          creditCostLabel: creditCostLabelFor(costs, type),
        ),
      );
    }

    final tools = used.values.toList()
      ..sort((a, b) {
        final byTotal = b.total.compareTo(a.total);
        if (byTotal != 0) return byTotal;
        return a.label.compareTo(b.label);
      });

    final plans = _asList(json['plans']).map((raw) {
      final row = _asMap(raw);
      return AdminPlanCount(
        name: (row['name'] as String?)?.trim().isNotEmpty == true
            ? (row['name'] as String).trim()
            : 'Free',
        users: _asInt(row['users']),
      );
    }).toList()
      ..sort((a, b) => b.users.compareTo(a.users));

    final clicks = <String, AdminBannerClicks>{};
    for (final raw in _asList(json['banner_clicks'])) {
      final row = _asMap(raw);
      final kind = row['kind'] as String? ?? '';
      if (kind.isEmpty) continue;
      clicks[kind] = AdminBannerClicks(
        kind: kind,
        clicks: _asInt(row['clicks']),
        people: _asInt(row['people']),
      );
    }
    for (final kind in _bannerKinds) {
      clicks.putIfAbsent(
        kind,
        () => AdminBannerClicks(kind: kind, clicks: 0, people: 0),
      );
    }
    final bannerClicks = _bannerKinds
        .map((kind) => clicks[kind]!)
        .toList();

    return AdminUsageOverview(
      generatedAt: DateTime.tryParse(json['generated_at'] as String? ?? ''),
      onlineWindowMinutes: _asInt(json['online_window_minutes'], fallback: 60),
      onlineUsers: _asInt(json['online_users']),
      activeToday: _asInt(json['active_today']),
      editsToday: _asInt(json['edits_today']),
      edits7d: _asInt(json['edits_7d']),
      edits30d: _asInt(json['edits_30d']),
      completed30d: _asInt(json['completed_30d']),
      failed30d: _asInt(json['failed_30d']),
      credits30d: _asInt(json['credits_30d']),
      editors30d: _asInt(json['editors_30d']),
      tools: tools,
      plans: plans,
      bannerClicks: bannerClicks,
    );
  }
}

const _bannerKinds = <String>[
  'compact',
  'offer',
  'opportunity',
  'principal',
];

const _knownOperationTypes = <String>[
  'edit_image',
  'edit_model',
  'text_to_image',
  'remove_background',
  'multi_image',
  'manual_edit',
];

String creditCostLabelFor(Map<String, dynamic> costs, String operationType) {
  if (operationType == 'multi_image') {
    final base = costs['multi_image_base'];
    final extra = costs['multi_image_per_image'];
    if (base != null) {
      final extraLabel = extra == null ? '0' : '$extra';
      return '$base + $extraLabel créditos por foto';
    }
  }
  if (!costs.containsKey(operationType)) return 'preço não configurado';
  final credits = _asInt(costs[operationType]);
  if (credits == 0) return 'sem custo de crédito';
  return '$credits créditos por edição';
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

List<Object?> _asList(Object? value) {
  if (value is List) return value;
  return const [];
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}
