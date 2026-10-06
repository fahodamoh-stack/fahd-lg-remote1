import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fahd_lg_remote/main.dart';

void main() {
  group('home screen', () {
    testWidgets('shows brand, tabs and offline status', (t) async {
      await t.pumpWidget(const LgRemoteApp());
      await t.pumpAndSettle();
      expect(find.text('FAHD'), findsWidgets);
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Remote'), findsOneWidget);
      expect(find.text('Cast'), findsOneWidget);
      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.textContaining('Not connected'), findsOneWidget);
    });

    testWidgets('connect tab: scan + manual IP', (t) async {
      await t.pumpWidget(const LgRemoteApp());
      await t.pumpAndSettle();
      expect(find.text('Scan for TVs'), findsOneWidget);
      expect(find.text('Found TVs'), findsOneWidget);
      expect(find.widgetWithText(TextField, '192.168.1.50'),
          findsOneWidget);
      expect(find.text('Connect & Pair'), findsOneWidget);
    });

    testWidgets('can switch to Remote tab', (t) async {
      await t.pumpWidget(const LgRemoteApp());
      await t.pumpAndSettle();
      await t.tap(find.text('Remote'));
      await t.pumpAndSettle();
      expect(find.text('Direction pad'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
      expect(find.text('Volume'), findsOneWidget);
      expect(find.text('Apps'), findsOneWidget);
    });

    testWidgets('can switch to Cast tab', (t) async {
      await t.pumpWidget(const LgRemoteApp());
      await t.pumpAndSettle();
      await t.tap(find.text('Cast'));
      await t.pumpAndSettle();
      expect(find.text('Cast YouTube'), findsOneWidget);
      expect(find.text('Play on TV'), findsOneWidget);
      expect(find.text('Open on TV'), findsOneWidget);
    });
  });
}
