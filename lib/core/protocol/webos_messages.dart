/// Pure webOS protocol helpers — no sockets, no Flutter.
/// Everything here is unit-testable without a TV.
abstract final class WebosMessages {
  // ---------- Registration ----------
  static Map<String, dynamic> buildRegisterPayload({String? savedKey}) {
    return {
      'forcePairing': false,
      'pairingType': 'PROMPT',
      if (savedKey != null) 'client-key': savedKey,
      'manifest': {
        'manifestVersion': 1,
        'appVersion': '1.1',
        'signedAppId': 'com.example.fahd',
        'appId': 'com.example.fahd',
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

  static Map<String, dynamic> buildRegisterEnvelope({String? savedKey}) => {
        'type': 'register',
        'id': 'register_0',
        'payload': buildRegisterPayload(savedKey: savedKey),
      };

  // ---------- Request envelope ----------
  static Map<String, dynamic> buildRequest(
      String id, String uri, Map<String, dynamic>? payload) {
    return {
      'id': id,
      'type': 'request',
      'uri': uri,
      'payload': payload ?? {},
    };
  }

  // ---------- SSDP ----------
  static const ssdpTarget = '239.255.255.250';
  static const ssdpPort = 1900;

  static String buildMSearch() => 'M-SEARCH * HTTP/1.1\r\n'
      'HOST: $ssdpTarget:$ssdpPort\r\n'
      'MAN: "ns=01; ns=01;"\r\n'
      'MX: 2\r\n'
      'ST: urn:schemas-upnp-org:device:MediaRenderer:1\r\n'
      '\r\n';

  /// Parse one SSDP response into {ip,name,location} or null.
  static Map<String, String>? parseSsdpResponse(String text, String senderIp) {
    final loc = RegExp(r'LOCATION:\s*(.+)', caseSensitive: false)
        .firstMatch(text)
        ?.group(1)
        ?.trim();
    if (loc == null || loc.isEmpty) return null;
    final uri = Uri.tryParse(loc);
    final host = (uri?.host ?? '').isNotEmpty ? uri!.host : senderIp;
    if (host.isEmpty) return null;
    final low = text.toLowerCase();
    final isLg =
        low.contains('lg') || low.contains('webos') || low.contains('netcast');
    return {
      'ip': host,
      'name': isLg ? 'LG webOS TV' : 'Media device',
      'location': loc,
    };
  }

  // ---------- Validation / math ----------
  static bool isValidIpv4(String s) {
    final p = s.trim().split('.');
    if (p.length != 4) return false;
    for (final o in p) {
      if (o.isEmpty) return false;
      final n = int.tryParse(o);
      if (n == null || n < 0 || n > 255) return false;
    }
    return true;
  }

  static int clampVolume(int v) => v.clamp(0, 100);

  /// Same local network? Compares first 3 octets (e.g. 192.168.1.x).
  static bool sameSubnet(String a, String b) {
    if (!isValidIpv4(a) || !isValidIpv4(b)) return false;
    return a.trim().split('.').sublist(0, 3).join('.') ==
        b.trim().split('.').sublist(0, 3).join('.');
  }

  // ---------- Pointer / input-socket frames ----------
  // Exact format per the verified input-socket protocol
  // (getPointerInputSocket): "key:value" lines ending with a blank line.
  static String pointerMoveMsg(int dx, int dy) =>
      'type:move\ndx:$dx\ndy:$dy\n\n';
  static String pointerClickMsg() => 'type:click\n\n';
  static String pointerScrollMsg(int dx, int dy) =>
      'type:scroll\ndx:$dx\ndy:$dy\n\n';
  static String pointerButtonMsg(String name) => 'type:button\nname:$name\n\n';

  /// Verified input-socket button names (up/down/left/right/ok/digits/
  /// colors/media...). Sent via [pointerButtonMsg].
  static const Map<String, String> inputButtons = {
    'up': 'UP',
    'down': 'DOWN',
    'left': 'LEFT',
    'right': 'RIGHT',
    'ok': 'ENTER',
    'home': 'HOME',
    'back': 'BACK',
    'menu': 'MENU',
    'exit': 'EXIT',
    'info': 'INFO',
    'dash': 'DASH',
    'cc': 'CC',
    'asterisk': 'ASTERISK',
    'mute': 'MUTE',
    'volUp': 'VOLUMEUP',
    'volDown': 'VOLUMEDOWN',
    'chUp': 'CHANNELUP',
    'chDown': 'CHANNELDOWN',
    'play': 'PLAY',
    'pause': 'PAUSE',
    'stop': 'STOP',
    'rewind': 'REWIND',
    'fastForward': 'FASTFORWARD',
    'red': 'RED',
    'green': 'GREEN',
    'yellow': 'YELLOW',
    'blue': 'BLUE',
    '0': '0',
    '1': '1',
    '2': '2',
    '3': '3',
    '4': '4',
    '5': '5',
    '6': '6',
    '7': '7',
    '8': '8',
    '9': '9',
  };

  /// Reconnect backoff: 2s, 4s, 8s ... capped at 30s. Pure/testable.
  static Duration backoffDelay(int attempt) {
    var a = attempt < 1 ? 1 : attempt;
    if (a > 5) a = 5; // 2<<4 = 32 already hits the cap; avoids overflow
    var s = 2 << (a - 1);
    if (s > 30) s = 30;
    return Duration(seconds: s);
  }

  /// Known webOS app IDs. Anything else launches via custom ID.
  static const Map<String, String> appIds = {
    'YouTube': 'youtube.leanback.v4',
    'Netflix': 'netflix',
    'Live TV': 'com.webos.app.livetv',
  };

  static bool isValidYouTubeUrl(String s) {
    final t = s.trim().toLowerCase();
    return t.startsWith('http://') || t.startsWith('https://');
  }
}
