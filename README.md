# FAHD — LG webOS Remote + Cast

One Flutter codebase for **iOS and Android**, plus a single-file browser demo
(`web-demo/index.html`) with the same look and most features.

iPhone-style dark UI, Siri-style touchpad, YouTube/Netflix/Live-TV launcher,
and honest platform limits shown inside the app.

## Requirements

- Flutter stable (3.x) — https://docs.flutter.dev/get-started/install
- Phone and LG TV on the **same Wi-Fi**
- LG webOS TV (2014+). Very old Netcast models are not supported.
- iPhone builds require **macOS + Xcode**. Android builds work from anywhere.

## Run

```sh
flutter pub get
flutter test
flutter run
```

First launch: tap **Scan for TVs** (or enter the IP from
TV Settings → Network), then accept **Allow** on the TV screen.
The pairing key and the last TV IP are saved — next launch reconnects alone.
**Forget saved TV** wipes them.

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

## How it talks to the TV

- Discovery: SSDP `M-SEARCH` to `239.255.255.250:1900`, parse `LOCATION`,
  detect LG/webOS (`lib/core/protocol/webos_messages.dart`).
- Pairing/control: `ws://TV_IP:3000`, PROMPT pairing, `ssap://` requests.
- Touchpad cursor: `ssap://com.webos.service.networkinput/getPointerInputSocket`
  + plain-text frames (`type:move/click/button`). Falls back to arrow keys
  when the TV refuses.
- Apps: `youtube.leanback.v4`, `netflix`, `com.webos.app.livetv`,
  plus any custom App ID.

## Browser demo limits

`web-demo/index.html` needs no build. It can pair and control a TV from the
same network, but browsers **cannot** auto-scan (enter IP manually) and
**cannot** read the Wi-Fi name. Pointer support depends on the TV.

## Testing

```sh
flutter test            # protocol unit tests + widget tests
python3 tools/verify.py # static checks (no Flutter needed)
```

## Release APK

Push to `main` → GitHub Actions runs format check, analyzer, tests, then
`flutter build apk --release` and uploads **`fahd-release-apk`**.
Download it from the Actions tab.

## Honest limitations (also shown in-app)

- Same Wi-Fi required. No way around it.
- Third-party iOS apps cannot do unrestricted full-screen mirroring —
  FAHD is remote + media cast.
- Local phone media needs a direct URL the TV can reach.
- iPhone builds need macOS + Xcode + Apple Developer account for devices.
