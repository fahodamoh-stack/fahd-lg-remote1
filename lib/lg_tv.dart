import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LG webOS TV client.
/// Works on most webOS TVs (2014+) over same Wi-Fi via ws://TV_IP:3000
/// Pairing is a one-time TV prompt. Key is saved locally.
class LgTv {
  WebSocketChannel? _ch;
  WebSocketChannel? _ptr;
  StreamSubscription? _sub;
  int _id = 0;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  final StreamController<LgState> _stateCtrl =
      StreamController<LgState>.broadcast();

  String? ip;
  String? clientKey;
  bool get connected => _ch != null;

  Stream<LgState> get states => _stateCtrl.stream;

  void _emit(String msg, {bool error = false}) {
    _stateCtrl.add(LgState(msg, error: error));
  }

  // ---------- Pure helpers (unit-testable, no socket) ----------
  static Map<String, dynamic> buildRegisterPayload({String? savedKey}) {
    return {
      'forcePairing': false,
      'pairingType': 'PROMPT',
      if (savedKey != null) 'client-key': savedKey,
      'manifest': {
        'manifestVersion': 1,
        'appVersion': '1.1',
        'signedAppId': 'com.example.lgremote',
        'appId': 'com.example.lgremote',
        'vendorId': '1',
        'permissions': [
          'LAUNCH',
          'LAUNCH_WEBAPP',
          'APP_TO_APP',
          'CLOSE',
          'TEST_OPEN',
          'CONTROL_AUDIO',
          'CONTROL_DISPLAY',
          'CONTROL_INPUT_JOYSTICK',
          'CONTROL_INPUT_MEDIA_RECORDING',
          'CONTROL_INPUT_MEDIA_PLAYBACK',
          'CONTROL_INPUT_TV',
          'CONTROL_POWER',
          'CONTROL_NOTIFICATIONS',
          'CONTROL_TV_SCREEN',
          'READ_APP_STATUS',
          'READ_CURRENT_CHANNEL',
          'READ_INPUT_DEVICE_LIST',
          'READ_NETWORK_STATE',
          'READ_RUNNING_APPS',
          'READ_TV_CHANNEL_LIST',
          'WRITE_NOTIFICATION_TOAST',
          'READ_POWER_STATE',
        ]
      }
    };
  }

  static Map<String, dynamic> buildRequest(
      String id, String uri, Map<String, dynamic>? payload) {
    return {
      'id': id,
      'type': 'request',
      'uri': uri,
      'payload': payload ?? {},
    };
  }

  /// Parse one SSDP response into {ip,name,location} or null.
  static Map<String, String>? parseSsdpResponse(
      String text, String senderIp) {
    final loc = RegExp(r'LOCATION:\s*(.+)', caseSensitive: false)
        .firstMatch(text)
        ?.group(1)
        ?.trim();
    if (loc == null || loc.isEmpty) return null;
    final uri = Uri.tryParse(loc);
    final host = (uri?.host ?? '').isNotEmpty ? uri!.host : senderIp;
    if (host.isEmpty) return null;
    final low = text.toLowerCase();
    final isLg = low.contains('lg') ||
        low.contains('webos') ||
        low.contains('netcast');
    return {
      'ip': host,
      'name': isLg ? 'LG webOS TV' : 'Media device',
      'location': loc,
    };
  }

  static int clampVolume(int v) => v.clamp(0, 100);

