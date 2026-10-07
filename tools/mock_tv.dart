/// Fake LG webOS TV for manual testing WITHOUT a real TV.
///
/// Run:  dart run tools/mock_tv.dart [port=3000]
/// Then in FAHD use manual IP 127.0.0.1 ... except: the app connects to
/// ws://IP:3000, so run the mock on the SAME machine and use your
/// machine's LAN IP in the app (127.0.0.1 works on emulators only).
///
/// Speaks just enough of the protocol to exercise pairing, commands,
/// app/source lists and the pointer socket. Dependency-free (dart:io).
import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final port = args.isNotEmpty ? int.tryParse(args[0]) ?? 3000 : 3000;
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  print('Mock LG TV on ws://0.0.0.0:$port  (Ctrl+C to stop)');
  await for (final req in server) {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response
        ..statusCode = HttpStatus.notFound
        ..write('mock tv: websocket only');
      await req.response.close();
      continue;
    }
    final path = req.uri.path;
    if (path.isNotEmpty && path != '/') {
      _servePointer(req, path);
    } else {
      _serveMain(await WebSocketTransformer.upgrade(req));
    }
  }
}

void _serveMain(WebSocket ws) {
  print('[main] client connected');
  ws.listen((raw) {
    Map<String, dynamic>? m;
    try {
      m = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = m['type'];
    final id = m['id']?.toString() ?? '';
    print('[main] $type ${m['uri'] ?? ''}');
    if (type == 'register') {
      ws.add(jsonEncode({
        'type': 'registered',
        'id': id,
        'payload': {'client-key': 'MOCK-KEY-123'}
      }));
      return;
    }
    if (type == 'request') {
      ws.add(jsonEncode({
        'type': 'response',
        'id': id,
        'payload': _canned(m['uri']?.toString() ?? ''),
      }));
    }
  }, onDone: () => print('[main] client left'));
}

Map<String, dynamic> _canned(String uri) {
  switch (uri) {
    case 'ssap://audio/getVolume':
      return {'returnValue': true, 'volume': 20, 'muted': false};
    case 'ssap://com.webos.applicationManager/listApps':
      return {
        'returnValue': true,
        'apps': [
          {'id': 'youtube.leanback.v4', 'title': 'YouTube'},
          {'id': 'netflix', 'title': 'Netflix'},
          {'id': 'com.webos.app.livetv', 'title': 'Live TV'},
        ]
      };
    case 'ssap://com.webos.applicationManager/getForegroundAppInfo':
      return {'returnValue': true, 'appId': 'youtube.leanback.v4'};
    case 'ssap://tv/getExternalInputList':
      return {
        'returnValue': true,
        'devices': [
          {'id': 'HDMI_1', 'label': 'HDMI 1'},
          {'id': 'HDMI_2', 'label': 'HDMI 2'},
        ]
      };
    case 'ssap://tv/getCurrentChannel':
      return {
        'returnValue': true,
        'channelNumber': '5',
        'channelId': '5_1'
      };
    case 'ssap://com.webos.service.networkinput/getPointerInputSocket':
      return {'returnValue': true, 'socketPath': '/mock-pointer'};
    default:
      return {'returnValue': true};
  }
}

void _servePointer(HttpRequest req, String path) async {
  final ws = await WebSocketTransformer.upgrade(req);
  print('[pointer] connected at $path — send moves, taps work');
  ws.listen((raw) {
    print('[pointer] ${(raw as String).replaceAll('\n', '|')}');
  }, onDone: () => print('[pointer] closed'));
}
