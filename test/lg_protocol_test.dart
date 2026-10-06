import 'package:flutter_test/flutter_test.dart';
import 'package:lg_remote/lg_tv.dart';

void main() {
  group('register payload', () {
    test('contains pairing + manifest + toast permission', () {
      final p = LgTv.buildRegisterPayload();
      expect(p['pairingType'], 'PROMPT');
      expect(p['forcePairing'], false);
      final perms =
          (p['manifest'] as Map)['permissions'] as List;
      expect(perms, contains('WRITE_NOTIFICATION_TOAST'));
      expect(perms, contains('CONTROL_AUDIO'));
      expect(p.containsKey('client-key'), false);
    });

    test('keeps saved client-key', () {
      final p = LgTv.buildRegisterPayload(savedKey: 'abc123');
      expect(p['client-key'], 'abc123');
    });
  });

  group('request builder', () {
    test('ssap envelope format', () {
      final r = LgTv.buildRequest('req_1', 'ssap://audio/volumeUp', {});
      expect(r['id'], 'req_1');
      expect(r['type'], 'request');
      expect(r['uri'], 'ssap://audio/volumeUp');
      expect(r['payload'], isA<Map>());
    });
  });

  group('ssdp parse', () {
    const sample = 'HTTP/1.1 200 OK\r\n'
        'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
        'USN: uuid:lg-tv\r\n'
        'SERVER: Linux UPnP/1.0 LG WebOS TV\r\n'
        'LOCATION: http://192.168.1.50:8080/dd.xml\r\n\r\n';

    test('detects LG + extracts IP', () {
      final out = LgTv.parseSsdpResponse(sample, '192.168.1.50');
      expect(out, isNotNull);
      expect(out!['ip'], '192.168.1.50');
      expect(out['name'], 'LG webOS TV');
    });

    test('bad response -> null', () {
      expect(LgTv.parseSsdpResponse('garbage', '1.2.3.4'), isNull);
      expect(LgTv.parseSsdpResponse('', '1.2.3.4'), isNull);
    });

    test('non-LG labeled generic', () {
      const other = 'HTTP/1.1 200 OK\r\nLOCATION: http://10.0.0.9:80/x.xml\r\n\r\n';
      final out = LgTv.parseSsdpResponse(other, '10.0.0.9');
      expect(out!['name'], 'Media device');
    });
  });

  group('volume', () {
    test('clamp 0..100', () {
      expect(LgTv.clampVolume(-5), 0);
      expect(LgTv.clampVolume(50), 50);
      expect(LgTv.clampVolume(130), 100);
    });
  });
}
