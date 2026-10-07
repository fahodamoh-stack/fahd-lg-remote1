import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'core/protocol/webos_messages.dart';

/// LG webOS TV client.
/// Works on most webOS TVs (2014+) over same Wi-Fi via ws://TV_IP:3000
/// Pairing is a one-time TV prompt. Key is saved locally.
class LgTv {
  WebSocketChannel? _ch;
  WebSocketChannel? _ptr;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  int _id = 0;
  int _reconnectAttempt = 0;
  bool _manualDisconnect = false;
  bool _useSecure = false;
  bool autoReconnect = true;
  static const int maxReconnectAttempts = 5;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  final StreamController<LgState> _stateCtrl =
      StreamController<LgState>.broadcast();
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  String? ip;
  String? clientKey;
  bool get connected => _ch != null;

  Stream<LgState> get states => _stateCtrl.stream;

  void _emit(String msg, {bool error = false}) {
    _stateCtrl.add(LgState(msg, error: error));
  }

  // ---------- Pure helpers (single source: WebosMessages) ----------
  static Map<String, dynamic> buildRegisterPayload({String? savedKey}) =>
      WebosMessages.buildRegisterPayload(savedKey: savedKey);

  static Map<String, dynamic> buildRequest(
          String id, String uri, Map<String, dynamic>? payload) =>
      WebosMessages.buildRequest(id, uri, payload);

  /// Parse one SSDP response into {ip,name,location} or null.
  static Map<String, String>? parseSsdpResponse(String text, String senderIp) =>
      WebosMessages.parseSsdpResponse(text, senderIp);

  static int clampVolume(int v) => WebosMessages.clampVolume(v);

  /// Same local network? Compares first 3 octets (e.g. 192.168.1.x).
  static bool sameSubnet(String a, String b) => WebosMessages.sameSubnet(a, b);

  // ---------- Pointer (Magic-remote cursor) message builders ----------
  // Sent over the pointer socket as plain text lines.
  static String pointerMoveMsg(int dx, int dy) =>
      WebosMessages.pointerMoveMsg(dx, dy);
  static String pointerClickMsg() => WebosMessages.pointerClickMsg();
  static String pointerScrollMsg(int dx, int dy) =>
      WebosMessages.pointerScrollMsg(dx, dy);
  static String pointerButtonMsg(String name) =>
      WebosMessages.pointerButtonMsg(name);

  /// Known webOS app IDs. Anything else can be launched via custom ID.
  static const Map<String, String> appIds = WebosMessages.appIds;

  // ---------- Secure key storage (never plain text) ----------
  static String _keyName(String tvIp) => 'lg_client_key_$tvIp';

