# FAHD — LG webOS Remote + Cast

One Flutter codebase for **iOS and Android**, plus a single-file browser demo
(`web-demo/index.html`) with the same look and most features.

iPhone-style dark UI, Siri-style touchpad, number pad, TV apps + inputs,
YouTube/Netflix/Live-TV launcher, and honest platform limits shown in-app.

## 1. Tech choice: why Flutter

Flutter (one Dart codebase for Android + iOS) because the app is a custom
animated utility UI with sockets — no heavy native modules needed, and the
same code ships both stores. React Native would work too (note: `moti` is
React-Native-only, so it can't be used here; the equivalent motion language
is hand-rolled with 150–300ms ease-out micro-interactions). Native Android
was rejected: it doubles the work for zero benefit here.

## 2. Connection method (verified, no invented APIs)

The exact protocol LG's own Connect SDK, PyWebOSTV and the Home Assistant
`webostv` integration use, valid for webOS 2.0 → current models:

1. **Discovery**: SSDP `M-SEARCH` to `239.255.255.250:1900`, parse
   `LOCATION`, detect LG/webOS.
2. **Socket**: `ws://TV:3000`, falling back to secure `wss://TV:3001` on
   newer firmware (TV uses a self-signed cert, accepted explicitly).
3. **Pairing**: PROMPT — TV shows Allow, key (`client-key`) is stored in
   **secure storage** (`flutter_secure_storage`), auto-reused, auto-reconnect
   with backoff on drops.
4. **Commands**: `ssap://` requests (audio/tv/media/system/launcher) +
   the input socket (`getPointerInputSocket`) for cursor AND all remote
   buttons (`UP/DOWN/LEFT/RIGHT/ENTER/HOME/BACK/0-9/colors/...`), IME for
   text, `listApps`/`getForegroundAppInfo`, `getExternalInputList`/
   `switchInput`, channel APIs.

**If pairing fails**: on the TV enable **“LG Connect Apps”**
(Settings → Network) or **Mobile TV On** (older models). Ports 3000/3001
TCP must be reachable on the same LAN.

**Bluetooth**: cannot be used for TV control — LG TVs expose no Bluetooth
control API for third-party apps (BT is for headphones/soundbars). The
official path is Wi-Fi WebSocket above. No PIN bypass, no hacks.

## Requirements

- Flutter stable — https://docs.flutter.dev/get-started/install
- Phone and LG TV on the **same Wi-Fi**
- LG webOS TV (webOS 2.0+). Pre-webOS Netcast is not supported.
- iPhone builds require **macOS + Xcode**. Android builds work from anywhere.
- No official LG SDK/API key needed — the TV-side protocol is the open
  documented one above.

## Run

```sh
flutter pub get
flutter test
flutter run
```

First launch: tap **Scan for TVs** (or enter the IP from
TV Settings → Network), then accept **Allow** on the TV screen.
The pairing key (secure storage) and the last TV IP are saved — next
launch reconnects alone. **Forget saved TV** wipes them.

No-TV testing: `dart run tools/mock_tv.dart` (needs a Dart SDK), then
point the app at your machine's LAN IP.

## Permissions

Android (`android/app/src/main/AndroidManifest.xml` — injected automatically
by CI, add manually for local builds):

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE"/>
<uses-permission android:name="android.permission.CHANGE_WIFI_MULTICAST_STATE"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
```

The app asks for location **once** to read the Wi-Fi name
(`network_info_plus`). IP and subnet check work without it.

iOS (`ios/Runner/Info.plist`):

```xml
<key>NSLocalNetworkUsageDescription</key>
<string>FAHD uses your local network to discover and control your LG TV.</string>
```

## Project map

```text
lib/main.dart                  # UI: Connect / Remote / Cast + settings rows
lib/lg_tv.dart                 # connection service (socket, pairing, reconnect)
lib/core/protocol/             # pure testable protocol builders
lib/services/sound_service.dart # UI sounds (never crashes UI)
lib/theme/ + lib/widgets/      # iOS tokens, press/stagger motion
test/protocol_test.dart        # pure unit tests (no device needed)
tools/mock_tv.dart             # fake TV for manual testing
tools/verify.py                # static checks without Flutter
web-demo/index.html            # single-file browser twin
```

## Testing

```sh
flutter test            # pure protocol unit tests
python3 tools/verify.py # static checks (no Flutter needed)
```

## Release APK

Push to `main` → GitHub Actions runs format, analyzer, tests, then
`flutter build apk --release` and uploads **`fahd-release-apk`**.
Download it from the Actions tab.

## Honest limitations (also shown in-app)

- Same Wi-Fi required. No way around it.
- Power-ON remotely needs Wake-on-LAN (wired TV + TV setting); the app can
  only power off. No mirroring beyond media URLs on iOS third-party apps.
- Local phone media needs a direct URL the TV can reach.
- iPhone builds need macOS + Xcode + Apple Developer account for devices.
- A feature the protocol doesn't expose is left out, not faked.
