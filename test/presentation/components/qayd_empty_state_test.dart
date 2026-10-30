import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/presentation/components/atomic/qayd_empty_state.dart';
import 'package:qayd/presentation/theme/app_theme.dart';

void main() {
  testWidgets('renders and invokes an optional action', (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: QaydEmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'No items',
            description: 'Add an item to begin.',
            action: FilledButton(
              onPressed: () => tapped = true,
              child: const Text('Add item'),
            ),
          ),
        ),
      ),
    );

    expect(find.text('No items'), findsOneWidget);
    expect(find.text('Add an item to begin.'), findsOneWidget);
    await tester.tap(find.text('Add item'));
    expect(tapped, isTrue);
  });
}
