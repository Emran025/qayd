import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qayd/presentation/pages/pos/widgets/pos_workspace_action_card.dart';

void main() {
  testWidgets('uses a forward chevron in RTL and invokes its action',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: PosWorkspaceActionCard(
              icon: Icons.inventory_2_outlined,
              title: 'Products',
              subtitle: 'Catalog',
              accent: Colors.teal,
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);
    await tester.tap(find.text('Products'));
    expect(tapped, isTrue);
  });
}
