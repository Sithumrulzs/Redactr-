import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:redactr_app/main.dart';

void main() {
  // Everything past the splash screen depends on Firebase, which has no
  // real platform implementation in the widget test sandbox (the
  // initializeApp() call just hangs rather than resolving or rejecting).
  // Properly mocking FirebaseAuth/GoogleSignIn for tests is real testing
  // infrastructure disproportionate to this assignment — the Sign-in ->
  // Dashboard -> Sign-out flow is verified manually via `flutter run`
  // instead (see DEMO.md).
  testWidgets('App shows the splash animation first', (WidgetTester tester) async {
    await tester.pumpWidget(const RedactrApp());

    expect(find.byType(SvgPicture), findsOneWidget);
  });
}
