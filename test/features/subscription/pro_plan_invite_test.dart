import 'package:editaiapp/features/subscription/presentation/pro_plan_invite.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a cada 3 edições manuais oferece o plano', () {
    expect(shouldOfferAfterManualEdits(count: 0, every: 3), isFalse);
    expect(shouldOfferAfterManualEdits(count: 1, every: 3), isFalse);
    expect(shouldOfferAfterManualEdits(count: 2, every: 3), isFalse);
    expect(shouldOfferAfterManualEdits(count: 3, every: 3), isTrue);
    expect(shouldOfferAfterManualEdits(count: 4, every: 3), isFalse);
    expect(shouldOfferAfterManualEdits(count: 6, every: 3), isTrue);
  });

  test('intervalo 0 desliga o convite principal', () {
    expect(shouldOfferAfterManualEdits(count: 4, every: 0), isFalse);
    expect(shouldOfferAfterManualEdits(count: 4, every: 4), isTrue);
  });
}