  /// Same local network? Compares first 3 octets (e.g. 192.168.1.x).
  static bool sameSubnet(String a, String b) {
    List<String> pa = a.trim().split('.'), pb = b.trim().split('.');
    if (pa.length != 4 || pb.length != 4) return false;
    for (final p in [...pa, ...pb]) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return false;
    }
    return pa.sublist(0, 3).join('.') == pb.sublist(0, 3).join('.');
  }

  // ---------- Pointer (Magic-remote cursor) message builders ----------
  // Sent over the pointer socket as plain text lines.
  static String pointerMoveMsg(int dx, int dy) =>
      'type:move\ndx:$dx\ndy:$dy\n';
  static String pointerClickMsg() => 'type:click\n';
  static String pointerScrollMsg(int dx, int dy) =>
      'type:scroll\ndx:$dx\ndy:$dy\n';
  static String pointerButtonMsg(String name) => 'type:button\nname:$name\n';

  /// Known webOS app IDs. Anything else can be launched via custom ID.
  static const Map<String, String> appIds = {
    'YouTube': 'youtube.leanback.v4',
    'Netflix': 'netflix',
    'Live TV': 'com.webos.app.livetv',
  };

  // ---------- Discovery (SSDP) ----------
  // Returns list of {ip, name, location}
  static Future<List<Map<String, String>>> discover({int seconds = 4}) async {
    final found = <String, Map<String, String>>{};
    RawDatagramSocket? sock;
    try {
      sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    } catch (_) {
      return [];
    }
    sock.broadcastEnabled = true;
    final search = 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: 239.255.255.250:1900\r\n'
        'MAN: "ns=01; ns=01;"\r\n'
        'MX: 2\r\n'
        'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
        '\r\n';
    final target = InternetAddress('239.255.255.250');
    for (var i = 0; i < 3; i++) {
      sock.send(utf8.encode(search), target, 1900);
      await Future.delayed(const Duration(milliseconds: 400));
    }
    final sub = sock.listen((e) {
      if (e == RawSocketEvent.read) {
        final dg = sock?.receive();
        if (dg == null) return;
        final text = utf8.decode(dg.data, allowMalformed: true);
        final parsed = parseSsdpResponse(text, dg.address.address);
        if (parsed == null) return;
        found[parsed['ip']!] = parsed;
      }
    });
    await Future.delayed(Duration(seconds: seconds));
    await sub.cancel();
    sock.close();
    return found.values.toList();
  }

  // ---------- Connect + pair ----------
  Future<void> connect(String tvIp) async {
    disconnect();
    ip = tvIp;
    final prefs = await SharedPreferences.getInstance();
    clientKey = prefs.getString('lg_client_key_$tvIp') ??
        prefs.getString('lg_client_key');

    final uri = Uri.parse('ws://$tvIp:3000');
    try {
      _ch = WebSocketChannel.connect(uri);
    } catch (e) {
      _emit('Cannot reach $tvIp:3000 — same Wi-Fi?', error: true);
      rethrow;
    }

    final registered = Completer<void>();
    _sub = _ch!.stream.listen((raw) {
      try {
        final m = jsonDecode(raw as String) as Map<String, dynamic>;
        final type = m['type']?.toString() ?? '';
        final id = m['id']?.toString() ?? '';

        if (type == 'registered') {
          final key = m['payload']?['client-key']?.toString();
          if (key != null && key.isNotEmpty) {
            clientKey = key;
            prefs.setString('lg_client_key', key);
            prefs.setString('lg_client_key_$tvIp', key);
          }
          if (!registered.isCompleted) registered.complete();
          _emit('Connected to $tvIp');
          return;
        }
        if (type == 'error' && id.startsWith('register')) {
          if (!registered.isCompleted) {
            registered.completeError(
                'TV refused pairing — accept the prompt on TV.');
          }
          return;
        }
        if (id.isNotEmpty && _pending.containsKey(id)) {
          _pending.remove(id)?.complete(m);
        }
      } catch (_) {}
    }, onError: (e) {
      if (!registered.isCompleted) {
        registered.completeError('Socket error: $e');
      }
      _emit('Connection error: $e', error: true);
    }, onDone: () {
      _ch = null;
      _emit('Disconnected', error: true);
    });

    final payload = buildRegisterPayload(savedKey: clientKey);
    _ch!.sink.add(jsonEncode({
      'type': 'register',
      'id': 'register_0',
      'payload': payload,
    }));

    await registered.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw TimeoutException(
          'No answer from TV — accept the pairing prompt on the TV screen.'),
    );
  }

  void disconnect() {
    try {
      _sub?.cancel();
    } catch (_) {}
    try {
      _ch?.sink.close();
    } catch (_) {}
    closePointer();
    _sub = null;
    _ch = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError('Disconnected');
    }
    _pending.clear();
  }

  Future<Map<String, dynamic>> _req(String uri,
      [Map<String, dynamic>? payload]) {
    if (_ch == null) throw StateError('Not connected');
    _id++;
    final id = 'req_$_id';
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    _ch!.sink.add(jsonEncode(buildRequest(id, uri, payload)));
    return c.future.timeout(const Duration(seconds: 8),
        onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('TV timeout: $uri');
    });
  }

  // ---------- Remote ----------
  Future<void> volumeUp() => _req('ssap://audio/volumeUp').then((_) {});
  Future<void> volumeDown() => _req('ssap://audio/volumeDown').then((_) {});
  Future<void> setVolume(int v) =>
      _req('ssap://audio/setVolume', {'volume': clampVolume(v)}).then((_) {});
  Future<void> setMuted(bool m) =>
      _req('ssap://audio/setMuted', {'muted': m}).then((_) {});
  Future<void> channelUp() => _req('ssap://tv/channelUp').then((_) {});
  Future<void> channelDown() => _req('ssap://tv/channelDown').then((_) {});
  Future<void> home() => _req('ssap://com.webos.applicationManager/launch',
      {'id': 'com.webos.app.home'}).then((_) {});
  Future<void> back() =>
      _req('ssap://com.webos.service.ime/sendEnterKey').then((_) {});
  Future<void> exitApp() async {
    try {
      await _req('ssap://com.webos.applicationManager/closeByAppId',
          {'id': '*'});
    } catch (_) {}
  }

  Future<void> sendKey(String key) async {
    try {
      await _req('ssap://com.webos.service.api/input', {'key': key});
    } catch (_) {
      await _req('ssap://system.notifications/createToast',
          {'message': key});
    }
  }

  Future<void> toast(String msg) =>
      _req('ssap://system.notifications/createToast', {'message': msg})
          .then((_) {});

  Future<void> openUrl(String url) => _req(
      'ssap://com.webos.applicationManager/open',
      {'target': url}).then((_) {});

  Future<void> launchApp(String appId, [Map<String, dynamic>? params]) =>
      _req('ssap://com.webos.applicationManager/launch', {
        'id': appId,
        if (params != null) ...params,
      }).then((_) {});

  Future<void> youtube([String? contentIdOrUrl]) {
    if (contentIdOrUrl == null || contentIdOrUrl.isEmpty) {
      return launchApp('youtube.leanback.v4');
    }
    return launchApp('youtube.leanback.v4', {
      'contentTarget': contentIdOrUrl,
    });
  }

  Future<void> netflix() => launchApp('netflix');
  Future<void> liveTv() => launchApp('com.webos.app.livetv');

  Future<void> play() => _req('ssap://media.controls/play').then((_) {});
  Future<void> pause() => _req('ssap://media.controls/pause').then((_) {});
  Future<void> stop() => _req('ssap://media.controls/stop').then((_) {});

  Future<void> powerOff() => _req('ssap://system/turnOff').then((_) {});

  // ---------- Pointer (touchpad cursor) ----------
  // Opens the TV's pointer input socket. Throws when the TV refuses
  // (older models) — callers should fall back to arrow keys.
  Future<void> connectPointer() async {
    if (_ch == null || ip == null) throw StateError('Not connected');
    closePointer();
    final res = await _req(
        'ssap://com.webos.service.networkinput/getPointerInputSocket');
    final path = res['payload']?['socketPath']?.toString() ?? '';
    if (path.isEmpty) throw StateError('Pointer not supported by this TV');
    _ptr = WebSocketChannel.connect(Uri.parse('ws://$ip:3000$path'));
  }

  void _ptrSend(String msg) {
    final p = _ptr;
    if (p == null) throw StateError('Pointer not connected');
    p.sink.add(msg);
  }

  Future<void> pointerMove(int dx, int dy) async =>
      _ptrSend(pointerMoveMsg(dx, dy));
  Future<void> pointerClick() async => _ptrSend(pointerClickMsg());
  Future<void> pointerScroll(int dx, int dy) async =>
      _ptrSend(pointerScrollMsg(dx, dy));

  void closePointer() {
    try {
      _ptr?.sink.close();
    } catch (_) {}
    _ptr = null;
  }

  bool get pointerReady => _ptr != null;

  void dispose() {
    disconnect();
    _stateCtrl.close();
  }
}

class LgState {
  final String message;
  final bool error;
  LgState(this.message, {this.error = false});
}
