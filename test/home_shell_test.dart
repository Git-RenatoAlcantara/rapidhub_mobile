import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rapidhubmobile/widgets/app_bottom_nav.dart';
import 'package:rapidhubmobile/widgets/home_shell.dart';

void main() {
  testWidgets('barra inferior aparece fora do layout de desktop',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(bottomNavigationBar: AppBottomNav(currentIndex: 1)),
    ));

    expect(find.text('Pedidos'), findsOneWidget);
    expect(find.text('Conversas'), findsOneWidget);
  });

  testWidgets('barra inferior some dentro do layout de desktop',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DesktopScope(
        child: Scaffold(bottomNavigationBar: AppBottomNav(currentIndex: 1)),
      ),
    ));

    expect(find.text('Pedidos'), findsNothing);
    expect(find.text('Conversas'), findsNothing);
  });
}
