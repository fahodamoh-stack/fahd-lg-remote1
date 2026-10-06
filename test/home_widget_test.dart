import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fahd_lg_remote/main.dart';

Future<void> pumpApp(WidgetTester t) async {
  await t.pumpWidget(const LgRemoteApp());
  await t.pumpAndSettle();
}

/// ListViews build lazily — scroll like a user before asserting
/// on anything below the fold.
Future<void> scrollTo(WidgetTester t, Finder f) async {
  await t.scrollUntilVisible(f, 400);
  await t.pumpAndSettle();
}

void main() {
  group('home screen', () {
    testWidgets('shows brand, tabs and offline status', (t) async {
      await pumpApp(t);
      expect(find.text('FAHD'), findsWidgets);
      expect(find.byKey(const Key('segTabs')), findsOneWidget);
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Remote'), findsOneWidget);
      expect(find.text('Cast'), findsOneWidget);
      expect(find.text('OFFLINE'), findsOneWidget);
      expect(find.textContaining('Not connected'), findsOneWidget);
    });

    testWidgets('connect tab: network card + scan + manual IP',
        (t) async {
      await pumpApp(t);
      expect(find.text('Network'), findsOneWidget);
      expect(find.text('Phone IP'), findsOneWidget);
      expect(find.text('Wi-Fi name'), findsOneWidget);
      await scrollTo(t, find.byKey(const Key('scanBtn')));
      expect(find.byKey(const Key('scanBtn')), findsOneWidget);
      expect(find.text('Found TVs'), findsOneWidget);
      await scrollTo(t, find.byKey(const Key('tvIpField')));
      expect(find.byKey(const Key('tvIpField')), findsOneWidget);
      expect(find.byKey(const Key('pairBtn')), findsOneWidget);
      expect(find.text('Connect & Pair'), findsOneWidget);
    });

    testWidgets('can switch tabs via segmented control', (t) async {
      await pumpApp(t);
      await t.tap(find.text('Remote'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('touchpad')), findsOneWidget);
      expect(find.text('Direction pad'), findsOneWidget);
      await scrollTo(t, find.byKey(const Key('volumeSlider')));
      expect(find.byKey(const Key('volumeSlider')), findsOneWidget);
      expect(find.text('Volume'), findsOneWidget);
      await scrollTo(t, find.byKey(const Key('app_Netflix')));
      expect(find.text('Apps'), findsOneWidget);
      expect(find.byKey(const Key('app_Netflix')), findsOneWidget);
      await t.tap(find.text('Cast'));
      await t.pumpAndSettle();
      expect(find.text('Cast YouTube'), findsOneWidget);
      expect(find.text('Play on TV'), findsOneWidget);
      expect(find.text('Open on TV'), findsOneWidget);
    });

    testWidgets('key controls meet min touch sizes', (t) async {
      await pumpApp(t);
      await scrollTo(t, find.byKey(const Key('scanBtn')));
      final scan = t.getSize(find.byKey(const Key('scanBtn')));
      expect(scan.height, greaterThanOrEqualTo(44));
      await scrollTo(t, find.byKey(const Key('pairBtn')));
      final pair = t.getSize(find.byKey(const Key('pairBtn')));
      expect(pair.height, greaterThanOrEqualTo(44));
      await t.tap(find.text('Remote'));
      await t.pumpAndSettle();
      await scrollTo(t, find.byKey(const Key('touchpad')));
      final pad = t.getSize(find.byKey(const Key('touchpad')));
      expect(pad.height, greaterThanOrEqualTo(44));
      expect(pad.width, greaterThanOrEqualTo(200));
    });

    testWidgets('remembers last TV IP across restarts', (t) async {
      SharedPreferences.setMockInitialValues(
          {'fa_last_ip': '192.168.1.50'});
      await pumpApp(t);
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      await scrollTo(t, find.byKey(const Key('tvIpField')));
      final fields = t.widgetList<TextField>(find.byType(TextField));
      expect(fields.any((f) => f.controller?.text == '192.168.1.50'),
          true);
      expect(find.text('Forget saved TV'), findsOneWidget);
    });
  });
}