  Future<String?> _readKey(String tvIp) async {
    try {
      return await _secure.read(key: _keyName(tvIp)) ??
          await _secure.read(key: 'lg_client_key');
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeKey(String tvIp, String key) async {
    try {
      await _secure.write(key: 'lg_client_key', value: key);
      await _secure.write(key: _keyName(tvIp), value: key);
    } catch (_) {}
  }

  Future<void> forgetKeys() async {
    try {
      await _secure.delete(key: 'lg_client_key');
      if (ip != null) await _secure.delete(key: _keyName(ip!));
    } catch (_) {}
  }

  Future<bool> hasSavedKey(String tvIp) async =>
      (await _readKey(tvIp))?.isNotEmpty ?? false;

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
    final search = WebosMessages.buildMSearch();
    final target = InternetAddress(WebosMessages.ssdpTarget);
    for (var i = 0; i < 3; i++) {
      sock.send(utf8.encode(search), target, WebosMessages.ssdpPort);
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

  /// Opens the main socket. Throws on failure (caller tries next scheme).
  Future<void> _open(String tvIp, {required bool secure}) async {
    if (secure) {
      final client = HttpClient();
      client.badCertificateCallback = (_, __, ___) => true;
      final sock = await WebSocket.connect(
        'wss://$tvIp:3001',
        customClient: client,
      ).timeout(const Duration(seconds: 8));
      _ch = IOWebSocketChannel(sock);
    } else {
      final sock = await WebSocket.connect(
        'ws://$tvIp:3000',
      ).timeout(const Duration(seconds: 8));
      _ch = IOWebSocketChannel(sock);
    }
    _useSecure = secure;
  }

  // ---------- Connect + pair ----------
  // Plain ws://TV:3000 first; newer firmware requires secure wss://TV:3001
  // (TV uses a self-signed cert, accepted explicitly here).
  Future<void> connect(String tvIp) async {
    disconnect();
    _manualDisconnect = false;
    ip = tvIp;
    clientKey = await _readKey(tvIp);

    Object? lastErr;
    for (final secure in [false, true]) {
      try {
        await _open(tvIp, secure: secure);
        lastErr = null;
        break;
      } catch (e) {
        lastErr = e;
      }
    }
    if (lastErr != null || _ch == null) {
      _emit(
          'Cannot reach $tvIp (tried 3000 + secure 3001) — same Wi-Fi? '
          'Enable “LG Connect Apps” in TV Network settings.',
          error: true);
      throw lastErr ?? StateError('Connection failed');
    }

    final registered = Completer<void>();
    _sub = _ch!.stream.listen((raw) async {
      try {
        final m = jsonDecode(raw as String) as Map<String, dynamic>;
        final type = m['type']?.toString() ?? '';
        final id = m['id']?.toString() ?? '';

        if (type == 'registered') {
          final key = m['payload']?['client-key']?.toString();
          if (key != null && key.isNotEmpty) {
            clientKey = key;
            await _writeKey(tvIp, key);
          }
          _reconnectAttempt = 0;
          if (!registered.isCompleted) registered.complete();
          _emit('Connected to $tvIp');
          return;
        }
        if (type == 'error' && id.startsWith('register')) {
          if (!registered.isCompleted) {
            registered
                .completeError('TV refused pairing — accept the prompt on TV.');
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
      closePointer();
      for (final c in _pending.values) {
        if (!c.isCompleted) c.completeError('Disconnected');
      }
      _pending.clear();
      if (_manualDisconnect || !autoReconnect) {
        _emit('Disconnected', error: true);
        return;
      }
      _scheduleReconnect();
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

  /// Auto-reconnect with backoff after an unexpected drop.
  void _scheduleReconnect() {
    _reconnectAttempt++;
    if (_reconnectAttempt > maxReconnectAttempts || ip == null) {
      _reconnectAttempt = 0;
      _emit('Disconnected — tap Connect to retry', error: true);
      return;
    }
    final wait = WebosMessages.backoffDelay(_reconnectAttempt);
    _emit('Reconnecting in ${wait.inSeconds}s… (try $_reconnectAttempt)');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(wait, () async {
      if (_manualDisconnect || connected) return;
      try {
        await connect(ip!);
      } catch (_) {
        // connect() emits its own status; onDone reschedules if needed.
      }
    });
  }

  void disconnect() {
    _manualDisconnect = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
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
    return c.future.timeout(const Duration(seconds: 8), onTimeout: () {
      _pending.remove(id);
      throw TimeoutException('TV timeout: $uri');
    });
  }

  // ---------- Remote ----------
  // Button presses go through the input socket (verified names in
  // WebosMessages.inputButtons), with ssap fallback when the TV
  // refuses the pointer socket.
  Future<void> press(String action) async {
    final name = WebosMessages.inputButtons[action];
    if (name == null) throw ArgumentError('Unknown button: $action');
    if (pointerReady) {
      try {
        return await pointerButton(name);
      } catch (_) {}
    }
    await _req('ssap://com.webos.service.api/input', {'key': action});
  }

  Future<void> pointerButton(String name) async =>
      _ptrSend(WebosMessages.pointerButtonMsg(name));

  Future<void> volumeUp() => press('volUp')
      .catchError((_) => _req('ssap://audio/volumeUp').then((_) {}));
  Future<void> volumeDown() => press('volDown')
      .catchError((_) => _req('ssap://audio/volumeDown').then((_) {}));
  Future<void> setVolume(int v) =>
      _req('ssap://audio/setVolume', {'volume': clampVolume(v)}).then((_) {});

  Future<int> getVolume() async {
    final res = await _req('ssap://audio/getVolume');
    final v = res['payload']?['volume'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    throw StateError('No volume in response');
  }

  Future<bool> getMuted() async {
    final res = await _req('ssap://audio/getVolume');
    final m = res['payload']?['muted'];
    if (m is bool) return m;
    throw StateError('No mute state in response');
  }

  Future<void> setMuted(bool m) async {
    try {
      await _req('ssap://audio/setMute', {'mute': m});
    } catch (_) {
      await _req('ssap://audio/setMuted', {'muted': m});
    }
  }

  Future<void> channelUp() =>
      press('chUp').catchError((_) => _req('ssap://tv/channelUp').then((_) {}));
  Future<void> channelDown() => press('chDown')
      .catchError((_) => _req('ssap://tv/channelDown').then((_) {}));

  Future<dynamic> currentChannel() async {
    final res = await _req('ssap://tv/getCurrentChannel');
    return res['payload'];
  }

  Future<void> home() => launchApp('com.webos.app.home');
  Future<void> back() => press('back').catchError(
      (_) => _req('ssap://com.webos.service.ime/sendEnterKey').then((_) {}));
  Future<void> exitApp() async {
    try {
      await press('exit');
    } catch (_) {
      try {
        await _req(
            'ssap://com.webos.applicationManager/closeByAppId', {'id': '*'});
      } catch (_) {}
    }
  }

  Future<void> sendKey(String key) => press(key);

  /// Sends text via the on-screen keyboard (IME). The TV must show
  /// a text field for keystrokes to land.
  Future<void> typeText(String text) => _req(
      'ssap://com.webos.service.ime/insertText',
      {'text': text, 'replace': 0}).then((_) {});
  Future<void> deleteChars(int count) =>
      _req('ssap://com.webos.service.ime/deleteCharacters', {'count': count})
          .then((_) {});
  Future<void> sendEnter() =>
      _req('ssap://com.webos.service.ime/sendEnterKey').then((_) {});

  Future<void> toast(String msg) =>
      _req('ssap://system.notifications/createToast', {'message': msg})
          .then((_) {});

  Future<void> openUrl(String url) =>
      _req('ssap://com.webos.applicationManager/open', {'target': url})
          .then((_) {});

  Future<void> launchApp(String appId, [Map<String, dynamic>? params]) =>
      _req('ssap://system.launcher/launch', {
        'id': appId,
        if (params != null) ...params,
      }).then((_) {});

  /// Installed apps on the TV: [{id, title, ...}].
  Future<List<Map<String, dynamic>>> listApps() async {
    final res = await _req('ssap://com.webos.applicationManager/listApps');
    final apps = res['payload']?['apps'];
    if (apps is List) {
      return apps
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    throw StateError('TV did not return an app list');
  }

  /// Foreground app id, e.g. "youtube.leanback.v4".
  Future<String?> foregroundApp() async {
    try {
      final res = await _req(
          'ssap://com.webos.applicationManager/getForegroundAppInfo');
      return res['payload']?['appId']?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> closeApp(String appId) =>
      _req('ssap://system.launcher/close', {'id': appId}).then((_) {});

  /// TV inputs/sources: [{id, label, ...}].
  Future<List<Map<String, dynamic>>> listSources() async {
    final res = await _req('ssap://tv/getExternalInputList');
    final devs = res['payload']?['devices'];
    if (devs is List) {
      return devs
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    throw StateError('TV did not return inputs');
  }

  Future<void> setSource(String inputId) =>
      _req('ssap://tv/switchInput', {'inputId': inputId}).then((_) {});

  Future<void> youtube([String? contentIdOrUrl]) {
    if (contentIdOrUrl == null || contentIdOrUrl.isEmpty) {
      return launchApp('youtube.leanback.v4');
    }
    return launchApp('youtube.leanback.v4', {
      'contentId': contentIdOrUrl,
    });
  }

  Future<void> netflix() => launchApp('netflix');
  Future<void> liveTv() => launchApp('com.webos.app.livetv');

  Future<void> play() => press('play')
      .catchError((_) => _req('ssap://media.controls/play').then((_) {}));
  Future<void> pause() => press('pause')
      .catchError((_) => _req('ssap://media.controls/pause').then((_) {}));
  Future<void> stop() => press('stop')
      .catchError((_) => _req('ssap://media.controls/stop').then((_) {}));
  Future<void> rewind() => _req('ssap://media.controls/rewind').then((_) {});
  Future<void> fastForward() =>
      _req('ssap://media.controls/fastForward').then((_) {});

  Future<void> powerOff() => _req('ssap://system/turnOff').then((_) {});

  // ---------- Pointer (touchpad cursor + input buttons) ----------
  // Opens the TV's pointer input socket. Throws when the TV refuses
  // (older models) — callers should fall back to arrow keys.
  Future<void> connectPointer() async {
    if (_ch == null || ip == null) throw StateError('Not connected');
    closePointer();
    final res = await _req(
        'ssap://com.webos.service.networkinput/getPointerInputSocket');
    final path = res['payload']?['socketPath']?.toString() ?? '';
    if (path.isEmpty) throw StateError('Pointer not supported by this TV');
    if (_useSecure) {
      final client = HttpClient();
      client.badCertificateCallback = (_, __, ___) => true;
      final sock = await WebSocket.connect(
        'wss://$ip:3001$path',
        customClient: client,
      ).timeout(const Duration(seconds: 8));
      _ptr = IOWebSocketChannel(sock);
    } else {
      _ptr = WebSocketChannel.connect(Uri.parse('ws://$ip:3000$path'));
    }
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
