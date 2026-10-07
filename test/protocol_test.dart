import 'package:flutter_test/flutter_test.dart';
import 'package:fahd_lg_remote/core/protocol/webos_messages.dart';

void main() {
  group('register', () {
    test('payload has pairing + manifest + toast permission', () {
      final p = WebosMessages.buildRegisterPayload();
      expect(p['pairingType'], 'PROMPT');
      expect(p['forcePairing'], false);
      final perms = (p['manifest'] as Map)['permissions'] as List;
      expect(perms, contains('WRITE_NOTIFICATION_TOAST'));
      expect(perms, contains('CONTROL_AUDIO'));
      expect(p.containsKey('client-key'), false);
    });
    test('keeps saved key, envelope shape', () {
      final e = WebosMessages.buildRegisterEnvelope(savedKey: 'k1');
      expect(e['type'], 'register');
      expect(e['id'], 'register_0');
      expect((e['payload'] as Map)['client-key'], 'k1');
    });
  });

  group('request envelope', () {
    test('ssap format', () {
      final r = WebosMessages.buildRequest('req_1', 'ssap://audio/volumeUp', {});
      expect(r['id'], 'req_1');
      expect(r['type'], 'request');
      expect(r['uri'], 'ssap://audio/volumeUp');
      expect(r['payload'], isA<Map>());
    });
  });

  group('ssdp', () {
    const sample = 'HTTP/1.1 200 OK\r\n'
        'SERVER: Linux UPnP LG WebOS TV\r\n'
        'LOCATION: http://192.168.1.50:8080/dd.xml\r\n\r\n';
    test('detects LG + extracts IP', () {
      final out = WebosMessages.parseSsdpResponse(sample, '192.168.1.50');
      expect(out, isNotNull);
      expect(out!['ip'], '192.168.1.50');
      expect(out['name'], 'LG webOS TV');
    });
    test('bad input -> null', () {
      expect(WebosMessages.parseSsdpResponse('garbage', '1.2.3.4'), isNull);
      expect(WebosMessages.parseSsdpResponse('', '1.2.3.4'), isNull);
      expect(
          WebosMessages.parseSsdpResponse('HTTP/1.1 200 OK\r\n\r\n', '1.2.3.4'),
          isNull);
    });
    test('non-LG generic', () {
      const o = 'HTTP/1.1 200 OK\r\nLOCATION: http://10.0.0.9/x.xml\r\n\r\n';
      expect(WebosMessages.parseSsdpResponse(o, '10.0.0.9')!['name'],
          'Media device');
    });
  });

  group('validation + math', () {
    test('ipv4', () {
      expect(WebosMessages.isValidIpv4('192.168.1.50'), true);
      expect(WebosMessages.isValidIpv4('192.168.1.999'), false);
      expect(WebosMessages.isValidIpv4('abc'), false);
      expect(WebosMessages.isValidIpv4(''), false);
    });
    test('volume clamp', () {
      expect(WebosMessages.clampVolume(-5), 0);
      expect(WebosMessages.clampVolume(50), 50);
      expect(WebosMessages.clampVolume(130), 100);
    });
    test('same subnet', () {
      expect(WebosMessages.sameSubnet('192.168.1.50', '192.168.1.7'), true);
      expect(WebosMessages.sameSubnet('192.168.1.50', '192.168.2.7'), false);
      expect(WebosMessages.sameSubnet('abc', '192.168.1.7'), false);
    });
    test('backoff grows then caps', () {
      expect(WebosMessages.backoffDelay(1), const Duration(seconds: 2));
      expect(WebosMessages.backoffDelay(2), const Duration(seconds: 4));
      expect(WebosMessages.backoffDelay(3), const Duration(seconds: 8));
      expect(WebosMessages.backoffDelay(99), const Duration(seconds: 30));
    });
  });

  group('pointer frames (blank-line terminated)', () {
    test('move/click/scroll/button', () {
      expect(WebosMessages.pointerMoveMsg(5, -3), 'type:move\ndx:5\ndy:-3\n\n');
      expect(WebosMessages.pointerClickMsg(), 'type:click\n\n');
      expect(WebosMessages.pointerScrollMsg(0, -10),
          'type:scroll\ndx:0\ndy:-10\n\n');
      expect(WebosMessages.pointerButtonMsg('HOME'), 'type:button\nname:HOME\n\n');
    });
    test('verified button names', () {
      final b = WebosMessages.inputButtons;
      expect(b['ok'], 'ENTER');
      expect(b['up'], 'UP');
      expect(b['1'], '1');
      expect(b['0'], '0');
      expect(b['red'], 'RED');
      expect(b['fastForward'], 'FASTFORWARD');
    });
  });

  group('apps', () {
    test('known IDs', () {
      expect(WebosMessages.appIds['YouTube'], 'youtube.leanback.v4');
      expect(WebosMessages.appIds['Netflix'], 'netflix');
      expect(WebosMessages.appIds['Live TV'], 'com.webos.app.livetv');
    });
  });
}
