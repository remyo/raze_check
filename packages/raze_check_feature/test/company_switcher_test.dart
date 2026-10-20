import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raze_check_feature/raze_check_feature.dart';

void main() {
  testWidgets('company switcher without a subtitle has a 48 pixel tap target', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: CheckTheme.light(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 240,
              child: CompanySwitcher(
                companies: const [],
                selected: null,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byKey(const Key('company-switcher'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(find.byTooltip('Switch company'), findsOneWidget);
  });
}
