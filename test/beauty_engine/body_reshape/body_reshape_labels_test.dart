import 'package:editaiapp/features/editor/beauty_engine/body_reshape/models/legacy_body_parameter_adapter.dart';
import 'package:editaiapp/features/editor/beauty_engine/l10n/body_reshape_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reset body menu has no labels or specs', () {
    expect(LegacyBodyParameterAdapter.supportedParameterKeys, isEmpty);
    expect(LegacyBodyParameterAdapter.controlSpecs, isEmpty);
    expect(BodyReshapeLabels.parameterLabelPt, isEmpty);
    expect(BodyReshapeLabels.controlLimitHint('waist_slim'), isNull);
    expect(BodyReshapeLabels.emptyToolsHint, isNotEmpty);
  });
}
