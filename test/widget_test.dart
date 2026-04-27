import 'package:flutter_test/flutter_test.dart';
import 'package:wyd/src/ui/wyd_app.dart';

void main() {
  testWidgets('boots the minimal wyd shell', (tester) async {
    await tester.pumpWidget(const WydApp());

    expect(find.text('wyd'), findsOneWidget);
    expect(find.text("What's ya doin?"), findsOneWidget);
    expect(find.textContaining('Domain core is ready'), findsOneWidget);
  });
}
