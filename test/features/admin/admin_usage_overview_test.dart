import 'package:editaiapp/features/admin/data/admin_usage_overview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('junta uso real com o preço configurado de cada ferramenta', () {
    final overview = AdminUsageOverview.fromJson({
      'generated_at': '2026-10-15T19:00:00Z',
      'online_window_minutes': 15,
      'online_users': 2,
      'active_today': 8,
      'edits_today': 4,
      'edits_7d': 20,
      'edits_30d': 40,
      'completed_30d': 36,
      'failed_30d': 3,
      'credits_30d': 210,
      'editors_30d': 11,
      'credit_costs': {
        'text_to_image': 5,
        'edit_image': 7,
        'edit_model': 7,
        'remove_background': 7,
        'multi_image_base': 7,
        'multi_image_per_image': 3,
        'manual_edit': 0,
      },
      'tools': [
        {
          'operation_type': 'edit_image',
          'total': 30,
          'completed': 28,
          'failed': 2,
          'credits': 196,
        },
      ],
      'plans': [
        {'name': 'PRO', 'users': 4},
        {'name': 'Free', 'users': 12},
      ],
      'banner_clicks': [
        {'kind': 'compact', 'clicks': 8, 'people': 5},
      ],
    });

    expect(overview.onlineUsers, 2);
    expect(overview.tools.first.operationType, 'edit_image');
    expect(overview.tools.first.creditCostLabel, '7 créditos por edição');
    expect(
      overview.tools.map((tool) => tool.operationType),
      containsAll([
        'text_to_image',
        'remove_background',
        'multi_image',
        'manual_edit',
      ]),
    );
    expect(
      overview.tools.firstWhere((tool) => tool.operationType == 'multi_image').creditCostLabel,
      '7 + 3 créditos por foto',
    );
    expect(
      overview.tools.firstWhere((tool) => tool.operationType == 'manual_edit').creditCostLabel,
      'sem custo de crédito',
    );
    expect(overview.plans.first.name, 'Free');
    expect(overview.plans.first.users, 12);
    expect(overview.bannerClicks, hasLength(4));
    final compact = overview.bannerClicks.firstWhere((row) => row.kind == 'compact');
    expect(compact.people, 5);
    expect(compact.clicks, 8);
    expect(compact.clicksPerPerson, 1.6);
  });
}
