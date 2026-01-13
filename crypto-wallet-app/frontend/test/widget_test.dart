// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:crypto_wallet_pro/app.dart';

void main() {
  testWidgets('App builds smoke test', (WidgetTester tester) async {
    // Wrap app with ProviderScope for Riverpod
    await tester.pumpWidget(const ProviderScope(child: CryptoWalletProApp()));

    // Basic smoke: AppBar title 'Receive' may not be visible until navigation,
    // but ensure the widget tree builds without throwing.
    expect(find.byType(CryptoWalletProApp), findsOneWidget);
  });
}
