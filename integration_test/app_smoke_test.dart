import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wyd/src/ui/wyd_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('boots the app harness', (tester) async {
    await tester.pumpWidget(const WydApp());

    expect(find.text("What's ya doin?"), findsOneWidget);
  });
}
